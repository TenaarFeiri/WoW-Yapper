--[[
    Interface/Widgets.lua
    Widget pool management, tooltip helpers, and reusable widget creators
    (checkbox, text input, color picker, font size, font outline, reset
    button, label).
]]

local _, YapperTable = ...
local Interface      = YapperTable.Interface

-- Re-localise shared helpers from hub.
local JoinPath          = Interface.JoinPath
local IsColourTable     = Interface.IsColourTable
local CopyColour        = Interface.CopyColour
local Clamp01           = Interface.Clamp01
local TrimString        = Interface.TrimString
local RoundToEven       = Interface.RoundToEven
local NormalizeFontFlags = Interface.NormalizeFontFlags
local GetFontFlagsLabel = Interface.GetFontFlagsLabel
local LAYOUT            = Interface._LAYOUT
local COLOUR_KEYS       = Interface._COLOUR_KEYS
local SETTING_TOOLTIPS  = Interface._SETTING_TOOLTIPS
local FONT_OUTLINE_OPTIONS = Interface._FONT_OUTLINE_OPTIONS

-- Re-localise Lua globals.
local type       = type
local pairs      = pairs
local ipairs     = ipairs
local tostring   = tostring
local tonumber   = tonumber
local math_floor = math.floor
local math_min   = math.min

function Interface:ClearConfigControls()
    if type(self.DynamicControls) ~= "table" then
        self.DynamicControls = {}
        return
    end
    for _, widget in ipairs(self.DynamicControls) do
        self:ReleaseWidget(widget)
    end
    self.DynamicControls = {}
end

