--[[
    Interface/Pages.lua
    Complex custom control pages: channel colour overrides, YALLM learning
    summary, queue diagnostics, credits, spellcheck dropdowns, user
    dictionary editor, and theme selector.
]]

local _, YapperTable = ...
local Interface      = YapperTable.Interface

-- Re-localise shared helpers from hub.
local JoinPath                    = Interface.JoinPath
local IsColourTable               = Interface.IsColourTable
local CopyColour                  = Interface.CopyColour
local Clamp01                     = Interface.Clamp01
local LAYOUT                      = Interface._LAYOUT
local COLOUR_KEYS                 = Interface._COLOUR_KEYS
local CHANNEL_OVERRIDE_OPTIONS    = Interface._CHANNEL_OVERRIDE_OPTIONS
local CREDITS_DICTIONARIES_BUNDLED  = Interface._CREDITS_BUNDLED
local CREDITS_DICTIONARIES_OPTIONAL = Interface._CREDITS_OPTIONAL
local FRIENDLY_LABELS             = Interface._FRIENDLY_LABELS
local SETTING_TOOLTIPS            = Interface._SETTING_TOOLTIPS

-- OpenColorPicker is defined in Widgets.lua which loads before us.
local OpenColorPicker = Interface._OpenColorPicker

-- Re-localise Lua globals.
local type       = type
local pairs      = pairs
local ipairs     = ipairs
local tostring   = tostring
local tonumber   = tonumber
local math_abs   = math.abs
local math_floor = math.floor
local table_sort    = table.sort
local table_concat  = table.concat
local string_format = string.format

local TrimString    = Interface.TrimString

