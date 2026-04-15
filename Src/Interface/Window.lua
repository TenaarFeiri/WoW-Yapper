--[[
    Interface/Window.lua
    Main settings window creation, scrollable content area, scrollbar,
    welcome choice frame, sidebar, font scaling, and position persistence.
]]

local YapperName, YapperTable = ...
local Interface      = YapperTable.Interface

-- Re-localise shared helpers from hub.
local IsAnchorPoint  = Interface.IsAnchorPoint
local LAYOUT         = Interface._LAYOUT
local CATEGORIES     = Interface._CATEGORIES
local LayoutCursor   = Interface._LayoutCursor

-- Re-localise Lua globals.
local type       = type
local ipairs     = ipairs
local math_abs   = math.abs
local math_floor = math.floor
local math_max   = math.max
local tinsert    = table.insert
local tostring   = tostring

-- Even-increment offsets (re-exported from hub for local use).
local UI_FONT_STEP       = Interface._UI_FONT_STEP
local UI_FONT_MIN_OFFSET = Interface._UI_FONT_MIN_OFFSET
local UI_FONT_MAX_OFFSET = Interface._UI_FONT_MAX_OFFSET

function Interface:GetMainWindowPositionStore()
    -- Stored per-character under local config root.
    local root = self:GetLocalConfigRoot()
    if type(root.FrameSettings) ~= "table" then
        root.FrameSettings = {}
    end
    if type(root.FrameSettings.MainWindowPosition) ~= "table" then
        root.FrameSettings.MainWindowPosition = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = 0,
        }
    end
    return root.FrameSettings.MainWindowPosition
end

function Interface:SaveMainWindowPosition(frame)
    -- Persist only anchor + offsets; size is static elsewhere.
    if not frame or not frame.GetPoint then return end

    local point, _, relativePoint, xOfs, yOfs = frame:GetPoint(1)
    if not IsAnchorPoint(point) then point = "CENTER" end
    if not IsAnchorPoint(relativePoint) then relativePoint = point end
    xOfs = tonumber(xOfs) or 0
    yOfs = tonumber(yOfs) or 0

    local store = self:GetMainWindowPositionStore()
    store.point = point
    store.relativePoint = relativePoint
    store.x = xOfs
    store.y = yOfs
end

function Interface:ApplyMainWindowPosition(frame)
    -- Apply saved anchor safely with validation fallbacks.
    if not frame or not frame.SetPoint then return end

    local store = self:GetMainWindowPositionStore()
    local point = IsAnchorPoint(store.point) and store.point or "CENTER"
    local relativePoint = IsAnchorPoint(store.relativePoint) and store.relativePoint or point
    local xOfs = tonumber(store.x) or 0
    local yOfs = tonumber(store.y) or 0

    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, relativePoint, xOfs, yOfs)
end

-- ---------------------------------------------------------------------------
-- Frame functions
-- ---------------------------------------------------------------------------

-- Create the scrollable content area inside a parent window frame.
-- The content sits to the right of the sidebar.
local function CreateScrollableContent(parent)
    local P = LAYOUT
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
    parent.ScrollFrame = scrollFrame
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", P.SIDEBAR_WIDTH + P.WINDOW_PADDING, -P.TITLE_INSET)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT",
        -(P.WINDOW_PADDING + P.SCROLLBAR_WIDTH + P.SCROLLBAR_GAP), P.BOTTOM_BAR)
    scrollFrame:SetClipsChildren(true)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    content:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 0, 0)
    content:SetHeight(1000)
    parent.ContentFrame = content

    -- Keep content width in sync with the scroll viewport.
    local function UpdateContentWidth()
        content:SetWidth(scrollFrame:GetWidth())
    end
    scrollFrame:SetScript("OnSizeChanged", UpdateContentWidth)
    UpdateContentWidth()
    scrollFrame:SetScrollChild(content)

    -- Mouse wheel support.
    scrollFrame:EnableMouse(true)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local step = tonumber(Interface:GetConfigPath({ "FrameSettings", "MouseWheelStepRate" }))
            or Interface.MouseWheelStepRate
        local cur = self:GetVerticalScroll()
        local maxv = self:GetVerticalScrollRange()
        local nxt = math_min(maxv, math_max(0, cur - delta * step))
        self:SetVerticalScroll(nxt)
        if self.ScrollBar and self.ScrollBar:IsShown() then
            self.ScrollBar:SetValue(nxt)
        end
    end)
    scrollFrame:SetScript("OnHorizontalScroll", function(self) self:SetHorizontalScroll(0) end)

    return scrollFrame, content
