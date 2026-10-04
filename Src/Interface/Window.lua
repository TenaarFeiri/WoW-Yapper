--[[
    Interface/Window.lua
    Main settings window creation, scrollable content area, scrollbar,
    welcome choice frame, sidebar, font scaling, and position persistence.
]]

local YapperName, YapperTable = ...
local Interface               = YapperTable.Interface

-- Re-localise shared helpers from hub.
local IsAnchorPoint           = Interface.IsAnchorPoint
local LAYOUT                  = Interface._LAYOUT
local CATEGORIES              = Interface._CATEGORIES

local type                    = type
local ipairs                  = ipairs
local math_floor              = math.floor
local math_max                = math.max
local math_min                = math.min
local tinsert                 = table.insert
local tostring                = tostring

-- Even-increment offsets (re-exported from hub for local use).
local UI_FONT_STEP            = Interface._UI_FONT_STEP
local UI_FONT_MIN_OFFSET      = Interface._UI_FONT_MIN_OFFSET
local UI_FONT_MAX_OFFSET      = Interface._UI_FONT_MAX_OFFSET

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

-- Active sidebar category; persists for the session.
Interface._activeCategory = "general"

-- ---------------------------------------------------------------------------
-- Version-gated popups: Welcome (first-run / schema change) & What's New
-- ---------------------------------------------------------------------------
-- _welcomeShown    -- schema VERSION at which the full welcome was last shown.
-- _lastSeenVersion -- addon version string last seen at login ("2.0.1" etc.).
--
-- Full welcome:   triggers when _welcomeShown == 0 or < current schema VERSION.
-- What's New:     triggers when _lastSeenVersion ~= addon version AND welcome
--                 was already shown for the current schema.
-- ---------------------------------------------------------------------------

-- WHATS_NEW table has been moved to Src/Interface/WhatsNew.lua

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