function Interface:AddControl(widget)
    if type(self.DynamicControls) ~= "table" then
        self.DynamicControls = {}
    end
    self.DynamicControls[#self.DynamicControls + 1] = widget
end

-- ---------------------------------------------------------------------------
-- WidgetShownState pooling to efficiently create frames and prevent memory leaks
-- ---------------------------------------------------------------------------

Interface.WidgetPool = {
    -- Keyed by widget type string.
    -- Values are arrays of hidden frames.
}

---@param widgetType string
---@param parent table
---@param template string?
---@param frameType string?
---@return table
function Interface:AcquireWidget(widgetType, parent, template, frameType)
    if not self.WidgetPool[widgetType] then
        self.WidgetPool[widgetType] = {}
    end

    local pool = self.WidgetPool[widgetType]
    local widget = table.remove(pool)

    if not widget then
        -- Create new if pool is empty.
        if frameType == "FontString" then
            widget = parent:CreateFontString(nil, "OVERLAY", template)
        else
            widget = CreateFrame(frameType or "Frame", nil, parent, template)
        end
        widget.widgetType = widgetType
        widget:Show()
    else
        -- Recycle existing.
        widget:SetParent(parent)
        widget:ClearAllPoints()
        widget:Show()
    end

    widget._inPool = false

    -- Ensure visibility above parent (fixes vanishing buttons behind backgrounds)
    if widget.SetFrameLevel then
        widget:SetFrameLevel(parent:GetFrameLevel() + 5)
    end

    return widget
end

function Interface:ReleaseWidget(widget)
    if not widget or not widget.widgetType then return end

    -- Guard against double-release: if the widget is already pooled, bail.
    if widget._inPool then return end

    local pool = self.WidgetPool[widget.widgetType]
    if not pool then
        pool = {}
        self.WidgetPool[widget.widgetType] = pool
    end

    widget:Hide()
    widget:ClearAllPoints()
    widget:SetParent(nil)

    -- Clear script handlers to prevent ghost callbacks from previous lifecycle.
    if widget.SetScript then
        local scripts = {
            "OnClick", "OnEnter", "OnLeave", "OnValueChanged",
            "OnEditFocusLost", "OnEnterPressed", "OnChar", "OnTextChanged",
            "OnUpdate"
        }
        for _, scriptName in ipairs(scripts) do
            if widget:HasScript(scriptName) then
                widget:SetScript(scriptName, nil)
            end
        end
    end

    -- Reset visual state that might persist.
    widget:SetAlpha(1)
    if widget.Enable then widget:Enable() end
    if widget.SetScale then widget:SetScale(1) end

    -- FontStrings: clear stale width / word-wrap so recycled labels are clean.
    if widget.SetWidth and widget.SetWordWrap then
        widget:SetWidth(0)
        widget:SetWordWrap(false)
    end

    -- ScrollingMessageFrame: reset fading and clear messages to prevent cross-page contamination.
    if widget.widgetType == "ScrollingMessageFrame" then
        if widget.Clear then widget:Clear() end
        if widget.SetFading then widget:SetFading(true) end
        if widget.SetMaxLines then widget:SetMaxLines(100) end
    end

    widget._inPool = true
    pool[#pool + 1] = widget
end

function Interface:GetTooltip(key)
    local tip = SETTING_TOOLTIPS[key]
    if tip and (key == "EditBox.InputBg" or key == "EditBox.LabelBg") then
        if self:GetConfigPath({ "EditBox", "UseBlizzardSkinProxy" }) == true then
            tip = tip ..
                "\n\n|cFFFFD100Note:|r Blizzard's skin is pre-coloured. For best results, disable the skin proxy and use Yapper's own appearance settings."
        end
    end
    return tip
end

function Interface:AttachTooltip(region, tooltipText, titleText)
    if not region or type(tooltipText) ~= "string" or tooltipText == "" then return end
    if region.EnableMouse then
        region:EnableMouse(true)
    end

    local function onEnter(selfFrame)
        -- Restore any leftover inflated fonts from a prior hover before
        -- measuring base sizes, so the offset never compounds.
        if GameTooltip._yFontBackup then
            for _, bk in ipairs(GameTooltip._yFontBackup) do
                if bk.fs and bk.file then
                    pcall(bk.fs.SetFont, bk.fs, bk.file, bk.size, bk.flags)
                end
            end
            GameTooltip._yFontBackup = nil
        end

        GameTooltip:SetOwner(selfFrame, "ANCHOR_RIGHT")
        if type(titleText) == "string" and titleText ~= "" then
            GameTooltip:AddLine(titleText, 1, 1, 1, true)
            GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
        else
            ---@diagnostic disable-next-line: param-type-mismatch
            GameTooltip:SetText(tooltipText, nil, nil, nil, nil, true)
        end
        GameTooltip:Show()

        -- Scale tooltip font proportionally with the UI font offset, but
        -- clamp so the tooltip never exceeds screen width.
        local offset = Interface:GetUIFontOffset()
        if offset ~= 0 then
            local screenW = GetScreenWidth() or 1920
            local maxTipW = screenW * 0.45 -- allow up to 45% of screen

            -- Snapshot base sizes BEFORE any modification.
            local regions = {}
            for _, region in pairs({ GameTooltip:GetRegions() }) do
                if region:IsObjectType("FontString") then
                    ---@diagnostic disable-next-line: undefined-field
                    local fontFile, fontSize, fontFlags = region:GetFont()
                    if fontFile and fontSize then
                        regions[#regions + 1] = { fs = region, file = fontFile, size = fontSize, flags = fontFlags or "" }
                    end
                end
            end

            -- Save originals so onLeave can restore them.
            GameTooltip._yFontBackup = regions

            -- Binary-search for the largest usable offset in [0, offset].
            local bestOffset = 0
            local lo, hi = 0, offset
            for _ = 1, 8 do
                local mid = math_floor((lo + hi) / 2 + 0.5)
                if mid == 0 then
                    lo = 0; break
                end
                for _, r in ipairs(regions) do
                    r.fs:SetFont(r.file, r.size + mid, r.flags)
                end
                GameTooltip:Show()
                local tipW = GameTooltip:GetWidth() or 0
                if tipW <= maxTipW then
                    bestOffset = mid
                    lo = mid
                else
                    hi = mid - 1
                end
                if lo >= hi then break end
            end

            -- Apply final sizes.
            for _, r in ipairs(regions) do
                r.fs:SetFont(r.file, r.size + bestOffset, r.flags)
            end
            GameTooltip:Show()
        end
    end

    local function onLeave()
        -- Restore original font sizes before hiding so the next tooltip
        -- starts from genuine base sizes, not our inflated ones.
        if GameTooltip._yFontBackup then
            for _, bk in ipairs(GameTooltip._yFontBackup) do
                if bk.fs and bk.file then
                    pcall(bk.fs.SetFont, bk.fs, bk.file, bk.size, bk.flags)
                end
            end
            GameTooltip._yFontBackup = nil
        end
        GameTooltip:Hide()
    end

    -- Cleanly replace recycled pool widgets.
    if region.SetScript and region.HasScript
        and region:HasScript("OnEnter") then
        region:SetScript("OnEnter", onEnter)
        region:SetScript("OnLeave", onLeave)
    elseif region.HookScript then
        region:HookScript("OnEnter", onEnter)
        region:HookScript("OnLeave", onLeave)
    end
end

function Interface:CreateResetButton(parent, x, y, onClick)
    -- Shared reset control helper for scalar/color rows.
    local btn = self:AcquireWidget("ResetButton", parent, "UIPanelButtonTemplate", "Button")
    btn:SetSize(58, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    btn:SetText("Reset")
    btn:SetEnabled(true)
    btn:SetAlpha(1.0)
    btn:SetScript("OnClick", onClick)
    self:AddControl(btn)
    return btn
end

function Interface:CreateLabel(parent, text, x, y, width, tooltipText, fontObj)
    -- Labels are tracked like controls so rebuild cleanup is consistent.
    -- Default to White (GameFontHighlight) for option labels.
    local font = fontObj or "GameFontHighlight"

    local fs = self:AcquireWidget("Label", parent, font, "FontString")
    fs:SetFontObject(font)

    if font == "GameFontNormal" then
        fs:SetTextColor(1, 0.82, 0, 1) -- Gold for Titles
    else
        fs:SetTextColor(1, 1, 1, 1)    -- White for Options
    end

    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetWidth(width)
    fs:SetWordWrap(false)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    self:AddControl(fs)

    -- Detect truncation: if the natural text width exceeds the label width,
    -- the label is being ellipsized.  In that case, show the full text as a
    -- title line above the description tooltip.
    local isTruncated = (fs.IsTruncated and fs:IsTruncated())
        or ((fs:GetStringWidth() or 0) > width)
    local titleLine = isTruncated and text or nil

    -- Build a combined tooltip: if no explicit description was provided but
    -- the label IS truncated, still show a tooltip with just the full text.
    local effectiveTooltip = tooltipText
    if not effectiveTooltip or effectiveTooltip == "" then
        if isTruncated then
            effectiveTooltip = text -- tooltip body = full label
            titleLine = nil         -- no separate title needed
        end
    end

    -- For tooltips, spawn an invisible hit-frame sized to the actual rendered
    -- text so the tooltip appears next to the label, not out in space.
    if type(effectiveTooltip) == "string" and effectiveTooltip ~= "" then
        self:AttachTooltip(fs, effectiveTooltip, titleLine)
        local hitFrame = self:AcquireWidget("LabelHitFrame", parent, nil, "Frame")
        hitFrame:SetPoint("TOPLEFT", fs, "TOPLEFT", 0, 2)
        hitFrame:SetPoint("BOTTOMLEFT", fs, "BOTTOMLEFT", 0, -2)
        -- Size to actual text width so ANCHOR_RIGHT stays near the label.
        local textW = fs:GetStringWidth() or 100
        hitFrame:SetWidth(math_min(textW + 8, width))
        hitFrame:SetFrameLevel(parent:GetFrameLevel() + 6)
        hitFrame:EnableMouse(true)
        self:AttachTooltip(hitFrame, effectiveTooltip, titleLine)
        self:AddControl(hitFrame)
    end
    return fs
end

-- ---------------------------------------------------------------------------
-- Unified ColorPicker helper — used by both channel and config pickers.
-- ---------------------------------------------------------------------------
-- opts = {
--   color       : {r,g,b,a}   — starting colour
--   hasOpacity  : boolean      — show alpha slider?
--   onApply     : function(newColor)   — called on confirm / live tick
--   onCancel    : function(prevColor)  — called on cancel
-- }
local function OpenColorPicker(opts)
    local color       = opts.color
    local previous    = CopyColour(color)
    local liveTicker  = nil
    local lastApplied = nil

    local function sameColor(lhs, rhs)
        if type(lhs) ~= "table" or type(rhs) ~= "table" then return false end
        return lhs.r == rhs.r and lhs.g == rhs.g and lhs.b == rhs.b and lhs.a == rhs.a
    end

    local function stopLiveTicker()
        if liveTicker then
            liveTicker:Cancel(); liveTicker = nil
        end
    end

    -- Read current state from whichever picker API is available.
    local function readPickerColor(callbackData)
        local r, g, b = color.r or 1, color.g or 1, color.b or 1
        local a = color.a or 1
        local hasRgb, hasAlpha = false, false

        if type(callbackData) == "table" then
            if type(callbackData.r) == "number" then
                r, g, b, hasRgb = callbackData.r, callbackData.g, callbackData.b, true
            end
            if type(callbackData.opacity) == "number" then
                a, hasAlpha = callbackData.opacity, true
            elseif type(callbackData.a) == "number" then
                a, hasAlpha = callbackData.a, true
            end
        end

        -- Direct frame polling fallback (for live-updates).
        if not hasRgb and ColorPickerFrame then
            if ColorPickerFrame.GetColorRGB then
                local pr, pg, pb = ColorPickerFrame:GetColorRGB()
                if pr then r, g, b, hasRgb = pr, pg, pb, true end
            elseif ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker then
                local picker = ColorPickerFrame.Content.ColorPicker
                if picker.GetColorRGB then
                    local pr, pg, pb = picker:GetColorRGB()
                    if pr then r, g, b, hasRgb = pr, pg, pb, true end
                end
            end
        end

        if not hasAlpha and ColorPickerFrame then
            if ColorPickerFrame.GetColorAlpha then
                local alpha = ColorPickerFrame:GetColorAlpha()
                if alpha then a, hasAlpha = alpha, true end
            elseif ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker then
                local picker = ColorPickerFrame.Content.ColorPicker
                if picker.GetColorAlpha then
                    local alpha = picker:GetColorAlpha()
                    if alpha then a, hasAlpha = alpha, true end
                end
            end
            -- Last resort: legacy property check.
            if not hasAlpha and type(ColorPickerFrame.opacity) == "number" then
                a = 1 - ColorPickerFrame.opacity
            end
        end

        return Clamp01(r, 1), Clamp01(g, 1), Clamp01(b, 1), Clamp01(a, 1)
    end

    local function applyCurrentColor(callbackData)
        local r, g, b, a = readPickerColor(callbackData)
        local nextColor = { r = r, g = g, b = b, a = a }
        if sameColor(lastApplied, nextColor) then return end
        lastApplied = CopyColour(nextColor)
        opts.onApply(nextColor)
    end

    local function restorePreviousColor(prev)
        stopLiveTicker()
        prev = prev or previous
        if prev then
            opts.onCancel(CopyColour(prev))
            lastApplied = CopyColour(prev)
        end
    end

    local function startLiveTicker()
        stopLiveTicker()
        if not (C_Timer and C_Timer.NewTicker) then return end
        liveTicker = C_Timer.NewTicker(0.05, function(ticker)
            if not ColorPickerFrame or not ColorPickerFrame:IsShown() then
                ticker:Cancel(); liveTicker = nil; return
            end
            applyCurrentColor()
        end)
    end

    -- Modern API path.
    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
        local info                      = {
            r              = color.r,
            g              = color.g,
            b              = color.b,
            opacity        = opts.hasOpacity and (color.a or 1) or nil,
            hasOpacity     = opts.hasOpacity,
            swatchFunc     = function(data) applyCurrentColor(data) end,
            opacityFunc    = opts.hasOpacity and function(data) applyCurrentColor(data) end or nil,
            cancelFunc     = function(prev) restorePreviousColor(prev) end,
            previousValues = previous,
        }
        ColorPickerFrame.previousValues = previous
        ColorPickerFrame.func           = applyCurrentColor
        ColorPickerFrame.opacityFunc    = applyCurrentColor
        ColorPickerFrame.cancelFunc     = restorePreviousColor
        ColorPickerFrame:SetupColorPickerAndShow(info)
        if opts.hasOpacity then startLiveTicker() end
        return
    end

    -- Legacy API fallback.
    if ColorPickerFrame then
        ---@diagnostic disable: undefined-field
        ColorPickerFrame.hasOpacity = opts.hasOpacity
        ColorPickerFrame.opacity    = opts.hasOpacity and (1 - (color.a or 1)) or nil
        if ColorPickerFrame.SetColorRGB then
            ColorPickerFrame:SetColorRGB(color.r, color.g, color.b)
        end
        ColorPickerFrame.previousValues = previous
        ColorPickerFrame.func           = applyCurrentColor
        ColorPickerFrame.opacityFunc    = applyCurrentColor
        ColorPickerFrame.cancelFunc     = restorePreviousColor
        ---@diagnostic enable: undefined-field
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
        if opts.hasOpacity then startLiveTicker() end
    end
end

function Interface:CreateCheckBox(parent, label, path, cursor)
    local y = cursor:Y()
    local cb = self:AcquireWidget("CheckBox", parent, "UICheckButtonTemplate", "CheckButton")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", LAYOUT.WINDOW_PADDING, y)


    local text = self:AcquireWidget("Label", parent, "GameFontHighlight", "FontString")
    text:SetFontObject("GameFontHighlight")
    text:SetTextColor(1, 1, 1, 1) -- Force white text (fix recycling color retention)
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetWidth(0)              -- Clear stale width from pool
    text:SetWordWrap(false)
    text:SetText(label)

    local tooltip = self:GetTooltip(JoinPath(path))

    local val = self:GetConfigPath(path)
    cb:SetChecked(val == true)

    local disabled = self:IsPathDisabledByTheme(path)
    if disabled then
        cb:SetEnabled(false)
        text:SetTextColor(0.5, 0.5, 0.5, 1) -- Grey out if disabled
    else
        cb:SetEnabled(true)
        text:SetTextColor(1, 1, 1, 1)
    end

    cb:SetScript("OnClick", function(selfFrame)
        local checked = selfFrame:GetChecked() == true
        
        -- Validation: If enabling spellcheck, ensure we have at least one dictionary addon.
        if checked and path[1] == "Spellcheck" and path[2] == "Enabled" then
            local spell = YapperTable and YapperTable.Spellcheck
            if spell and spell.HasAnyDictionary and not spell:HasAnyDictionary() then
                selfFrame:SetChecked(false)
                StaticPopup_Show("YAPPER_DICTS_MISSING_LINK")
                return
            end
        end

        Interface:SetLocalPath(path, checked)
    end)

    self:AddControl(cb)
    self:AddControl(text)
    self:AttachTooltip(cb, tooltip)
    self:AttachTooltip(text, tooltip)

    cursor:Advance(self:ScaledRow(LAYOUT.ROW_CHECKBOX))
    return cb
end

function Interface:CreateTextInput(parent, label, path, cursor)
    local y = cursor:Y()
    self:CreateLabel(parent, label, LAYOUT.LABEL_X, y - 2, LAYOUT.LABEL_WIDTH, self:GetTooltip(JoinPath(path)))

    local edit = self:AcquireWidget("InputBox", parent, "InputBoxTemplate", "EditBox")
    edit:SetAutoFocus(false)
    edit:SetSize(160, 22)
    edit:SetPoint("TOPLEFT", parent, "TOPLEFT", LAYOUT.CONTROL_X, y)

    local current = self:GetConfigPath(path)
    if current ~= nil then
        -- For chat marker fields, show the trimmed marker (no added spacing)
        if JoinPath(path) == "Chat.DELINEATOR" or JoinPath(path) == "Chat.PREFIX" then
            edit:SetText(TrimString(current))
        else
            edit:SetText(tostring(current))
        end
    else
        edit:SetText("")
    end

    -- Commit on enter/focus loss, preserving numeric paths as numbers.
    local function commit()
        local defaults = self:GetDefaultsRoot()
        local cursor = defaults
        for i = 1, #path do
            if type(cursor) ~= "table" then break end
            cursor = cursor[path[i]]
        end

        local raw = edit:GetText() or ""
        if type(cursor) == "number" then
            local num = tonumber(raw)
            if num ~= nil then
                local stored = Interface:SetLocalPath(path, num)
                if JoinPath(path) == "FrameSettings.MouseWheelStepRate" then
                    Interface.MouseWheelStepRate = num
                end
                if stored ~= nil then
                    edit:SetText(tostring(stored))
                end
            end
        else
            local stored = Interface:SetLocalPath(path, raw)
            if type(stored) == "string" then
                -- For marker fields, display the trimmed marker to the user
                if JoinPath(path) == "Chat.DELINEATOR" or JoinPath(path) == "Chat.PREFIX" then
                    edit:SetText(TrimString(stored))
                else
                    edit:SetText(stored)
                end
            end
        end
    end

    edit:SetScript("OnEnterPressed", function(selfFrame)
        commit()
        selfFrame:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(selfFrame)
        selfFrame:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function()
        commit()
    end)

    local resetBtn = Interface:CreateResetButton(parent, LAYOUT.RESET_X, y, function()
        local d = Interface:GetDefaultPath(path)
        if d ~= nil then
            Interface:SetLocalPath(path, d)
            edit:SetText(tostring(d))
        end
    end)

    local disabled = self:IsPathDisabledByTheme(path)
    if disabled then
        edit:SetEnabled(false)
        edit:SetAlpha(0.6)
        resetBtn:SetEnabled(false)
        resetBtn:SetAlpha(0.6)
    else
        edit:SetEnabled(true)
        edit:SetAlpha(1.0)
        resetBtn:SetEnabled(true)
        resetBtn:SetAlpha(1.0)
    end

    self:AddControl(edit)
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_TEXT_INPUT))
end

function Interface:CreateColorPickerControl(parent, label, path, cursor)
    local y = cursor:Y()
    self:CreateLabel(parent, label, LAYOUT.LABEL_X, y - 2, LAYOUT.LABEL_WIDTH, self:GetTooltip(JoinPath(path)))
    local fullPath = JoinPath(path)

    local btn = self:AcquireWidget("ColorPickerButton", parent, "UIPanelButtonTemplate", "Button")
    btn:SetSize(120, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", LAYOUT.CONTROL_X, y)

    local swatch = btn.swatch
    if not swatch then
        swatch = btn:CreateTexture(nil, "ARTWORK")
        swatch:SetPoint("LEFT", btn, "LEFT", 6, 0)
        swatch:SetSize(16, 16)
        swatch:SetTexture("Interface\\Buttons\\WHITE8x8")
        btn.swatch = swatch
    end

    local labelFS = btn.labelFS
    if not labelFS then
        labelFS = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        labelFS:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
        labelFS:SetText("Pick colour")
        btn.labelFS = labelFS
    end

    -- Keep swatch in sync with live config state.
    local function refreshSwatch()
        local color = self:GetConfigPath(path) or { r = 1, g = 1, b = 1, a = 1 }
        if IsColourTable(color) then
            swatch:SetVertexColor(color.r, color.g, color.b, color.a or 1)
        else
            swatch:SetVertexColor(1, 1, 1, 1)
        end
        if fullPath == "EditBox.TextColor" then
            self:UpdateOverrideTextColorCheckboxState()
        end
    end

    local function applyStoredColor(colorValue)
        Interface:SetLocalPath(path, colorValue)
        refreshSwatch()
    end

    btn:SetScript("OnClick", function()
        local color = self:GetConfigPath(path) or { r = 1, g = 1, b = 1, a = 1 }
        if not IsColourTable(color) then
            color = { r = 1, g = 1, b = 1, a = 1 }
        end
        color.a = Clamp01(color.a, 1)

        OpenColorPicker({
            color      = CopyColour(color),
            hasOpacity = true,
            onApply    = function(newColor) applyStoredColor(newColor) end,
            onCancel   = function(prev) applyStoredColor(CopyColour(prev)) end,
        })
    end)

    local resetBtn = Interface:CreateResetButton(parent, LAYOUT.RESET_X, y, function()
        local defaultColor = Interface:GetDefaultPath(path)
        if IsColourTable(defaultColor) then
            applyStoredColor(CopyColour(defaultColor))
        end
    end)

    local disabled = self:IsPathDisabledByTheme(path)
    if disabled then
        btn:SetEnabled(false)
        btn:SetAlpha(0.6)
        resetBtn:SetEnabled(false)
        resetBtn:SetAlpha(0.6)
    else
        btn:SetEnabled(true)
        btn:SetAlpha(1.0)
        resetBtn:SetEnabled(true)
        resetBtn:SetAlpha(1.0)
    end

    refreshSwatch()
    self:AddControl(btn)
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_COLOR_PICKER))
    return btn
end

function Interface:CreateFontSizeDropdown(parent, label, path, cursor)
    local y = cursor:Y()
    self:CreateLabel(parent, label, LAYOUT.LABEL_X, y - 2, LAYOUT.LABEL_WIDTH, self:GetTooltip(JoinPath(path)))

    local slider = self:AcquireWidget("Slider", parent, "OptionsSliderTemplate", "Slider")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 165, y)
    slider:SetWidth(146)
    slider:SetHeight(20)
    slider:SetMinMaxValues(8, 64)
    slider:SetValueStep(2)
    slider:SetObeyStepOnDrag(true)

    local current = RoundToEven(self:GetConfigPath(path))
    slider:SetValue(current)
    slider._lastSaved = current

    local sliderName = slider:GetName()
    local low = sliderName and _G[sliderName .. "Low"] or nil
    local high = sliderName and _G[sliderName .. "High"] or nil
    local text = sliderName and _G[sliderName .. "Text"] or nil
    if low then
        low:SetText(""); low:Hide()
    end
    if high then
        high:SetText(""); high:Hide()
    end
    if text then
        text:SetText(""); text:Hide()
    end

    local valueFs = self:AcquireWidget("Label", parent, "GameFontHighlightSmall", "FontString")
    valueFs:SetPoint("LEFT", slider, "RIGHT", 6, 0)
    valueFs:SetText(tostring(current))

    local fontPad = self:GetUIFontOffset()
    local dd = self:AcquireWidget("Dropdown", parent, "UIDropDownMenuTemplate", "Frame")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 155, y - 26 - fontPad)
    UIDropDownMenu_SetWidth(dd, 126)
    UIDropDownMenu_SetText(dd, tostring(current))

    UIDropDownMenu_Initialize(dd, function(frame, level)
        for size = 8, 64, 2 do
            local info = UIDropDownMenu_CreateInfo()
            info.text = tostring(size)
            info.func = function()
                UIDropDownMenu_SetText(frame, tostring(size))
                slider:SetValue(size)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- Slider is source of truth; dropdown mirrors and can drive slider updates.
    slider:SetScript("OnValueChanged", function(selfFrame, value)
        local even = RoundToEven(value)
        if selfFrame:GetValue() ~= even then
            selfFrame:SetValue(even)
            return
        end
        valueFs:SetText(tostring(even))
        UIDropDownMenu_SetText(dd, tostring(even))
        if selfFrame._lastSaved ~= even then
            Interface:SetLocalPath(path, even)
            selfFrame._lastSaved = even
        end
    end)

    local resetBtn = Interface:CreateResetButton(parent, LAYOUT.RESET_X, y - 44 - fontPad, function()
        local defaultSize = RoundToEven(Interface:GetDefaultPath(path))
        slider:SetValue(defaultSize)
        UIDropDownMenu_SetText(dd, tostring(defaultSize))
    end)
    self:AttachTooltip(resetBtn, "Reset font size to default.")

    local disabled = self:IsPathDisabledByTheme(path)
    if disabled then
        slider:SetEnabled(false)
        slider:SetAlpha(0.6)
        resetBtn:SetEnabled(false)
        resetBtn:SetAlpha(0.6)
        dd:SetAlpha(0.6)
    else
        slider:SetEnabled(true)
        slider:SetAlpha(1.0)
        resetBtn:SetEnabled(true)
        resetBtn:SetAlpha(1.0)
        dd:SetAlpha(1.0)
    end

    -- Ensure the initial value is persisted and all controls are in sync.
    slider:SetValue(current)

    self:AddControl(slider)
    self:AddControl(valueFs)
    self:AddControl(dd)
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_FONT_SIZE))
    return slider