end

-- Attach a scrollbar to a parent frame that drives an existing ScrollFrame.
local function CreateScrollBarForFrame(parent, scrollFrame)
    local P = LAYOUT
    local scrollBar = CreateFrame("Slider", nil, parent, "UIPanelScrollBarTemplate")
    parent.ScrollBar = scrollBar
    scrollFrame.ScrollBar = scrollBar

    scrollBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -P.WINDOW_PADDING, -P.SCROLLBAR_TOP_INSET)
    scrollBar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -P.WINDOW_PADDING, P.SCROLLBAR_BOTTOM_INSET)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValueStep(1)
    scrollBar:SetObeyStepOnDrag(true)
    scrollBar:SetWidth(P.SCROLLBAR_WIDTH)

    local function UpdateVisibility(yRange)
        yRange = math_max(0, yRange or 0)
        local needsScroll = yRange > 0
        scrollBar:SetMinMaxValues(0, yRange)
        scrollBar:SetShown(needsScroll)
        if not needsScroll then
            scrollFrame:SetVerticalScroll(0)
            scrollBar:SetValue(0)
        else
            local cur = scrollFrame:GetVerticalScroll()
            if cur > yRange then
                scrollFrame:SetVerticalScroll(yRange)
                scrollBar:SetValue(yRange)
            end
        end
    end

    scrollBar:SetScript("OnValueChanged", function(_, value)
        scrollFrame:SetVerticalScroll(value)
    end)
    scrollFrame:SetScript("OnScrollRangeChanged", function(_, _, yRange)
        UpdateVisibility(yRange)
    end)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        self:SetVerticalScroll(offset)
        if scrollBar:IsShown() then scrollBar:SetValue(offset) end
    end)

    scrollFrame:UpdateScrollChildRect()
    UpdateVisibility(scrollFrame:GetVerticalScrollRange())
    return scrollBar
end

-- Active sidebar category — persists for the session.
Interface._activeCategory = "general"

-- ---------------------------------------------------------------------------
-- First-run appearance choice popup
-- ---------------------------------------------------------------------------
-- Shows once when VERSION < 1.1 (or on every reload if DEBUG is on).
-- Two columns: "Blizzard Skin" vs "Yapper's Own", each with a preview slot.

function Interface:ShouldShowWelcomeChoice()
    -- Check raw saved variable — the value before defaults got merged in.
    local sv = _G.YapperLocalConf
    if type(sv) ~= "table" then return true end
    local sys = sv.System
    if type(sys) ~= "table" then return true end
    local ver = tonumber(sys._welcomeShown)
    if not ver or ver < 1.1 then return true end
    return false
end

function Interface:MarkWelcomeShown()
    if type(_G.YapperLocalConf) ~= "table" then return end
    if type(_G.YapperLocalConf.System) ~= "table" then
        _G.YapperLocalConf.System = {}
    end
    _G.YapperLocalConf.System._welcomeShown = 1.1
end