function Interface:CompareVersions(v1, v2)
    local p1 = { strsplit(".", v1) }
    local p2 = { strsplit(".", v2) }
    for i = 1, math_max(#p1, #p2) do
        local n1 = tonumber(p1[i]) or 0
        local n2 = tonumber(p2[i]) or 0
        if n1 ~= n2 then return n1 > n2 end
    end
    return false
end

function Interface:GetSortedVersions()
    local list = {}
    local WHATS_NEW = YapperTable.WHATS_NEW or {}
    for v in pairs(WHATS_NEW) do
        tinsert(list, v)
    end
    table.sort(list, function(a, b) return self:CompareVersions(a, b) end)
    return list
end

--- Iterate through changelog versions in display order.
---@param limitToOne boolean? Stop after the newest version.
---@param callback function Receives version string and note array.
function Interface:ForEachWhatsNewVersion(limitToOne, callback)
    if type(callback) ~= "function" then return end

    local WHATS_NEW = YapperTable.WHATS_NEW or {}
    for index, version in ipairs(self:GetSortedVersions()) do
        if limitToOne and index > 1 then break end
        callback(version, WHATS_NEW[version] or {})
    end
end

--- Returns the target version of the welcome screen content.
function Interface:GetWelcomeVersion()
    local defaults = self:GetDefaultsRoot()
    if type(defaults) == "table" and type(defaults.System) == "table" then
        return tonumber(defaults.System.WELCOME_VERSION) or 1
    end
    return 1
end

local function GetAddonVersion()
    if YapperTable.Core and YapperTable.Core.GetVersion then
        return YapperTable.Core:GetVersion() or ""
    end
    return ""
end

local function ReadSV(key)
    local sv = _G.YapperLocalConf
    if type(sv) ~= "table" then return nil end
    local sys = sv.System
    if type(sys) ~= "table" then return nil end
    return sys[key]
end

local function WriteSV(key, value)
    if type(_G.YapperLocalConf) ~= "table" then return end
    if type(_G.YapperLocalConf.System) ~= "table" then
        _G.YapperLocalConf.System = {}
    end
    _G.YapperLocalConf.System[key] = value
end

-- Create a fullscreen modal dimmer shared by welcome and What's New popups.
---@param alpha number
---@return Frame dimmer
function Interface:CreateFullscreenDimmer(alpha)
    local dimmer = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    dimmer:SetBackdropColor(0, 0, 0, alpha)
    dimmer:EnableMouse(true)
    return dimmer
end

-- ---------------------------------------------------------------------------
-- Gating
-- ---------------------------------------------------------------------------

function Interface:ShouldShowWelcomeChoice()
    if YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        return true
    end
    local shown = tonumber(ReadSV("_welcomeShown"))
    if not shown or shown == 0 then return true end

    -- Re-show when the welcome screen content changes (UI update).
    if shown ~= self:GetWelcomeVersion() then return true end
    return false
end

-- Helper function to strip non-numerical characters (except dots) from version strings.
-- This allows versions like "2.1.28_alpha" to be compared with "2.1.28".
local function NormaliseVersion(version)
    if type(version) ~= "string" then return version end
    return version:gsub("[^0-9%.]", "")
end

function Interface:CheckForChangelogUpdate()
    if YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        self:CreateWhatsNewFrame()
        return
    end

    -- Never show What's New if the full welcome hasn't been shown yet.
    if self:ShouldShowWelcomeChoice() then return end

    local last = NormaliseVersion(ReadSV("_lastSeenVersion") or "0.0.0")
    local current = NormaliseVersion(GetAddonVersion())

    if last == current then return end

    -- Record the bump immediately so it isn't processed twice, and only
    -- show the popup when this version actually has notes.
    self:MarkVersionSeen()
    local WHATS_NEW = YapperTable.WHATS_NEW or {}
    if WHATS_NEW[current] then
        self:CreateWhatsNewFrame()
    end
end

function Interface:MarkWelcomeShown()
    WriteSV("_welcomeShown", self:GetWelcomeVersion())
end

function Interface:MarkVersionSeen()
    WriteSV("_lastSeenVersion", NormaliseVersion(GetAddonVersion()))
end

-- ---------------------------------------------------------------------------
-- Shared UI helpers for popup frames
-- ---------------------------------------------------------------------------

--- Create a standard toggle row inside a popup frame.
--- Uses Interface:SetLocalPath so the change is fully live immediately.
---@param parent Frame   Parent frame to anchor widgets to.
---@param path   table   Config path, e.g. {"Spellcheck", "Enabled"}.
---@param label  string  Display text next to the checkbox.
---@param tip    string? Tooltip text.
---@param y      number  Vertical offset from parent top.
---@return CheckButton cb, FontString fs, number nextY
local function CreatePopupToggle(parent, path, label, tip, y, opts)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("LEFT", parent, "LEFT", (opts and opts.x) or 24, 0)
    cb:SetPoint("TOP", parent, "TOP", 0, y)
    cb:SetSize(26, 26)

    local current = Interface:GetConfigPath(path)
    cb:SetChecked(current == true)

    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked() == true
        if opts and opts.onSet then
            -- Interceptor owns the config write (e.g. spellcheck prompts
            -- for a language before enabling) and may revert the checkmark.
            opts.onSet(self, checked)
        else
            Interface:SetLocalPath(path, checked)
        end
        if cb.OnToggle then cb:OnToggle(self:GetChecked() == true) end
    end)

    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    fs:SetText(label)
    fs:SetTextColor(0.9, 0.9, 0.9, 1)



    if tip then
        local function OnEnter(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
        local function OnLeave() GameTooltip:Hide() end
        cb:SetScript("OnEnter", OnEnter)
        cb:SetScript("OnLeave", OnLeave)
        fs:SetScript("OnEnter", OnEnter)
        fs:SetScript("OnLeave", OnLeave)
    end

    return cb, fs, y - 30
end

-- ---------------------------------------------------------------------------
-- Spellcheck locale prompt (welcome / What's New opt-in flow)
-- ---------------------------------------------------------------------------

-- Friendly labels for shipped dictionary locales; unknown codes display raw.
local LOCALE_LABELS = {
    enUS = "English (US)",
    enGB = "English (UK)",
    enAU = "English (Australia)",
    deDE = "German",
}

--- Small chooser shown when spellcheck is enabled from a popup before any
--- dictionary exists: the user picks which locale to load rather than
--- silently pulling in the configured default.
--- @param parent Frame   Popup frame to anchor over.
--- @param onDone function?  Called with true after a locale is picked and
---                          enabled, false on cancel.
function Interface:ShowSpellcheckLocalePrompt(parent, onDone)
    if self.LocalePrompt then self.LocalePrompt:Hide() end

    local spell = YapperTable.Spellcheck
    local locales = {}
    for _, locale in ipairs((spell and spell.KnownLocales) or {}) do
        local usable = (spell.IsLocaleAvailable and spell:IsLocaleAvailable(locale))
            or (spell.CanLoadLocale and spell:CanLoadLocale(locale))
        if usable then
            locales[#locales + 1] = locale
        end
    end
    if #locales == 0 then locales = { "enUS" } end

    local BTN_H = 24
    local PAD   = 16
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(260, PAD * 2 + 30 + #locales * (BTN_H + 6) + 34)
    frame:SetPoint("CENTER", parent, "CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(parent:GetFrameLevel() + 10)
    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    frame:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", frame, "TOP", 0, -PAD)
    title:SetText("Choose your spellcheck language")
    title:SetTextColor(1, 0.82, 0, 1)

    local function finish(picked)
        frame:Hide()
        frame:SetParent(nil)
        if self.LocalePrompt == frame then self.LocalePrompt = nil end
        if onDone then onDone(picked) end
    end

    local y = -PAD - 26
    for _, locale in ipairs(locales) do
        local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btn:SetSize(220, BTN_H)
        btn:SetPoint("TOP", frame, "TOP", 0, y)
        btn:SetText(LOCALE_LABELS[locale] or locale)
        local loc = locale
        btn:SetScript("OnClick", function()
            -- Order matters: store the locale while spellcheck is still off
            -- (ApplyState then skips loading), then flip Enabled so the
            -- config-changed path loads exactly this dictionary.
            Interface:SetLocalPath({ "Spellcheck", "Locale" }, loc)
            Interface:SetLocalPath({ "Spellcheck", "Enabled" }, true)
            finish(true)
        end)
        y = y - (BTN_H + 6)
    end

    local cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancel:SetSize(220, BTN_H)
    cancel:SetPoint("TOP", frame, "TOP", 0, y)
    cancel:SetText("Cancel")
    cancel:SetScript("OnClick", function() finish(false) end)

    self.LocalePrompt = frame
    frame:Show()
end

-- ---------------------------------------------------------------------------
-- Welcome Choice Frame (first-run or schema change)
-- ---------------------------------------------------------------------------

function Interface:CreateWelcomeChoiceFrame()
    if self.WelcomeFrame then return end

    local FRAME_W   = 960
    local FRAME_H   = 620
    local COL_W     = 440
    local PREVIEW_H = 280
    local BTN_W     = 200
    local BTN_H     = 36
    local PAD       = 20

    local dimmer = self:CreateFullscreenDimmer(0.55)

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

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -PAD)
    title:SetText("Welcome to Yapper!")
    title:SetTextColor(1, 0.82, 0, 1)

    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -6)
    sub:SetWidth(FRAME_W - 60)
    sub:SetText(
        "Pick your editbox appearance, then configure your preferences below. You can change everything later in |cFFFFD100/yapper|r.")
    sub:SetTextColor(0.75, 0.75, 0.75, 1)

    local contentTop = -72 -- below title+subtitle

    -- Helper: build one column (button + preview area).
    local function BuildColumn(anchorX, labelText, descText, onClick)
        local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btn:SetSize(BTN_W, BTN_H)
        btn:SetPoint("TOP", frame, "TOP", anchorX, contentTop)
        btn:SetText(labelText)
        btn:SetScript("OnClick", onClick)

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

        -- Texture is filled in per-column after BuildColumn returns.
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

        -- Chain into What's New if eligible.
        Interface:CheckForChangelogUpdate()
    end

    -- Left column: Blizzard Skin Proxy.
    local _, blizzPreview        = BuildColumn(
        -(COL_W / 2 + PAD / 2), -- left of centre
        "Blizzard",
        "Imitates Blizzard's default appearance, but offers less customisation. May not be compatible with other re-skinning addons, in which case Yapper's own theme may serve your needs.",
        function()
            Interface:SetLocalPath({ "EditBox", "UseBlizzardSkinProxy" }, true)
            closeWelcome()
        end
    )

    -- Right column: Yapper's Own.
    local _, yapperPreview         = BuildColumn(
        (COL_W / 2 + PAD / 2), -- right of centre
        "Yapper",
        "Fully customisable with background colours and opacity. Has several styling options.",
        function()
            Interface:SetLocalPath({ "EditBox", "UseBlizzardSkinProxy" }, false)
            closeWelcome()
        end
    )

    -- Set preview screenshots.
    local addonPath                = "Interface\\AddOns\\Yapper\\Src\\Img\\"
    blizzPreview.Texture:SetTexture(addonPath .. "BlizzTheme")
    blizzPreview.Texture:SetTexCoord(0, 1, 0, 1)
    yapperPreview.Texture:SetTexture(addonPath .. "YapperTheme")
    yapperPreview.Texture:SetTexCoord(0, 1, 0, 1)

    -- Feature opt-in toggles below the columns
    local toggleY = contentTop - BTN_H - 44 - PREVIEW_H - 24

    local featureLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    featureLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 4, toggleY)
    featureLabel:SetText("Optional Features")
    featureLabel:SetTextColor(1, 0.82, 0, 1)
    toggleY = toggleY - 24

    local spellToggle, acToggle, acLabel, yasToggle, yasLabel, corrToggle, corrLabel
    local function updateSubToggles()
        local spellEnabled = Interface:GetConfigPath({ "Spellcheck", "Enabled" }) == true
        local yasEnabled   = Interface:GetConfigPath({ "Spellcheck", "YASEnabled" }) == true
        acToggle:SetEnabled(spellEnabled)
        acLabel:SetTextColor(spellEnabled and 0.9 or 0.5, spellEnabled and 0.9 or 0.5, spellEnabled and 0.9 or 0.5, 1)
        yasToggle:SetEnabled(spellEnabled)
        yasLabel:SetTextColor(spellEnabled and 0.9 or 0.5, spellEnabled and 0.9 or 0.5, spellEnabled and 0.9 or 0.5, 1)
        local corrOk = spellEnabled and yasEnabled
        corrToggle:SetEnabled(corrOk)
        corrLabel:SetTextColor(corrOk and 0.9 or 0.5, corrOk and 0.9 or 0.5, corrOk and 0.9 or 0.5, 1)
    end

    spellToggle = CreatePopupToggle(
        frame,
        { "Spellcheck", "Enabled" },
        "Enable spellcheck  |cFF888888(per-locale dictionaries with adaptive learning)|r",
        "Turns on real-time spellchecking and colours misspelled words. "
        .. "You will be asked which dictionary language to load.",
        toggleY,
        { onSet = function(cb, checked)
            if checked then
                -- Don't load a dictionary sight unseen: ask which language.
                cb:SetChecked(false)
                Interface:ShowSpellcheckLocalePrompt(frame, function(picked)
                    if picked then
                        cb:SetChecked(true)
                        updateSubToggles()
                    end
                end)
            else
                Interface:SetLocalPath({ "Spellcheck", "Enabled" }, false)
            end
        end }
    )
    local nextY = toggleY - 30

    acToggle, acLabel, nextY = CreatePopupToggle(
        frame,
        { "EditBox", "AutocompleteEnabled" },
        "Enable autocomplete / ghost text  |cFF888888(requires spellcheck)|r",
        "Shows ghost-text word predictions as you type based on your personal "
        .. "vocabulary and the spellcheck dictionary. Press Tab to accept.",
        nextY
    )

    yasToggle, yasLabel, nextY = CreatePopupToggle(
        frame,
        { "Spellcheck", "YASEnabled" },
        "Enable adaptive learning  |cFF888888(requires spellcheck)|r",
        "Tracks your vocabulary and correction preferences to improve "
        .. "suggestion accuracy over time.",
        nextY
    )

    corrToggle, corrLabel = CreatePopupToggle(
        frame,
        { "Spellcheck", "AutocorrectEnabled" },
        "Enable autocorrect  |cFF888888(requires spellcheck + adaptive learning)|r",
        "Fixes typos the moment you finish a word, but only corrections adaptive "
        .. "learning is highly confident about. Undo instantly with Backspace, "
        .. "Ctrl+Z, or the Undo toast.",
        nextY
    )

    spellToggle.OnToggle = updateSubToggles
    yasToggle.OnToggle = updateSubToggles
    updateSubToggles()

    frame.BlizzPreview  = blizzPreview
    frame.YapperPreview = yapperPreview
    frame.Dimmer        = dimmer

    self.WelcomeFrame   = frame
    dimmer:Show()
end

-- ---------------------------------------------------------------------------
-- What's New Frame (version bump, not a schema change)
-- ---------------------------------------------------------------------------

function Interface:CreateWhatsNewFrame()
    if self.WhatsNewFrame then return end

    local sorted = self:GetSortedVersions()
    if #sorted == 0 then
        self:MarkVersionSeen()
        return
    end

    local FRAME_W = 560
    local FRAME_H = 540
    local PAD     = 20

    local dimmer = self:CreateFullscreenDimmer(0.45)

    local frame = CreateFrame("Frame", "YapperWhatsNew", dimmer, "BackdropTemplate")
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

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -PAD)
    title:SetText("Yapper Changelog")
    title:SetTextColor(1, 0.82, 0, 1)

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD - 32)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 26, PAD + 100)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(content)

    -- Note entries (most recent only for the popup).
    self:PopulateWhatsNewContent(content, scrollFrame:GetWidth() - 10, true)

    self.WhatsNewFrame = frame
    self.WhatsNewContent = content
    self.WhatsNewScroll = scrollFrame
    dimmer:Show()

    -- Feature opt-in toggles
    local spellEnabled = Interface:GetConfigPath({ "Spellcheck", "Enabled" })
    local acEnabled    = Interface:GetConfigPath({ "EditBox", "AutocompleteEnabled" })
    local yasEnabled = Interface:GetConfigPath({ "Spellcheck", "YASEnabled" })

    local toggleCursor = -FRAME_H + 120

    -- Live Font Size Slider (Upscaled)
    local sizeSlider   = CreateFrame("Slider", "YapperWhatsNewSizeSlider", frame, "OptionsSliderTemplate")
    sizeSlider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD + 10, PAD + 10)
    sizeSlider:SetWidth(280)
    sizeSlider:SetHeight(24)
    sizeSlider:SetMinMaxValues(8, 32)
    sizeSlider:SetValueStep(1)
    sizeSlider:SetObeyStepOnDrag(true)

    -- Hide the generic template labels.
    _G[sizeSlider:GetName() .. "Low"]:SetText("")
    _G[sizeSlider:GetName() .. "High"]:SetText("")

    local currentSize = YapperTable.Config.FrameSettings.WhatsNewFontSize or 12
    sizeSlider:SetValue(currentSize)

    local sizeLabel = sizeSlider:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sizeLabel:SetPoint("BOTTOM", sizeSlider, "TOP", 0, 8)
    sizeLabel:SetText("Text Size: " .. currentSize)
    sizeLabel:SetTextColor(1, 0.82, 0, 1)

    sizeSlider:SetScript("OnValueChanged", function(s, value)
        local val = math.floor(value + 0.5)
        sizeLabel:SetText("Text Size: " .. val)
        if YapperTable.Config.FrameSettings.WhatsNewFontSize ~= val then
            Interface:SetLocalPath({ "FrameSettings", "WhatsNewFontSize" }, val)
            Interface:RefreshWhatsNewContent()
        end
    end)

    local corrEnabled = Interface:GetConfigPath({ "Spellcheck", "AutocorrectEnabled" })

    if spellEnabled ~= true or acEnabled ~= true or yasEnabled ~= true or corrEnabled ~= true then
        local togLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        togLabel:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", PAD + 4, 120)
        togLabel:SetText("New Features — Try Them Out")
        togLabel:SetTextColor(1, 0.82, 0, 1)
        toggleCursor = toggleCursor - 24

        -- Two columns: dependencies (spellcheck, adaptive) on the left,
        -- dependent features (autocomplete, autocorrect) on the right.
        local COL2_X = 280
        local acT, acL, yasT, yasL, spellT, corrT, corrL
        local leftY = toggleCursor
        local rightY = toggleCursor

        local function setEnabled(cb, label, on)
            if not cb then return end
            cb:SetEnabled(on)
            label:SetTextColor(on and 0.9 or 0.5, on and 0.9 or 0.5, on and 0.9 or 0.5, 1)
        end

        local function update()
            local spell = Interface:GetConfigPath({ "Spellcheck", "Enabled" }) == true
            local yas   = Interface:GetConfigPath({ "Spellcheck", "YASEnabled" }) == true
            setEnabled(acT, acL, spell)
            setEnabled(yasT, yasL, spell)
            setEnabled(corrT, corrL, spell and yas)
        end

        if spellEnabled ~= true then
            spellT = CreatePopupToggle(frame, { "Spellcheck", "Enabled" }, "Enable spellcheck",
                "Turns on real-time spellchecking. You will be asked which "
                .. "dictionary language to load.", leftY,
                { onSet = function(cb, checked)
                    if checked then
                        cb:SetChecked(false)
                        Interface:ShowSpellcheckLocalePrompt(frame, function(picked)
                            if picked then
                                cb:SetChecked(true)
                                update()
                            end
                        end)
                    else
                        Interface:SetLocalPath({ "Spellcheck", "Enabled" }, false)
                    end
                end })
            leftY = leftY - 30
        end
        if yasEnabled ~= true then
            yasT, yasL = CreatePopupToggle(frame, { "Spellcheck", "YASEnabled" }, "Enable adaptive learning",
                "Tracks your vocabulary to improve suggestion accuracy. Requires spellcheck.", leftY)
            leftY = leftY - 30
        end
        if acEnabled ~= true then
            acT, acL = CreatePopupToggle(frame, { "EditBox", "AutocompleteEnabled" },
                "Enable autocomplete", "Shows ghost-text predictions as you type. Requires spellcheck.",
                rightY, { x = COL2_X })
            rightY = rightY - 30
        end
        if corrEnabled ~= true then
            corrT, corrL = CreatePopupToggle(frame, { "Spellcheck", "AutocorrectEnabled" },
                "Enable autocorrect",
                "Fixes typos as you finish a word, only when adaptive learning "
                .. "is highly confident. Undo with Backspace, Ctrl+Z, or the "
                .. "toast. Requires spellcheck and adaptive learning.",
                rightY, { x = COL2_X })
            rightY = rightY - 30
        end

        if spellT then spellT.OnToggle = update end
        if yasT then yasT.OnToggle = update end
        update()
    end

    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btn:SetSize(120, 32)
    btn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
    btn:SetText("Got it")
    btn.GotItButton = btn
    frame.GotItButton = btn
    btn:SetScript("OnClick", function()
        Interface:MarkVersionSeen()
        dimmer:Hide()
        dimmer:SetParent(nil)
        Interface.WhatsNewFrame = nil
    end)
    self:UpdateWhatsNewButtonScale()

    self.WhatsNewFrame = frame
    dimmer:Show()