end

function Interface:CreateFontOutlineDropdown(parent, label, path, cursor)
    local y = cursor:Y()
    self:CreateLabel(parent, label, LAYOUT.LABEL_X, y - 2, LAYOUT.LABEL_WIDTH, self:GetTooltip(JoinPath(path)))

    local dd = self:AcquireWidget("Dropdown", parent, "UIDropDownMenuTemplate", "Frame")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 165, y - 4)
    UIDropDownMenu_SetWidth(dd, 140)

    local current = NormalizeFontFlags(self:GetConfigPath(path))
    UIDropDownMenu_SetText(dd, GetFontFlagsLabel(current))

    UIDropDownMenu_Initialize(dd, function(frame, level)
        for _, option in ipairs(FONT_OUTLINE_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.label
            info.checked = (option.value == current)
            info.func = function()
                current = option.value
                Interface:SetLocalPath(path, option.value)
                UIDropDownMenu_SetText(frame, option.label)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local resetBtn = Interface:CreateResetButton(parent, LAYOUT.RESET_X, y - 4, function()
        local d = Interface:GetDefaultPath(path)
        current = NormalizeFontFlags(d)
        Interface:SetLocalPath(path, d)
        UIDropDownMenu_SetText(dd, GetFontFlagsLabel(current))
    end)

    local disabled = self:IsPathDisabledByTheme(path)
    if disabled then
        dd:SetAlpha(0.6)
        resetBtn:SetEnabled(false)
        resetBtn:SetAlpha(0.6)
    else
        dd:SetAlpha(1.0)
        resetBtn:SetEnabled(true)
        resetBtn:SetAlpha(1.0)
    end

    self:AddControl(dd)
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_FONT_OUTLINE))
    return dd
end

-- Export OpenColorPicker for Pages.lua.
Interface._OpenColorPicker = OpenColorPicker