function Interface:CreateWelcomeChoiceFrame()
    if self.WelcomeFrame then return end

    local FRAME_W   = 960
    local FRAME_H   = 540
    local COL_W     = 440
    local PREVIEW_H = 320
    local BTN_W     = 200
    local BTN_H     = 36
    local PAD       = 20

    -- Fullscreen darkener.
    local dimmer    = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    dimmer:SetBackdropColor(0, 0, 0, 0.55)
    dimmer:EnableMouse(true) -- block clicks through

    -- Main container.
    local frame = CreateFrame("Frame", "YapperWelcomeChoice", dimmer, "BackdropTemplate")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(dimmer:GetFrameLevel() + 5)
    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    frame:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    -- Title.
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -PAD)
    title:SetText("Choose Your Editbox Appearance")
    title:SetTextColor(1, 0.82, 0, 1)

    -- Subtitle.
    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -6)
    sub:SetWidth(FRAME_W - 60)
    sub:SetText("You can change this at any time in settings. Pick whichever you prefer!")
    sub:SetTextColor(0.75, 0.75, 0.75, 1)

    local contentTop = -72 -- below title+subtitle

    -- Helper: build one column (button + preview area).
    local function BuildColumn(anchorX, labelText, descText, onClick)
        -- Button first (at top of column).
        local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btn:SetSize(BTN_W, BTN_H)
        btn:SetPoint("TOP", frame, "TOP", anchorX, contentTop)
        btn:SetText(labelText)
        btn:SetScript("OnClick", onClick)

        -- Short description under button.
        local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOP", btn, "BOTTOM", 0, -6)
        desc:SetWidth(COL_W - 20)
        desc:SetJustifyH("CENTER")
        desc:SetText(descText)
        desc:SetTextColor(0.65, 0.65, 0.65, 1)

        -- Preview placeholder underneath.
        local preview = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        preview:SetSize(COL_W, PREVIEW_H)
        preview:SetPoint("TOP", btn, "BOTTOM", 0, -36)
        preview:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        preview:SetBackdropColor(0.04, 0.04, 0.04, 1)
        preview:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6)

        -- Preview image texture (filled in per-column after BuildColumn).
        local tex = preview:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", preview, "TOPLEFT", 3, -3)
        tex:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -3, 3)
        preview.Texture = tex

        return btn, preview
    end

    local function closeWelcome()
        Interface:MarkWelcomeShown()
        dimmer:Hide()
        dimmer:SetParent(nil)
        Interface.WelcomeFrame = nil
    end

    -- Left column: Blizzard Skin Proxy.
    local blizzBtn, blizzPreview   = BuildColumn(
        -(COL_W / 2 + PAD / 2), -- left of centre
        "Blizzard",
        "Imitates Blizzard's default appearance, but offers less customisation. May not be compatible with other re-skinning addons, in which case Yapper's own theme may serve your needs.",
        function()
            Interface:SetLocalPath({ "EditBox", "UseBlizzardSkinProxy" }, true)
            closeWelcome()
        end
    )

    -- Right column: Yapper's Own.
    local yapperBtn, yapperPreview = BuildColumn(
        (COL_W / 2 + PAD / 2), -- right of centre
        "Yapper",
        "Fully customiseable with background colours and opacity. Has several styling options.",
        function()
            Interface:SetLocalPath({ "EditBox", "UseBlizzardSkinProxy" }, false)
            closeWelcome()
        end
    )

    -- Store references for preview images if added later.
    frame.BlizzPreview             = blizzPreview
    frame.YapperPreview            = yapperPreview
    frame.Dimmer                   = dimmer

    -- Set preview screenshots.
    local addonPath                = "Interface\\AddOns\\Yapper\\Src\\Img\\"
    blizzPreview.Texture:SetTexture(addonPath .. "BlizzTheme")
    blizzPreview.Texture:SetTexCoord(0, 1, 0, 1)
    yapperPreview.Texture:SetTexture(addonPath .. "YapperTheme")
    yapperPreview.Texture:SetTexCoord(0, 1, 0, 1)

    self.WelcomeFrame = frame
    dimmer:Show()
end

-- ---------------------------------------------------------------------------