function Interface:CreateChannelOverrideControls(parent, cursor)
    -- Custom row block (outside schema renderer) for per-channel colours.
    local y = cursor:Y()
    local title = self:CreateLabel(parent, "Channel Text Colour Overrides",
        LAYOUT.WINDOW_PADDING, y, 340, self:GetTooltip("CHANNEL.HEADER"), "GameFontNormal")

    local rows = {}

    local function getChannelColor(key)
        local color = self:GetConfigPath({ "EditBox", "ChannelTextColors", key })
        if IsColourTable(color) then
            return color
        end
        local def = self:GetDefaultPath({ "EditBox", "ChannelTextColors", key })
        if IsColourTable(def) then
            return def
        end
        return { r = 1, g = 1, b = 1, a = 1 }
    end

    local function setChannelColor(key, color)
        self:SetLocalPath({ "EditBox", "ChannelTextColors", key }, color)
    end

    local function resetAllChannelColors()
        for _, option in ipairs(CHANNEL_OVERRIDE_OPTIONS) do
            local def = self:GetDefaultPath({ "EditBox", "ChannelTextColors", option.key })
            if IsColourTable(def) then
                setChannelColor(option.key, CopyColour(def))
            end
        end
        for _, row in ipairs(rows) do
            if row.refreshColor then row.refreshColor() end
        end
    end

    local resetAllBtn = self:CreateResetButton(parent, 290, y - 2, function()
        resetAllChannelColors()
    end)
    resetAllBtn:SetSize(74, 20)
    resetAllBtn:SetText("Reset all")
    self:AttachTooltip(resetAllBtn, self:GetTooltip("CHANNEL.RESET_ALL"))

    cursor:Advance(self:ScaledRow(LAYOUT.ROW_CHANNEL_HEADER))
    y = cursor:Y()

    self:CreateLabel(parent, "Colour", 136, y, 60)
    self:CreateLabel(parent, "Master", 252, y, 50, self:GetTooltip("CHANNEL.MASTER"))
    self:CreateLabel(parent, "Override", 322, y, 60, self:GetTooltip("CHANNEL.OVERRIDE"))

    local masterHelp = self:AcquireWidget("HelpButton", parent, "UIPanelButtonTemplate", "Button")
    masterHelp:SetSize(14, 14)
    masterHelp:SetPoint("TOPLEFT", parent, "TOPLEFT", 236, y + 2)
    masterHelp:SetText("?")
    masterHelp:SetScript("OnEnter", function(selfFrame)
        GameTooltip:SetOwner(selfFrame, "ANCHOR_RIGHT")
        ---@diagnostic disable-next-line: missing-parameter
        GameTooltip:SetText("Master Channel")
        GameTooltip:AddLine("Choose one channel as the colour source.", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Channels with Override checked", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("use the master's colour.", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    masterHelp:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self:AddControl(masterHelp)

    cursor:Advance(self:ScaledRow(LAYOUT.ROW_CHANNEL_LABELS))
    y = cursor:Y()

    local function getMaster()
        local m = self:GetConfigPath({ "EditBox", "ChannelColorMaster" })
        if type(m) ~= "string" then return nil end
        if m == "" then return nil end
        for _, option in ipairs(CHANNEL_OVERRIDE_OPTIONS) do
            if option.key == m then
                return m
            end
        end
        return nil
    end

    local function getOverrideValue(key)
        return self:GetConfigPath({ "EditBox", "ChannelColorOverrides", key }) == true
    end

    local function refreshRows()
        local master = getMaster()
        for _, row in ipairs(rows) do
            local isMaster = (row.key == master)
            row.master:SetChecked(isMaster)
            row.refreshColor()

            if isMaster then
                if getOverrideValue(row.key) then
                    self:SetLocalPath({ "EditBox", "ChannelColorOverrides", row.key }, false)
                end
                row.override:SetChecked(false)
                row.override:Disable()
            else
                row.override:Enable()
                row.override:SetChecked(getOverrideValue(row.key))
            end
        end
    end

    for _, option in ipairs(CHANNEL_OVERRIDE_OPTIONS) do
        self:CreateLabel(parent, option.label, LAYOUT.LABEL_X, y - 2, LAYOUT.LABEL_WIDTH)

        local colorBtn = self:AcquireWidget("ColorPickerButtonSmall", parent, "UIPanelButtonTemplate", "Button")
        colorBtn:SetSize(72, 20)
        colorBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 132, y + 1)
        colorBtn:SetText("Pick")

        local swatch = colorBtn.swatch
        if not swatch then
            swatch = colorBtn:CreateTexture(nil, "ARTWORK")
            swatch:SetPoint("LEFT", colorBtn, "LEFT", 6, 0)
            swatch:SetSize(14, 14)
            swatch:SetTexture("Interface\\Buttons\\WHITE8x8")
            colorBtn.swatch = swatch
        end

        local function refreshColor()
            local c = getChannelColor(option.key) or { r = 1, g = 1, b = 1, a = 1 }
            swatch:SetVertexColor(c.r or 1, c.g or 1, c.b or 1, 1)
        end

        colorBtn:SetScript("OnClick", function()
            local clr = CopyColour(getChannelColor(option.key))
            OpenColorPicker({
                color      = clr,
                hasOpacity = false,
                onApply    = function(newColor)
                    setChannelColor(option.key, {
                        r = newColor.r, g = newColor.g, b = newColor.b, a = 1,
                    })
                    refreshColor()
                end,
                onCancel   = function(prev)
                    setChannelColor(option.key, prev)
                    refreshColor()
                end,
            })
        end)

        local resetBtn = self:CreateResetButton(parent, 208, y + 1, function()
            local key = option.key

            -- Restore the active theme's default value into local config so
            -- "Def" reflects the theme currently in use. This makes the
            -- reset behaviour predictable regardless of which theme is
            -- active (including the proxy/'Yapper Default' skin).
            local root = self:GetLocalConfigRoot()
            if type(root.EditBox) ~= "table" then root.EditBox = {} end
            if type(root.EditBox.ChannelTextColors) ~= "table" then root.EditBox.ChannelTextColors = {} end

            -- Prefer the active theme's channel colour if available, else
            -- fall back to the global defaults from Core.
            local applied = nil
            if YapperTable and YapperTable.Theme and type(YapperTable.Theme.GetTheme) == "function" then
                local th = YapperTable.Theme:GetTheme()
                if th and type(th.channelTextColors) == "table" and type(th.channelTextColors[key]) == "table" then
                    applied = CopyColour(th.channelTextColors[key])
                end
            end
            if not applied then
                local d = self:GetDefaultPath({ "EditBox", "ChannelTextColors", key })
                if type(d) == "table" then applied = CopyColour(d) end
            end
            if type(applied) == "table" then
                -- Use SetLocalPath to ensure proper normalisation and hooks.
                self:SetLocalPath({ "EditBox", "ChannelTextColors", key }, applied)
            else
                -- Remove explicit local value so config falls back to global.
                local troot = self:GetLocalConfigRoot()
                if type(troot.EditBox) == "table" and type(troot.EditBox.ChannelTextColors) == "table" then
                    troot.EditBox.ChannelTextColors[option.key] = nil
                    _G.YapperLocalConf = troot
                end
            end
            -- Ensure we don't mark this as a user theme override so future
            -- theme changes can still apply when appropriate.
            local clearRoot = self:GetLocalConfigRoot()
            if type(clearRoot._themeOverrides) == "table" then
                clearRoot._themeOverrides[key] = nil
            end
            _G.YapperLocalConf = clearRoot
            -- Debug: raw stored value in local config for verification.
            local rawStored = (type(clearRoot.EditBox) == "table" and type(clearRoot.EditBox.ChannelTextColors) == "table") and
                clearRoot.EditBox.ChannelTextColors[key] or nil

            -- If the Blizzard ColorPickerFrame is present, update its cached
            -- colour so the next OpenColorPicker shows the correct default
            -- immediately rather than an older cached value.
            if ColorPickerFrame then
                local appliedColor = rawStored or self:GetDefaultPath({ "EditBox", "ChannelTextColors", key })
                if type(appliedColor) == "table" then
                    -- Try direct API first.
                    if ColorPickerFrame.SetColorRGB then
                        pcall(function()
                            ColorPickerFrame:SetColorRGB(appliedColor.r or 1, appliedColor.g or 1,
                                appliedColor.b or 1)
                        end)
                    end
                    -- Modern frame content path.
                    if ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker and ColorPickerFrame.Content.ColorPicker.SetColorRGB then
                        pcall(function()
                            ColorPickerFrame.Content.ColorPicker:SetColorRGB(appliedColor.r or 1,
                                appliedColor.g or 1, appliedColor.b or 1)
                        end)
                    end
                    -- Update previousValues so the 'previous' swatch matches.
                    pcall(function()
                        ColorPickerFrame.previousValues = {
                            r = appliedColor.r or 1,
                            g = appliedColor.g or 1,
                            b =
                                appliedColor.b or 1,
                            a = appliedColor.a ~= nil and appliedColor.a or 1
                        }
                    end)
                end
            end

            if type(root.EditBox.ChannelColorOverrides) ~= "table" then
                root.EditBox.ChannelColorOverrides = {}
            end
            -- Uncheck override for this key so Master doesn't force it.
            root.EditBox.ChannelColorOverrides[option.key] = false
            if type(root._themeOverrides) == "table" then
                root._themeOverrides[option.key] = nil
            end
            _G.YapperLocalConf = root

            -- Force UI refresh and reapply to live overlay.
            refreshRows()
            if YapperTable.EditBox and type(YapperTable.EditBox.ApplyConfigToLiveOverlay) == "function" then
                pcall(function() YapperTable.EditBox:ApplyConfigToLiveOverlay(true) end)
            end
        end)
        resetBtn:SetSize(50, 20)
        resetBtn:SetText("Def")
        resetBtn:ClearAllPoints()
        resetBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 208, y + 1)

        local masterCb = self:AcquireWidget("CheckBoxSmall", parent, "UICheckButtonTemplate", "CheckButton")
        masterCb:SetPoint("TOPLEFT", parent, "TOPLEFT", 258, y)

        local overrideCb = self:AcquireWidget("CheckBoxSmall", parent, "UICheckButtonTemplate", "CheckButton")
        overrideCb:SetPoint("TOPLEFT", parent, "TOPLEFT", 328, y)

        masterCb:SetScript("OnClick", function(selfFrame)
            if selfFrame:GetChecked() then
                self:SetLocalPath({ "EditBox", "ChannelColorMaster" }, option.key)
                self:SetLocalPath({ "EditBox", "ChannelColorOverrides", option.key }, false)
            else
                self:SetLocalPath({ "EditBox", "ChannelColorMaster" }, "")
            end
            refreshRows()
        end)

        overrideCb:SetScript("OnClick", function(selfFrame)
            if getMaster() == option.key then
                selfFrame:SetChecked(false)
                return
            end
            self:SetLocalPath(
                { "EditBox", "ChannelColorOverrides", option.key },
                selfFrame:GetChecked() == true
            )
            refreshRows()
        end)

        self:AddControl(colorBtn)
        self:AddControl(masterCb)
        self:AddControl(overrideCb)
        rows[#rows + 1] = {
            key = option.key,
            master = masterCb,
            override = overrideCb,
            refreshColor = refreshColor,
        }

        cursor:Advance(self:ScaledRow(LAYOUT.ROW_CHANNEL_ROW))
        y = cursor:Y()
    end

    refreshRows()
    cursor:Pad(10)