end

function Interface:PopulateWhatsNewContent(content, textW, limitToOne)
    local cursor = 0
    local cfgSize = YapperTable.Config.FrameSettings.WhatsNewFontSize or 12

    self:ForEachWhatsNewVersion(limitToOne, function(version, notes)
        local vHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        local vFont, _, vFlags = vHeader:GetFont()
        vHeader:SetFont(vFont, cfgSize + 4, vFlags)
        vHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 4, cursor)
        vHeader:SetWidth(textW)
        vHeader:SetJustifyH("LEFT")
        vHeader:SetText("Version " .. version)
        vHeader:SetTextColor(1, 0.9, 0, 1)
        cursor = cursor - (vHeader:GetStringHeight() + 10)

        for _, entry in ipairs(notes) do
            local heading = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            local hFont, _, hFlags = heading:GetFont()
            heading:SetFont(hFont, cfgSize + 2, hFlags)
            heading:SetPoint("TOPLEFT", content, "TOPLEFT", 12, cursor)
            heading:SetWidth(textW - 12)
            heading:SetJustifyH("LEFT")
            heading:SetText(entry.title)
            heading:SetTextColor(1, 0.82, 0, 0.95)
            cursor = cursor - (heading:GetStringHeight() + 4)

            local body = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            local bFont, _, bFlags = body:GetFont()
            body:SetFont(bFont, cfgSize, bFlags)
            body:SetPoint("TOPLEFT", content, "TOPLEFT", 12, cursor)
            body:SetWidth(textW - 12)
            body:SetJustifyH("LEFT")
            body:SetText(entry.body)
            body:SetTextColor(0.8, 0.8, 0.8, 1)
            cursor = cursor - (body:GetStringHeight() + 14)
        end
        cursor = cursor - 20
    end)
    content:SetHeight(math.abs(cursor))