-- Create the main settings window.
function Interface:CreateMainWindow()
    -- Prevent duplicate creation.
    if Interface.MainWindowFrame
        and Interface.MainWindowFrame.IsObjectType
        and Interface.MainWindowFrame:IsObjectType("Frame") then
        return
    end
    Interface.MainWindowFrame = nil

    local frame = CreateFrame(
        "Frame",
        YapperName .. "MainWindow",
        UIParent,
        "BasicFrameTemplateWithInset"
    )
    Interface.MainWindowFrame = frame
    frame:Hide()

    -- Allow ESC to close the settings window.
    tinsert(UISpecialFrames, YapperName .. "MainWindow")

    frame:SetSize(LAYOUT.WINDOW_WIDTH, LAYOUT.WINDOW_HEIGHT)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:EnableMouse(true)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Interface:SaveMainWindowPosition(self)
    end)
    frame:SetClampedToScreen(true)
    Interface:ApplyMainWindowPosition(frame)

    if frame.TitleText and frame.TitleText.SetText then
        frame.TitleText:SetText("Yapper Settings")
    end
    if frame.CloseButton ~= nil then
        frame.CloseButton:SetScript("OnClick", function(self)
            Interface:CloseFrame(self:GetParent())
        end)
    end

    -- -----------------------------------------------------------------------
    -- Sidebar
    -- -----------------------------------------------------------------------
    local P = LAYOUT
    local sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", P.WINDOW_PADDING, -P.SIDEBAR_TOP_INSET)
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", P.WINDOW_PADDING, P.BOTTOM_BAR + 4)
    sidebar:SetWidth(P.SIDEBAR_WIDTH)
    frame.Sidebar = sidebar

    -- Vertical divider between sidebar and content.
    local divider = sidebar:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    divider:SetWidth(1)
    divider:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    divider:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)

    -- -----------------------------------------------------------------------
    -- Font-size +/– control at the top of the sidebar.
    -- -----------------------------------------------------------------------
    local fontRow = CreateFrame("Frame", nil, sidebar)
    fontRow:SetSize(P.SIDEBAR_WIDTH - 8, 24)
    fontRow:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, 0)

    local fontLabel = fontRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fontLabel:SetPoint("LEFT", fontRow, "LEFT", 4, 0)
    fontLabel:SetText("Font:")
    fontLabel:SetTextColor(0.7, 0.7, 0.7, 1)

    -- Current size readout.
    local sizeLabel = fontRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sizeLabel:SetPoint("CENTER", fontRow, "CENTER", 0, 0)
    frame.FontScaleLabel = sizeLabel

    -- Minus button.
    local minusBtn = CreateFrame("Button", nil, fontRow)
    minusBtn:SetSize(20, 20)
    minusBtn:SetPoint("RIGHT", sizeLabel, "LEFT", -4, 0)
    minusBtn:SetNormalFontObject(GameFontNormal)
    minusBtn:SetHighlightFontObject(GameFontHighlight)
    minusBtn:SetText("\226\128\147") -- en-dash as minus glyph
    local minusHl = minusBtn:CreateTexture(nil, "HIGHLIGHT")
    minusHl:SetAllPoints()
    minusHl:SetColorTexture(1, 1, 1, 0.08)
    frame.FontMinusBtn = minusBtn

    -- Plus button.
    local plusBtn = CreateFrame("Button", nil, fontRow)
    plusBtn:SetSize(20, 20)
    plusBtn:SetPoint("LEFT", sizeLabel, "RIGHT", 4, 0)
    plusBtn:SetNormalFontObject(GameFontNormal)
    plusBtn:SetHighlightFontObject(GameFontHighlight)
    plusBtn:SetText("+")
    local plusHl = plusBtn:CreateTexture(nil, "HIGHLIGHT")
    plusHl:SetAllPoints()
    plusHl:SetColorTexture(1, 1, 1, 0.08)
    frame.FontPlusBtn = plusBtn

    minusBtn:SetScript("OnClick", function()
        local cur = Interface:GetUIFontOffset()
        Interface:SetUIFontOffset(cur - UI_FONT_STEP)
        Interface:RefreshFontScaleLabel()
        Interface:BuildConfigUI()
    end)
    plusBtn:SetScript("OnClick", function()
        local cur = Interface:GetUIFontOffset()
        Interface:SetUIFontOffset(cur + UI_FONT_STEP)
        Interface:RefreshFontScaleLabel()
        Interface:BuildConfigUI()
    end)

    -- Thin separator between font control and category buttons.
    local fontSep = sidebar:CreateTexture(nil, "ARTWORK")
    fontSep:SetColorTexture(0.4, 0.4, 0.4, 0.4)
    fontSep:SetHeight(1)
    fontSep:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 4, -28)
    fontSep:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -8, -28)

    -- Build one button per category.
    frame.SidebarButtons = {}
    local btnY = 32 -- start below font row + separator
    for _, cat in ipairs(CATEGORIES) do
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetSize(P.SIDEBAR_WIDTH - 8, P.SIDEBAR_BTN_HEIGHT)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -btnY)
        btnY = btnY + P.SIDEBAR_BTN_HEIGHT + P.SIDEBAR_BTN_PAD

        -- Label
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", btn, "LEFT", 8, 0)
        label:SetText(cat.label)
        btn.Label = label

        -- Highlight texture
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)

        -- Selected indicator (left accent bar)
        local sel = btn:CreateTexture(nil, "OVERLAY")
        sel:SetColorTexture(0.9, 0.75, 0.2, 1)
        sel:SetWidth(3)
        sel:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        sel:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        sel:Hide()
        btn.SelectedBar = sel

        -- Background for selected state
        local selBg = btn:CreateTexture(nil, "BACKGROUND")
        selBg:SetAllPoints()
        selBg:SetColorTexture(1, 1, 1, 0.05)
        selBg:Hide()
        btn.SelectedBg = selBg

        btn.categoryId = cat.id
        btn:SetScript("OnClick", function()
            Interface._activeCategory = cat.id
            Interface:UpdateSidebarSelection()
            Interface:BuildConfigUI()
        end)

        frame.SidebarButtons[cat.id] = btn
    end

    -- Delegate scrolling to focused helpers.
    local scrollFrame = CreateScrollableContent(frame)
    CreateScrollBarForFrame(frame, scrollFrame)

    -- Bottom close button.
    local bottomClose = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    bottomClose:SetSize(LAYOUT.CLOSE_BTN_WIDTH, LAYOUT.CLOSE_BTN_HEIGHT)
    bottomClose:SetPoint("BOTTOM", frame, "BOTTOM", 0, LAYOUT.CLOSE_BTN_OFFSET_Y)
    bottomClose:SetText("Close")
    bottomClose:SetScript("OnClick", function()
        Interface:CloseFrame(frame)
    end)
    frame.BottomCloseButton = bottomClose

    -- Apply initial sidebar selection highlight.
    self:UpdateSidebarSelection()