end

-- ---------------------------------------------------------------------------
-- YALLM Learning Page
-- ---------------------------------------------------------------------------

local TIME_UNITS = {
    { s = 31536000, label = "y" },
    { s = 2592000,  label = "mo" },
    { s = 604800,   label = "w" },
    { s = 86400,    label = "d" },
    { s = 3600,     label = "h" },
    { s = 60,       label = "m" },
    { s = 1,        label = "s" },
}

local function FormatRelativeTime(ts)
    if not ts or ts == 0 then return "Never" end
    local now = time()
    local diff = now - ts
    if diff < 10 then return "Just now" end

    for _, unit in ipairs(TIME_UNITS) do
        if diff >= unit.s then
            local val = math_floor(diff / unit.s)
            return val .. unit.label .. " ago"
        end
    end
    return "Just now"
end

function Interface:CreateYALLMLearningPage(parent, cursor)
    local sc = YapperTable.Spellcheck
    local yallm = sc and sc.YALLM
    if not yallm or not yallm.GetDataSummary then
        self:CreateLabel(parent, "YALLM engine not initialized.", LAYOUT.WINDOW_PADDING, cursor:Y(), 400)
        return
    end

    local data = yallm:GetDataSummary()
    if not data then return end

    -- Title: Adaptive Learning (YALLM) - in yellow
    local titleFs = self:CreateLabel(
        parent,
        "Adaptive Learning (YALLM)",
        LAYOUT.WINDOW_PADDING,
        cursor:Y(),
        400,
        "Personalized typing patterns and correction biases stored by the YALLM engine.",
        "GameFontNormal"
    )
    titleFs:SetTextColor(1, 0.82, 0) -- Yellow
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_SECTION))

    -- 1. Top Vocabulary Trends
    cursor:Pad(4)
    self:CreateLabel(parent, "Top Vocabulary Trends", LAYOUT.WINDOW_PADDING, cursor:Y(), 400, nil, "GameFontHighlightMedium")
    cursor:Advance(self:ScaledRow(20))
    
    local freqCount = 0
    if data.freq then
        for i = 1, math.min(5, #data.freq) do
            local item = data.freq[i]
            self:CreateLabel(parent, string.format("%d. %s (%d uses)", i, item.word, item.count), LAYOUT.WINDOW_PADDING + 10, cursor:Y(), 400)
            cursor:Advance(self:ScaledRow(15))
            freqCount = freqCount + 1
        end
    end
    if freqCount == 0 then
        self:CreateLabel(parent, "No word usage recorded yet.", LAYOUT.WINDOW_PADDING + 10, cursor:Y(), 400)
        cursor:Advance(self:ScaledRow(15))
    end
    cursor:Advance(self:ScaledRow(10))

    -- 2. Common Corrections
    self:CreateLabel(parent, "Common Corrections", LAYOUT.WINDOW_PADDING, cursor:Y(), 400, nil, "GameFontHighlightMedium")
    cursor:Advance(self:ScaledRow(20))
    
    local biasCount = 0
    if data.bias then
        for i = 1, math.min(6, #data.bias) do
            local item = data.bias[i]
            local text = string.format("|cffff4444%s|r -> |cff44ff44%s|r (%d times)", item.typo, item.correction, item.count)
            self:CreateLabel(parent, text, LAYOUT.WINDOW_PADDING + 120, cursor:Y(), 460)
            cursor:Advance(self:ScaledRow(15))
            biasCount = biasCount + 1
        end
    end
    if biasCount == 0 then
        self:CreateLabel(parent, "No correction patterns learned yet.", LAYOUT.WINDOW_PADDING + 10, cursor:Y(), 400)
        cursor:Advance(self:ScaledRow(15))
    end
    cursor:Advance(self:ScaledRow(10))

    -- 3. Learning Candidates
    self:CreateLabel(parent, "Learning Candidates", LAYOUT.WINDOW_PADDING, cursor:Y(), 400, nil, "GameFontHighlightMedium")
    cursor:Advance(self:ScaledRow(20))
    
    local autoCount = 0
    if data.auto then
        for i = 1, math.min(3, #data.auto) do
            local item = data.auto[i]
            local progress = math.min(100, math.floor((item.count / (data.threshold or 10)) * 100))
            local text = string.format("%s: %d/%d (%d%% to auto-learned)", item.word, item.count, data.threshold or 10, progress)
            self:CreateLabel(parent, text, LAYOUT.WINDOW_PADDING + 120, cursor:Y(), 400)
            cursor:Advance(self:ScaledRow(15))
            autoCount = autoCount + 1
        end
    end
    if autoCount == 0 then
        self:CreateLabel(parent, "No candidate words identified for auto-learning.", LAYOUT.WINDOW_PADDING + 10, cursor:Y(), 400)
        cursor:Advance(self:ScaledRow(15))
    end
    cursor:Advance(self:ScaledRow(10))

    -- 4. Detailed Data (Granular Tables)
    self:CreateLabel(parent, "Detailed Engine Context", LAYOUT.WINDOW_PADDING, cursor:Y(), 400, nil, "GameFontHighlightMedium")
    cursor:Advance(self:ScaledRow(20))

    local function renderTable(list, headers, emptyMsg, maxHeight)
        if not list or #list == 0 then
            self:CreateLabel(parent, emptyMsg or "No data recorded yet.", LAYOUT.WINDOW_PADDING + 10, cursor:Y(), 400)
            cursor:Advance(self:ScaledRow(20))
            return
        end

        local headerY = cursor:Y()
        local curX = LAYOUT.WINDOW_PADDING + 5
        for _, col in ipairs(headers) do
            local fs = self:AcquireWidget("YALLMTableHead", parent, "GameFontNormalSmall", "FontString")
            fs:SetPoint("TOPLEFT", parent, "TOPLEFT", curX, headerY)
            fs:SetText(col.label)
            fs:SetTextColor(0.6, 0.6, 0.6)
            self:AddControl(fs)
            curX = curX + col.width
        end
        cursor:Advance(self:ScaledRow(16))

        maxHeight = maxHeight or 120
        local rowCount = #list
        local totalContentHeight = rowCount * 15 + 10
        local useScroll = totalContentHeight > maxHeight

        local container = parent
        local renderCursorY = cursor:Y()

        if useScroll then
            local sf = self:AcquireWidget("YALLMTableScroll", parent, nil, "ScrollFrame")
            sf:SetSize(520, maxHeight)
            sf:SetPoint("TOPLEFT", parent, "TOPLEFT", LAYOUT.WINDOW_PADDING, renderCursorY)
            self:AddControl(sf)

            local child = self:AcquireWidget("YALLMTableScrollChild", sf, nil, "Frame")
            child:SetSize(500, totalContentHeight)
            child:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, 0)
            sf:SetScrollChild(child)

            sf:EnableMouseWheel(true)
            sf:SetScript("OnMouseWheel", function(s, delta)
                s:SetVerticalScroll(math.max(0, math.min(totalContentHeight - maxHeight, s:GetVerticalScroll() - delta * 20)))
            end)

            container = child
            renderCursorY = 0
            cursor:Advance(maxHeight + 10)
        end

        for i = 1, #list do
            local row = list[i]
            local rowY = renderCursorY - ((i - 1) * 15)
            local rX = useScroll and 5 or (LAYOUT.WINDOW_PADDING + 5)

            for _, col in ipairs(headers) do
                local val = ""
                if col.key == "typo" then val = row.typo or row.hash or "-"
                elseif col.key == "correction" then val = row.correction or "-"
                elseif col.key == "count" then val = tostring(row.count or 0)
                elseif col.key == "utility" then val = string.format("%.1f", row.utility or 1)
                elseif col.key == "word" then val = row.word or "-"
                elseif col.key == "last" then val = FormatRelativeTime(row.last)
                elseif col.key == "progress" then
                    local progress = math.min(100, math.floor(((row.count or 0) / (data.threshold or 10)) * 100))
                    val = progress .. "%"
                end

                local fs = self:AcquireWidget("YALLMTableRow", container, "GameFontHighlightSmall", "FontString")
                fs:SetPoint("TOPLEFT", container, "TOPLEFT", rX, rowY)
                fs:SetSize(col.width - 5, 14)
                fs:SetJustifyH("LEFT")
                fs:SetText(val)
                self:AddControl(fs)
                rX = rX + col.width
            end
            if not useScroll then cursor:Advance(15) end
        end
        if not useScroll then cursor:Pad(10) end
    end

    -- Full Correction Bias Table
    -- Utility > 1.0 means the user implicitly confirmed the correction was useful
    -- (YALLM promoted a lower-ranked candidate above the natural #1 and the user accepted it).
    self:CreateLabel(parent, "Correction Bias (Full)", LAYOUT.WINDOW_PADDING + 10, cursor:Y(), 520)
    cursor:Advance(self:ScaledRow(15))
    self:CreateLabel(parent, "|cffaaaaaa[Utility > 1.0 = implicitly learned — user accepted a YALLM-promoted candidate]|r",
        LAYOUT.WINDOW_PADDING + 10, cursor:Y(), 520)
    cursor:Advance(self:ScaledRow(14))
    renderTable(data.bias, {
        { label = "Typo",       width = 130, key = "typo" },
        { label = "Correction", width = 130, key = "correction" },
        { label = "Uses",       width = 55,  key = "count" },
        { label = "Utility",    width = 55,  key = "utility" },
        { label = "Last Seen",  width = 110, key = "last" },
    }, "No correction patterns learned yet.", 120)

    -- Phonetic Bias Table
    -- These are generalised patterns learned by sound: if the user consistently
    -- corrects words with the same phonetic shape to the same word, YALLM applies
    -- that generalised bias even to typos it has never seen before.
    self:CreateLabel(parent, "Phonetic Pattern Bias", LAYOUT.WINDOW_PADDING + 10, cursor:Y(), 520)
    cursor:Advance(self:ScaledRow(15))
    self:CreateLabel(parent, "|cffaaaaaa[Generalised corrections by sound — hash is the phonetic fingerprint of the typo]|r",
        LAYOUT.WINDOW_PADDING + 10, cursor:Y(), 520)
    cursor:Advance(self:ScaledRow(14))
    renderTable(data.phBias, {
        { label = "Phonetic Hash", width = 130, key = "typo" },
        { label = "Correction",   width = 130, key = "correction" },
        { label = "Uses",         width = 55,  key = "count" },
        { label = "Last Seen",    width = 110, key = "last" },
    }, "No phonetic patterns learned yet.", 120)

    -- Rejection (Implicit Backtrack) Table
    -- Populated when the user clicks \"More...\" (explicit rejection), OR when
    -- ResolveImplicitTrace detects the user backtracked and manually retyped a word
    -- that YALLM had suggested — i.e. the user silently disagreed with the suggestion.
    self:CreateLabel(parent, "Rejected Suggestions / Implicit Backtracks", LAYOUT.WINDOW_PADDING + 10, cursor:Y(), 520)
    cursor:Advance(self:ScaledRow(15))
    self:CreateLabel(parent, "|cffaaaaaa[Populated when user clicks \"More...\" or manually retypes over a YALLM suggestion]|r",
        LAYOUT.WINDOW_PADDING + 10, cursor:Y(), 520)
    cursor:Advance(self:ScaledRow(14))
    renderTable(data.negBias, {
        { label = "Typo",      width = 130, key = "typo" },
        { label = "Rejected",  width = 130, key = "word" },
        { label = "Rejections",width = 70,  key = "count" },
        { label = "Penalty",   width = 55,  key = "utility" },
        { label = "Last Seen", width = 110, key = "last" },
    }, "No rejections or backtracks recorded yet.", 120)

    -- Full Vocabulary Frequency
    self:CreateLabel(parent, "Complete Vocabulary", LAYOUT.WINDOW_PADDING + 10, cursor:Y(), 520)
    cursor:Advance(self:ScaledRow(15))
    renderTable(data.freq, {
        { label = "Word",      width = 270, key = "word" },
        { label = "Uses",      width = 80,  key = "count" },
        { label = "Last Seen", width = 110, key = "last" },
    }, "No word usage recorded yet.", 150)

    cursor:Advance(self:ScaledRow(20))

    -- 5. Management Section
    self:CreateLabel(parent, "Management", LAYOUT.WINDOW_PADDING, cursor:Y(), 400, nil, "GameFontHighlightMedium")
    cursor:Advance(self:ScaledRow(20))

    -- Reset Button
    local resetAllBtn = self:AcquireWidget("YALLMResetAll", parent, "UIPanelButtonTemplate", "Button")
    resetAllBtn:SetSize(160, 24)
    resetAllBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", LAYOUT.WINDOW_PADDING + 10, cursor:Y() - 2)
    resetAllBtn:SetText("Reset All Learning")
    resetAllBtn:SetScript("OnClick", function()
        StaticPopup_Show("YAPPER_CONFIRM_RESET_LEARNING")
    end)
    self:AddControl(resetAllBtn)
    cursor:Advance(30)
end

function Interface:CreateQueueDiagnostics(parent, cursor)
    local y = cursor:Y()
    self:CreateLabel(
        parent,
        "Queue Diagnostics",
        LAYOUT.WINDOW_PADDING,
        y,
        400,
        "Live state for the event-driven send pipeline.",
        "GameFontNormal"
    )
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_SECTION))

    local frame = self:AcquireWidget("QueueDiagnosticsFrame", parent, nil, "Frame")
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", LAYOUT.WINDOW_PADDING, cursor:Y())
    frame:SetSize(520, 10)
    self:AddControl(frame)

    local refreshBtn = self:AcquireWidget("QueueDiagnosticsRefresh", parent, "UIPanelButtonTemplate", "Button")
    refreshBtn:SetSize(78, 20)
    refreshBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", LAYOUT.WINDOW_PADDING + 360, cursor:Y() - 2)
    refreshBtn:SetText("Refresh")
    self:AddControl(refreshBtn)

    local rows = {
        { label = "Active",           key = "active" },
        { label = "Policy",           key = "policyClass" },
        { label = "Chat Type",        key = "chatType" },
        { label = "Expected Ack",     key = "expectedAckEvent" },
        { label = "Pending Chunks",   key = "pending" },
        { label = "In Flight",        key = "inFlight" },
        { label = "Needs Continue",   key = "needsContinue" },
        { label = "Strict Ack Match", key = "strictAck" },
    }

    local rowHeight = self:ScaledRow(22)
    local rowY = 0

    for _, row in ipairs(rows) do
        local labelFs = self:AcquireWidget("QueueDiagLabel", frame, "GameFontHighlightSmall", "FontString")
        labelFs:SetFontObject("GameFontHighlightSmall")
        labelFs:SetTextColor(0.85, 0.85, 0.85, 1)
        labelFs:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -rowY)
        labelFs:SetText(row.label .. ":")
        self:AddControl(labelFs)

        local valueFs = self:AcquireWidget("QueueDiagValue", frame, "GameFontHighlightSmall", "FontString")
        valueFs:SetFontObject("GameFontHighlightSmall")
        valueFs:SetTextColor(1, 1, 1, 1)
        valueFs:SetPoint("TOPLEFT", frame, "TOPLEFT", 200, -rowY)
        valueFs:SetText("-")
        self:AddControl(valueFs)

        row._value = valueFs
        rowY = rowY + rowHeight
    end

    frame._yDiagRows = rows
    frame._yNextUpdate = 0

    local function formatValue(value)
        if value == nil then return "-" end
        if type(value) == "boolean" then
            return value and "Yes" or "No"
        end
        return tostring(value)
    end

    local function RefreshQueueDiagnostics(selfFrame)
        local q = YapperTable.Queue
        local snapshot = q and q.GetActivePolicySnapshot and q:GetActivePolicySnapshot() or {}

        for _, row in ipairs(selfFrame._yDiagRows) do
            local value = nil
            if row.key == "needsContinue" then
                value = q and q.NeedsContinue or false
            elseif row.key == "strictAck" then
                value = q and q.StrictAckMatching or false
            else
                value = snapshot[row.key]
            end
            row._value:SetText(formatValue(value))
        end
    end

    refreshBtn:SetScript("OnClick", function()
        RefreshQueueDiagnostics(frame)
    end)

    frame:SetScript("OnUpdate", function(selfFrame, elapsed)
        if Interface.IsVisible ~= true or Interface._activeCategory ~= "diagnostics" then
            return
        end

        selfFrame._yNextUpdate = (selfFrame._yNextUpdate or 0) - elapsed
        if selfFrame._yNextUpdate > 0 then return end
        selfFrame._yNextUpdate = 0.2
        RefreshQueueDiagnostics(selfFrame)
    end)

    cursor:Advance(rowY)
    cursor:Pad(10)