end

function Interface:RefreshWhatsNewContent()
    if not self.WhatsNewContent or not self.WhatsNewScroll then return end

    -- Clear old fontstrings
    local regions = { self.WhatsNewContent:GetRegions() }
    for _, region in ipairs(regions) do
        if region:IsObjectType("FontString") then
            region:Hide()
            region:SetText("")
            region:ClearAllPoints()
        end
    end

    self:PopulateWhatsNewContent(self.WhatsNewContent, self.WhatsNewScroll:GetWidth() - 10, true)
    self:UpdateWhatsNewButtonScale()
end

function Interface:UpdateWhatsNewButtonScale()
    if not self.WhatsNewFrame or not self.WhatsNewFrame.GotItButton then return end
    local btn = self.WhatsNewFrame.GotItButton
    local cfgSize = YapperTable.Config.FrameSettings.WhatsNewFontSize or 12

    -- Scale the font, but clamp it so it doesn't break the button's 120x32 footprint.
    -- 20pt is about as large as we can go without looking ridiculous or clipping.
    local targetSize = math_max(11, math_min(20, cfgSize))
    local fs = btn:GetFontString()
    if fs then
        local font, _, flags = fs:GetFont()
        fs:SetFont(font, targetSize, flags)
    end
end

-- ---------------------------------------------------------------------------