end

-- Refresh the visual state of sidebar buttons to reflect _activeCategory.
function Interface:UpdateSidebarSelection()
    local frame = self.MainWindowFrame
    if not frame or not frame.SidebarButtons then return end
    for catId, btn in pairs(frame.SidebarButtons) do
        local selected = (catId == self._activeCategory)
        btn.SelectedBar:SetShown(selected)
        btn.SelectedBg:SetShown(selected)
        if selected then
            btn.Label:SetFontObject(GameFontHighlight)
        else
            btn.Label:SetFontObject(GameFontNormal)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Settings-panel font scaling
-- ---------------------------------------------------------------------------

function Interface:GetUIFontOffset()
    local v = tonumber(self:GetConfigPath({ "FrameSettings", "UIFontOffset" }))
    if v then return v end
    return 0
end

function Interface:SetUIFontOffset(offset)
    offset = math_max(UI_FONT_MIN_OFFSET, math_min(UI_FONT_MAX_OFFSET, offset))
    self:SetLocalPath({ "FrameSettings", "UIFontOffset" }, offset)
    return offset
end

--- Return a row height scaled by the current font offset so elements don't
--- overlap when the user increases the UI font size.
function Interface:ScaledRow(base)
    return base + self:GetUIFontOffset()
end

--- Walk every FontString under the settings window and set its size to
--- the Blizzard base size + the user's offset.
function Interface:ApplyUIFontScale()
    local offset = self:GetUIFontOffset()
    local frame  = self.MainWindowFrame
    if not frame then return end

    -- Query the Blizzard base once per pass.
    local _, blizzBase = GameFontNormal:GetFont()
    blizzBase = blizzBase or 12
    local targetSize = math_max(8, blizzBase + offset)

    local function scaleRegions(parent)
        for _, region in pairs({ parent:GetRegions() }) do
            if region:IsObjectType("FontString") then
                local fontFile, _, fontFlags = region:GetFont()
                if fontFile then
                    region:SetFont(fontFile, targetSize, fontFlags or "")
                end
            end
        end
        for _, child in pairs({ parent:GetChildren() }) do
            scaleRegions(child)
        end
    end

    scaleRegions(frame)
end

--- Update the font-scale label text to reflect the current effective size.
function Interface:RefreshFontScaleLabel()
    local frame = self.MainWindowFrame
    if not frame or not frame.FontScaleLabel then return end
    local offset = self:GetUIFontOffset()
    local _, baseSize = GameFontNormal:GetFont()
    baseSize = baseSize or 12
    frame.FontScaleLabel:SetText(tostring(math_floor(baseSize + offset)))
end