end

function Interface:CreateTutorialPage(parent, cursor)
    local P = LAYOUT
    local W = 520  -- content width

    local function heading(text)
        local fs = self:AcquireWidget("TutHead", parent, "GameFontNormalLarge", "FontString")
        fs:SetFontObject("GameFontNormalLarge")
        fs:SetTextColor(0.9, 0.75, 0.2, 1)
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", P.WINDOW_PADDING, cursor:Y())
        fs:SetWidth(W)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:SetText(text)
        self:AddControl(fs)
        cursor:Advance(self:ScaledRow(20))
    end

    local function body(text)
        local fs = self:AcquireWidget("TutBody", parent, "GameFontHighlightSmall", "FontString")
        fs:SetFontObject("GameFontHighlightSmall")
        fs:SetTextColor(0.85, 0.85, 0.85, 1)
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", P.WINDOW_PADDING, cursor:Y())
        fs:SetWidth(W)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        fs:SetText(text)
        self:AddControl(fs)
        local h = math.max(fs:GetStringHeight(), 14)
        cursor:Advance(self:ScaledRow(h + 4))
    end

    local function key(k)
        return "|cFFFFD700" .. k .. "|r"
    end

    local function sep()
        cursor:Pad(8)
        -- Use a poolable Frame as a 1px-high separator so it gets hidden by
        -- ClearConfigControls when switching pages.  A bare CreateTexture
        -- call produces a permanent child that can never be hidden/pooled.
        local f = self:AcquireWidget("TutSep", parent, nil, "Frame")
        f:SetSize(W, 1)
        f:SetPoint("TOPLEFT", parent, "TOPLEFT", P.WINDOW_PADDING, cursor:Y())
        local tex = f._sepTex
        if not tex then
            tex = f:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints(f)
            f._sepTex = tex
        end
        tex:SetColorTexture(0.4, 0.4, 0.4, 0.4)
        tex:Show()
        self:AddControl(f)
        cursor:Advance(self:ScaledRow(10))
    end

    -- ── Title ──────────────────────────────────────────────────────────────
    self:CreateLabel(parent, "How to use Yapper", P.WINDOW_PADDING, cursor:Y(), W,
        "A quick reference for Yapper's chat features.", "GameFontNormal")
    cursor:Advance(self:ScaledRow(P.ROW_SECTION))

    -- ── Basic typing ───────────────────────────────────────────────────────
    heading("Basic Typing")
    body("Open chat with " .. key("Enter") .. " as normal. Yapper replaces Blizzard's input box "
      .. "with its own overlay. Type your message and press " .. key("Enter") .. " to send "
      .. "or " .. key("Escape") .. " to close.")

    sep()

    -- ── Channel switching ──────────────────────────────────────────────────
    heading("Switching Channels")
    body(key("Tab") .. "  — cycle forward through available channels (Say → Party → Raid → Guild …).")
    body(key("Shift+Tab") .. "  — open spell-check suggestions for the word under the cursor "
      .. "(or cycle channels backwards when no suggestion popup is open).")
    body("You can also type a slash command directly: " .. key("/p") .. ", " .. key("/r") .. ", "
      .. key("/g") .. ", " .. key("/w Name") .. ", etc.")
    body("The last channel you used is remembered and restored on the next open "
      .. "(configurable in General settings).")

    sep()

    -- ── Autocomplete ───────────────────────────────────────────────────────
    heading("Autocomplete")
    body("As you type, Yapper shows a greyed-out ghost word after the cursor.")
    body(key("Tab") .. "  — accept the suggestion and move on. A space is appended automatically.")
    body("Just keep typing to ignore the suggestion. If you repeatedly type a different word "
      .. "Yapper learns your preference and adjusts future suggestions.")

    sep()

    -- ── Spellcheck ─────────────────────────────────────────────────────────
    heading("Spellcheck")
    body("Misspelled words are underlined. Press " .. key("Shift+Tab") .. " to open a "
      .. "suggestion popup for the word under the cursor.")
    body("Use the " .. key("number keys") .. " or " .. key("arrow keys") .. " to pick a "
      .. "suggestion and press " .. key("Enter") .. " to apply it.")
    body("Press " .. key("Escape") .. " to close the popup without changing the word.")
    body("Words you send repeatedly despite the underline are automatically added to your "
      .. "personal dictionary after a few uses.")

    sep()

    -- ── Multiline / Storyteller ────────────────────────────────────────────
    heading("Multiline Editor (Storyteller)")
    body("When your text grows long enough, Yapper automatically opens the multiline editor. "
      .. "You can also open it manually with Shift+Enter from the single-line overlay.")
    body(key("Enter") .. " — send the entire post.")
    body(key("Shift+Enter") .. " — insert a line break. A blank line creates a paragraph break; "
      .. "each paragraph is sent as a separate chat message.")
    body(key("Escape") .. " — cancel and return to the single-line overlay. Your draft is "
      .. "preserved so you can continue editing.")
    body(key("Tab") .. " — accept autocomplete   |   " .. key("Shift+Tab") .. " — spellcheck suggestions.")
    body("If the game crashes mid-edit your draft is automatically restored the next time "
      .. "you open the chat box.")

    sep()

    -- ── Draft recovery ─────────────────────────────────────────────────────
    heading("Crash-safe Drafts")
    body("Yapper saves your in-progress message every few keystrokes. "
      .. "After a crash or /reload, the draft is automatically restored "
      .. "when you open the chat box, exactly as you left it — including the channel and, "
      .. "for multiline posts, hard line-breaks.")

    sep()

    -- ── Undo / redo ────────────────────────────────────────────────────────
    heading("Undo / Redo")
    body(key("Ctrl+Z") .. " — undo the last change.")
    body(key("Ctrl+Y") .. " — redo.")
    body("Snapshots are taken at word boundaries so a single undo steps back one whole word "
      .. "at a time rather than one character.")

    sep()

    -- ── Slash commands ─────────────────────────────────────────────────────
    heading("Slash Commands")
    body(key("/yapper") .. "  or  " .. key("/yapper toggle") .. "  — open / close settings.")
    body(key("/yapper help") .. "  or  " .. key("/yapper ?") .. "  — open this page directly.")
    body(key("/yapper open") .. "  — show settings.")
    body(key("/yapper close") .. "  — hide settings.")
    body("Right-click the minimap or toolbar icon to jump straight to this Help page.")

    cursor:Pad(10)