-- Create the main settings window.
function Interface:CreateMainWindow()
    -- Bail if the window already exists.
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
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:SetToplevel(true)
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
    -- Font-size +/- control at the top of the sidebar.
    -- -----------------------------------------------------------------------
    local fontRow = CreateFrame("Frame", nil, sidebar)
    fontRow:SetSize(P.SIDEBAR_WIDTH - 8, 24)
    fontRow:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, 0)

    local fontLabel = fontRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fontLabel:SetText("Font:")
    fontLabel:SetTextColor(0.7, 0.7, 0.7, 1)

    local sizeLabel = fontRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.FontScaleLabel = sizeLabel

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

    fontLabel:SetPoint("LEFT", fontRow, "LEFT", 4, 0)
    fontLabel:SetPoint("RIGHT", minusBtn, "LEFT", -4, 0)
    fontLabel:SetWordWrap(false)
    fontLabel:SetMaxLines(1)

    local plusBtn = CreateFrame("Button", nil, fontRow)
    plusBtn:SetSize(20, 20)
    plusBtn:SetPoint("RIGHT", fontRow, "RIGHT", -4, 0)
    plusBtn:SetNormalFontObject(GameFontNormal)
    plusBtn:SetHighlightFontObject(GameFontHighlight)
    plusBtn:SetText("+")
    local plusHl = plusBtn:CreateTexture(nil, "HIGHLIGHT")
    plusHl:SetAllPoints()
    plusHl:SetColorTexture(1, 1, 1, 0.08)
    frame.FontPlusBtn = plusBtn

    sizeLabel:SetPoint("RIGHT", plusBtn, "LEFT", -4, 0)

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
    local ALL_CATEGORIES = Interface._ALL_CATEGORIES or CATEGORIES
    local btnY = 32 -- start below font row + separator
    local seenPlugin = false
    for _, cat in ipairs(ALL_CATEGORIES) do
        -- Add separator before first plugin category
        if not cat.internal and not seenPlugin then
            seenPlugin = true
            local sep = sidebar:CreateTexture(nil, "ARTWORK")
            sep:SetColorTexture(0.4, 0.4, 0.4, 0.4)
            sep:SetHeight(1)
            sep:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 4, -btnY)
            sep:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -8, -btnY)
            btnY = btnY + 8
        end

        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetSize(P.SIDEBAR_WIDTH - 8, P.SIDEBAR_BTN_HEIGHT)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -btnY)
        btnY = btnY + P.SIDEBAR_BTN_HEIGHT + P.SIDEBAR_BTN_PAD

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", btn, "LEFT", 8, 0)
        label:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        label:SetWordWrap(false)
        label:SetMaxLines(1)
        label:SetText(cat.label)
        label._yCategoryLabel = cat.label
        btn.Label = label

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

    local scrollFrame = CreateScrollableContent(frame)
    CreateScrollBarForFrame(frame, scrollFrame)

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

--- Set a settings-panel FontString to the current UI font size.
function Interface:ApplyUIFontScaleToFontString(fontString)
    if not fontString then return end

    local offset = self:GetUIFontOffset()
    local _, blizzBase = GameFontNormal:GetFont()
    blizzBase = blizzBase or 12
    local targetSize = math_max(8, blizzBase + offset)
    local fontFile, _, fontFlags = fontString:GetFont()
    if fontFile then
        fontString:SetFont(fontFile, targetSize, fontFlags or "")
    end
end

--- Walk every FontString under the settings window and set its size to
--- the Blizzard base size + the user's offset.
function Interface:ApplyUIFontScale()
    local frame  = self.MainWindowFrame
    if not frame then return end

    local function scaleRegions(parent)
        for _, region in pairs({ parent:GetRegions() }) do
            if region:IsObjectType("FontString") and not region._ySkipUIFontScale then
                self:ApplyUIFontScaleToFontString(region)
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