end

function Interface:CreateCreditsPage(parent, cursor)
    self:CreateLabel(
        parent,
        "Credits",
        LAYOUT.WINDOW_PADDING,
        cursor:Y(),
        500,
        "Things used by Yapper and their licenses.",
        "GameFontNormal"
    )
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_SECTION))

    self:CreateLabel(
        parent,
        "Spellcheck Dictionaries",
        LAYOUT.WINDOW_PADDING,
        cursor:Y(),
        500,
        "Spellcheck wordlists are derived from Hunspell dictionaries.",
        "GameFontNormal"
    )
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_SECTION))

    local function addLine(text)
        local fs = self:AcquireWidget("CreditsLine", parent, "GameFontHighlightSmall", "FontString")
        fs:SetFontObject("GameFontHighlightSmall")
        fs:SetTextColor(0.9, 0.9, 0.9, 1)
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", LAYOUT.WINDOW_PADDING, cursor:Y())
        fs:SetWidth(520)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        fs:SetText(text)
        self:AddControl(fs)
        cursor:Advance(self:ScaledRow(18))
    end

    addLine("Source: https://github.com/wooorm/dictionaries")
    addLine("Each dictionary retains its original license. See dictionaries/<code>/license in the source repo.")
    cursor:Pad(6)

    addLine("Bundled dictionaries:")
    for _, entry in ipairs(CREDITS_DICTIONARIES_BUNDLED) do
        addLine(string_format(
            "%s (%s) - %s - %s",
            entry.locale,
            entry.label,
            entry.package,
            entry.license
        ))
    end

    cursor:Pad(6)
    addLine("Optional dictionary addons:")
    addLine("Install the locale addon to enable it in Yapper settings.")
    addLine("Addon naming: Yapper_Dict_<locale> (example: Yapper_Dict_frFR).")
    for _, entry in ipairs(CREDITS_DICTIONARIES_OPTIONAL) do
        addLine(string_format(
            "%s (%s) - %s - %s",
            entry.locale,
            entry.label,
            entry.package,
            entry.license
        ))
    end

    cursor:Pad(10)
end

function Interface:CreateSpellcheckLocaleDropdown(parent, label, path, cursor)
    local y = cursor:Y()
    self:CreateLabel(parent, label, LAYOUT.LABEL_X, y - 2, LAYOUT.LABEL_WIDTH, self:GetTooltip(JoinPath(path)))

    local dd = self:AcquireWidget("Dropdown", parent, "UIDropDownMenuTemplate", "Frame")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 165, y - 4)
    UIDropDownMenu_SetWidth(dd, 180)

    local spell = YapperTable and YapperTable.Spellcheck
    local current = self:GetConfigPath(path)
    local wasUnset = false
    if not current or current == "" then
        wasUnset = true
        if spell and spell.GetLocale then
            current = spell:GetLocale()
        else
            current = (GetLocale and GetLocale()) or "enUS"
        end
    end
    -- If this is the first run (user hasn't chosen a locale), persist the chosen default.
    if wasUnset then
        self:SetLocalPath(path, current)
    end
    UIDropDownMenu_SetText(dd, tostring(current))

    UIDropDownMenu_Initialize(dd, function(frame, level)
        local locales = { "enUS", "enGB" }
        local spell = YapperTable and YapperTable.Spellcheck
        for _, locale in ipairs(locales) do
            local info = UIDropDownMenu_CreateInfo()
            local available = spell and spell.IsLocaleAvailable and spell:IsLocaleAvailable(locale)
            local canLoad = spell and spell.CanLoadLocale and spell:CanLoadLocale(locale)
            local labelText = locale

            if not available then
                if canLoad then
                    labelText = locale .. " (load addon)"
                else
                    labelText = locale .. " (addon missing)"
                end
            end

            info.text = labelText
            info.checked = (locale == current)
            info.disabled = (not available and not canLoad)
            info.func = function()
                if spell and spell.ApplyState then
                    if not spell:ApplyState(spell:IsEnabled(), locale) then
                        if spell.Notify then
                            if spell.HasLocaleAddon and spell:HasLocaleAddon(locale) then
                                spell:Notify("Yapper: failed to load " ..
                                    (spell:GetLocaleAddon(locale) or "") .. " for " .. locale .. ".")
                            else
                                spell:Notify("Yapper: install the " ..
                                    (spell:GetLocaleAddon(locale) or "") .. " addon to use " .. locale .. ".")
                            end
                        end
                        return
                    end
                end
                current = locale
                Interface:SetLocalPath(path, locale)
                UIDropDownMenu_SetText(frame, locale)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local resetBtn = Interface:CreateResetButton(parent, LAYOUT.RESET_X, y - 4, function()
        local d = Interface:GetDefaultPath(path)
        current = d
        Interface:SetLocalPath(path, d)
        UIDropDownMenu_SetText(dd, d)
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
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_TEXT_INPUT))
    return dd
end

function Interface:CreateSpellcheckKeyboardLayoutDropdown(parent, label, path, cursor)
    local y = cursor:Y()
    self:CreateLabel(parent, label, LAYOUT.LABEL_X, y - 2, LAYOUT.LABEL_WIDTH, self:GetTooltip(JoinPath(path)))

    local dd = self:AcquireWidget("Dropdown", parent, "UIDropDownMenuTemplate", "Frame")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 165, y - 4)
    UIDropDownMenu_SetWidth(dd, 180)

    local current = self:GetConfigPath(path) or "QWERTY"
    UIDropDownMenu_SetText(dd, current)

    UIDropDownMenu_Initialize(dd, function(frame, level)
        local layouts = { "QWERTY", "QWERTZ", "AZERTY" }
        for _, layout in ipairs(layouts) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = layout
            info.checked = (layout == current)
            info.func = function()
                current = layout
                Interface:SetLocalPath(path, layout)
                UIDropDownMenu_SetText(frame, layout)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local resetBtn = Interface:CreateResetButton(parent, LAYOUT.RESET_X, y - 4, function()
        local d = Interface:GetDefaultPath(path)
        current = d
        Interface:SetLocalPath(path, d)
        UIDropDownMenu_SetText(dd, d)
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
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_TEXT_INPUT))
    return dd
end

function Interface:CreateSpellcheckUnderlineDropdown(parent, label, path, cursor)
    local y = cursor:Y()
    self:CreateLabel(parent, label, LAYOUT.LABEL_X, y - 2, LAYOUT.LABEL_WIDTH, self:GetTooltip(JoinPath(path)))

    local dd = self:AcquireWidget("Dropdown", parent, "UIDropDownMenuTemplate", "Frame")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 165, y - 4)
    UIDropDownMenu_SetWidth(dd, 180)

    local current = self:GetConfigPath(path)
    if current ~= "highlight" then
        current = "line"
    end

    local function labelFor(value)
        if value == "highlight" then
            return "Highlight"
        end
        return "Underline"
    end

    UIDropDownMenu_SetText(dd, labelFor(current))

    UIDropDownMenu_Initialize(dd, function(frame, level)
        local options = {
            { value = "line",      label = "Underline" },
            { value = "highlight", label = "Highlight" },
        }

        for _, option in ipairs(options) do
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
        current = d
        Interface:SetLocalPath(path, d)
        UIDropDownMenu_SetText(dd, labelFor(d))
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
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_TEXT_INPUT))
    return dd
end

function Interface:CreateSpellcheckUserDictEditor(parent, cursor)
    local spell = YapperTable and YapperTable.Spellcheck
    if not spell then return end

    cursor:Pad(10)
    self:CreateLabel(
        parent,
        "Spellcheck User Dictionary",
        LAYOUT.WINDOW_PADDING,
        cursor:Y(),
        520,
        "Edit added and ignored words per dictionary locale.",
        "GameFontNormal"
    )
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_SECTION))

    local y = cursor:Y()
    self:CreateLabel(parent, "Dictionary to edit", LAYOUT.LABEL_X, y - 2, LAYOUT.LABEL_WIDTH)

    local dd = self:AcquireWidget("Dropdown", parent, "UIDropDownMenuTemplate", "Frame")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 165, y - 4)
    UIDropDownMenu_SetWidth(dd, 180)

    local current = self._spellcheckUserDictLocale
    if not current or current == "" then
        current = (spell.GetLocale and spell:GetLocale()) or (GetLocale and GetLocale()) or "enUS"
    end
    self._spellcheckUserDictLocale = current
    UIDropDownMenu_SetText(dd, tostring(current))

    local function TextToList(text)
        local out = {}
        for line in (text or ""):gmatch("[^\r\n]+") do
            local word = TrimString(line)
            if word ~= "" then
                out[#out + 1] = word
            end
        end
        return out
    end

    local function ListToText(list)
        if not list or #list == 0 then return "" end
        return table_concat(list, "\n")
    end

    local function RefreshEditors()
        local locale = self._spellcheckUserDictLocale
        local dict = spell.GetUserDict and spell:GetUserDict(locale) or nil
        local added = dict and dict.AddedWords or {}
        local ignored = dict and dict.IgnoredWords or {}
        if self._spellcheckUserDictAddedEdit then
            self._spellcheckUserDictAddedEdit:SetText(ListToText(added))
        end
        if self._spellcheckUserDictIgnoredEdit then
            self._spellcheckUserDictIgnoredEdit:SetText(ListToText(ignored))
        end
    end

    UIDropDownMenu_Initialize(dd, function(frame, level)
        local locales = {}
        if spell.GetKnownLocales then
            locales = spell:GetKnownLocales()
        elseif spell.GetAvailableLocales then
            locales = spell:GetAvailableLocales()
        end
        if #locales == 0 then
            locales = { current }
        end

        for _, locale in ipairs(locales) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = tostring(locale)
            info.checked = (locale == current)
            info.func = function()
                current = locale
                self._spellcheckUserDictLocale = locale
                UIDropDownMenu_SetText(frame, locale)
                RefreshEditors()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    self:AddControl(dd)
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_TEXT_INPUT))

    local function CreateMultiLineBox(labelText)
        local labelY = cursor:Y()
        self:CreateLabel(parent, labelText, LAYOUT.LABEL_X, labelY - 2, LAYOUT.LABEL_WIDTH)

        local sf = self:AcquireWidget("SpellcheckUserDictScroll", parent, "InputScrollFrameTemplate", "ScrollFrame")
        sf:SetPoint("TOPLEFT", parent, "TOPLEFT", LAYOUT.CONTROL_X, labelY)
        sf:SetSize(300, 110)
        sf:SetClipsChildren(true)
        local edit = sf.EditBox
        if edit then
            edit:SetAutoFocus(false)
            edit:SetMultiLine(true)
            edit:SetMaxLetters(0)
            edit:SetFontObject(GameFontHighlightSmall)
            edit:SetWidth(sf:GetWidth() - 20)
            edit:SetScript("OnEscapePressed", function(selfFrame)
                selfFrame:ClearFocus()
            end)
        end

        self:AddControl(sf)
        if edit then
            edit.widgetType = "SpellcheckUserDictEdit"
            self:AddControl(edit)
        end
        cursor:Advance(120)
        return edit
    end

    local addedEdit = CreateMultiLineBox("Added words (one per line)")
    self._spellcheckUserDictAddedEdit = addedEdit
    local ignoredEdit = CreateMultiLineBox("Ignored words (one per line)")
    self._spellcheckUserDictIgnoredEdit = ignoredEdit

    local function commit(editBox, kind)
        local locale = self._spellcheckUserDictLocale
        local dict = spell.GetUserDict and spell:GetUserDict(locale) or nil
        if not dict then return end
        local list = TextToList(editBox and editBox:GetText() or "")
        if kind == "added" then
            dict.AddedWords = list
        else
            dict.IgnoredWords = list
        end
        if spell.TouchUserDict then
            spell:TouchUserDict(dict)
        end

        if spell.ScheduleRefresh then
            spell:ScheduleRefresh()
        end
    end

    if addedEdit then
        addedEdit:SetScript("OnEditFocusLost", function(selfFrame)
            commit(selfFrame, "added")
        end)
    end
    if ignoredEdit then
        ignoredEdit:SetScript("OnEditFocusLost", function(selfFrame)
            commit(selfFrame, "ignored")
        end)
    end

    RefreshEditors()
end

function Interface:CreateThemeDropdown(parent, label, path, cursor)
    local y = cursor:Y()
    self:CreateLabel(parent, label, LAYOUT.LABEL_X, y - 2, LAYOUT.LABEL_WIDTH, self:GetTooltip(JoinPath(path)))

    local dd = self:AcquireWidget("Dropdown", parent, "UIDropDownMenuTemplate", "Frame")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 165, y - 4)
    UIDropDownMenu_SetWidth(dd, 180)

    local current = self:GetConfigPath(path) or (YapperTable.Theme and YapperTable.Theme._current)
    UIDropDownMenu_SetText(dd, tostring(current or "Default"))

    UIDropDownMenu_Initialize(dd, function(frame, level)
        local names = {}
        if YapperTable and YapperTable.GetRegisteredThemes then
            names = YapperTable:GetRegisteredThemes()
        elseif YapperTable and YapperTable.Theme and YapperTable.Theme.GetRegisteredNames then
            names = YapperTable.Theme:GetRegisteredNames()
        end

        -- Ensure there's at least the default entry.
        if #names == 0 then names = { "Yapper Default" } end

        for _, name in ipairs(names) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.checked = (name == current)
            info.func = function()
                current = name
                Interface:SetLocalPath(path, name)
                pcall(function()
                    if YapperTable and YapperTable.Utils and YapperTable.Utils.VerbosePrint then
                        YapperTable.Utils:VerbosePrint("Interface: theme selected -> " .. tostring(name))
                    end
                end)
                UIDropDownMenu_SetText(frame, name)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    self:AddControl(dd)
    cursor:Advance(self:ScaledRow(LAYOUT.ROW_TEXT_INPUT))
    return dd
end
