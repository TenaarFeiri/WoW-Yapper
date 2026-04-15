--[[
    User interface for configuration options.
]]

local YapperName, YapperTable = ...
local Interface               = {}
YapperTable.Interface         = Interface
Interface.MouseWheelStepRate  = YapperTable.Config.FrameSettings.MouseWheelStepRate or 30
Interface.IsVisible           = false

-- Localise Lua globals for performance
local math_floor              = math.floor
local math_rad                = math.rad
local math_cos                = math.cos
local math_sin                = math.sin
local math_deg                = math.deg
local math_atan2              = math.atan2 or math.atan
local math_max                = math.max
local math_min                = math.min
local math_abs                = math.abs
local string_upper            = string.upper
local string_format           = string.format
local table_concat            = table.concat
local table_sort              = table.sort
local type                    = type
local pairs                   = pairs
local ipairs                  = ipairs
local tostring                = tostring
local tonumber                = tonumber
local select                  = select
local tinsert                 = table.insert

-- ---------------------------------------------------------------------------
-- StaticPopups
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------------
local LAYOUT             = {
    -- Main window
    WINDOW_WIDTH           = 740,
    WINDOW_HEIGHT          = 640,
    WINDOW_PADDING         = 8,
    SCROLLBAR_WIDTH        = 14,
    SCROLLBAR_GAP          = 2,
    TITLE_INSET            = 28,
    BOTTOM_BAR             = 36,

    -- Sidebar
    SIDEBAR_WIDTH          = 150,
    SIDEBAR_BTN_HEIGHT     = 28,
    SIDEBAR_BTN_PAD        = 2,
    SIDEBAR_TOP_INSET      = 32,

    -- Widget row heights (generous spacing for readability)
    ROW_CHECKBOX           = 36,
    ROW_TEXT_INPUT         = 36,
    ROW_COLOR_PICKER       = 36,
    ROW_FONT_OUTLINE       = 36,
    ROW_FONT_SIZE          = 90,
    ROW_SECTION            = 28,
    ROW_CHANNEL_ROW        = 28,
    ROW_CHANNEL_HEADER     = 24,
    ROW_CHANNEL_LABELS     = 18,

    -- Starting Y for dynamic content (pushed below the autosave notice)
    CONTENT_START_Y        = -28,

    -- Horizontal positions (wider labels to avoid word-wrap in 740px window)
    LABEL_X                = 10,
    LABEL_WIDTH            = 300,
    CONTROL_X              = 320,
    RESET_X                = 500,

    -- Close button
    CLOSE_BTN_WIDTH        = 120,
    CLOSE_BTN_HEIGHT       = 24,
    CLOSE_BTN_OFFSET_Y     = 10,

    -- Scrollbar fixed offsets
    SCROLLBAR_TOP_INSET    = 48,
    SCROLLBAR_BOTTOM_INSET = 44,
}

-- Even-increment offsets from the Blizzard base size (used by sidebar +/–).
local UI_FONT_STEP       = 2
local UI_FONT_MIN_OFFSET = -4 -- smallest allowed offset (8 pt at base 12)
local UI_FONT_MAX_OFFSET = 8  -- largest  allowed offset (20 pt at base 12)

-- ---------------------------------------------------------------------------
-- LayoutCursor... replaces manual `y = y - N` tracking.
-- ---------------------------------------------------------------------------
local LayoutCursor       = {}
LayoutCursor.__index     = LayoutCursor

---@param startY number?
---@return table
function LayoutCursor.New(startY)
    return setmetatable({ _y = startY or 0 }, LayoutCursor)
end

function LayoutCursor:Y()
    return self._y
end

function LayoutCursor:Advance(amount)
    self._y = self._y - (amount or 0)
    return self._y
end

function LayoutCursor:Pad(px)
    return self:Advance(px or 4)
end

-- Export layout and cursor for sub-files.
Interface._LAYOUT           = LAYOUT
Interface._LayoutCursor     = LayoutCursor
Interface._UI_FONT_STEP     = UI_FONT_STEP
Interface._UI_FONT_MIN_OFFSET = UI_FONT_MIN_OFFSET
Interface._UI_FONT_MAX_OFFSET = UI_FONT_MAX_OFFSET

-- ---------------------------------------------------------------------------
-- Utility helpers (exported on Interface for sub-files to re-localise)
-- ---------------------------------------------------------------------------
local function IsColourTable(tbl)
    return type(tbl) == "table"
        and type(tbl.r) == "number"
        and type(tbl.g) == "number"
        and type(tbl.b) == "number"
end

-- Copy a colour table safely, supplying sane defaults.
local function CopyColour(tbl)
    return {
        r = tbl.r or 1,
        g = tbl.g or 1,
        b = tbl.b or 1,
        a = tbl.a ~= nil and tbl.a or 1,
    }
end

-- Convert a path array into "A.B.C" form for lookup keys.
local function JoinPath(path)
    return table_concat(path, ".")
end

-- Copy a path array so render walkers can mutate independently.
local function ClonePath(path)
    local out = {}
    for i = 1, #path do out[i] = path[i] end
    return out
end

-- Trim user text input for normalisation workflows.
local function TrimString(s)
    s = tostring(s or "")
    return (s:match("^%s*(.-)%s*$") or "")
end

-- Clamp numbers into [0,1], with a fallback when value is invalid.
local function Clamp01(value, fallback)
    if type(value) ~= "number" then
        return fallback
    end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

-- Force font size to valid even values in our supported range.
local function RoundToEven(value)
    value = tonumber(value) or 14
    value = math_floor(value + 0.5)
    if value % 2 ~= 0 then
        value = value + 1
    end
    if value < 8 then value = 8 end
    if value > 64 then value = 64 end
    return value
end

-- Normalise legacy/variant font flag values into known dropdown options.
local function NormalizeFontFlags(value)
    if type(value) ~= "string" then return "" end
    local flags = string_upper(TrimString(value))
    if flags == "" or flags == "NONE" then
        return ""
    end

    local FONT_OUTLINE_OPTIONS = Interface._FONT_OUTLINE_OPTIONS or {}
    for _, option in ipairs(FONT_OUTLINE_OPTIONS) do
        if option.value == flags then
            return option.value
        end
    end

    return ""
end

-- Resolve a font flag value to display text.
local function GetFontFlagsLabel(flags)
    local FONT_OUTLINE_OPTIONS = Interface._FONT_OUTLINE_OPTIONS or {}
    for _, option in ipairs(FONT_OUTLINE_OPTIONS) do
        if option.value == flags then
            return option.label
        end
    end
    return (FONT_OUTLINE_OPTIONS[1] or {}).label
end

-- Traverse nested tables using a key path.
local function GetPathValue(root, path)
    local cursor = root
    for i = 1, #path do
        if type(cursor) ~= "table" then return nil end
        cursor = cursor[path[i]]
    end
    return cursor
end

-- Write into nested tables, creating missing parents as needed.
local function SetPathValue(root, path, value)
    if type(root) ~= "table" then return end
    local cursor = root
    for i = 1, #path - 1 do
        local key = path[i]
        if type(cursor[key]) ~= "table" then
            cursor[key] = {}
        end
        cursor = cursor[key]
    end
    cursor[path[#path]] = value
end

-- Keep split marker settings visually consistent while user edits either side.
local function NormalizeChatMarkers(path, value)
    if #path ~= 2 or path[1] ~= "Chat" or type(value) ~= "string" then
        return value
    end

    local trimmed = TrimString(value)
    if trimmed == "" then
        -- Empty marker means: no delineator / no prefix.
        return ""
    end

    if path[2] == "DELINEATOR" then
        return " " .. trimmed
    elseif path[2] == "PREFIX" then
        return trimmed .. " "
    end

    return value
end

-- Remove local keys that no longer exist in defaults.
local function PruneUnknown(localTbl, defaultTbl)
    if type(localTbl) ~= "table" or type(defaultTbl) ~= "table" then return end

    for key, value in pairs(localTbl) do
        local defValue = defaultTbl[key]
        if defValue == nil then
            localTbl[key] = nil
        elseif type(value) == "table" and type(defValue) == "table" then
            PruneUnknown(value, defValue)
        elseif type(value) == "table" and type(defValue) ~= "table" then
            localTbl[key] = nil
        end
    end
end

-- Restrict restored frame anchors to known safe point names.
local function IsAnchorPoint(value)
    return value == "TOP"
        or value == "BOTTOM"
        or value == "LEFT"
        or value == "RIGHT"
        or value == "CENTER"
        or value == "TOPLEFT"
        or value == "TOPRIGHT"
        or value == "BOTTOMLEFT"
        or value == "BOTTOMRIGHT"
end

-- Export utilities for sub-files.
Interface.IsColourTable       = IsColourTable
Interface.CopyColour          = CopyColour
Interface.JoinPath            = JoinPath
Interface.ClonePath           = ClonePath
Interface.TrimString          = TrimString
Interface.Clamp01             = Clamp01
Interface.RoundToEven         = RoundToEven
Interface.NormalizeFontFlags  = NormalizeFontFlags
Interface.GetFontFlagsLabel   = GetFontFlagsLabel
Interface.GetPathValue        = GetPathValue
Interface.SetPathValue        = SetPathValue
Interface.NormalizeChatMarkers = NormalizeChatMarkers
Interface.PruneUnknown        = PruneUnknown
Interface.IsAnchorPoint       = IsAnchorPoint

-- ---------------------------------------------------------------------------
-- StaticPopups
-- ---------------------------------------------------------------------------
function Interface:InitPopups()
    if not StaticPopupDialogs["YAPPER_CONFIRM_RESET_LEARNING"] then
        StaticPopupDialogs["YAPPER_CONFIRM_RESET_LEARNING"] = {
            text =
            "Are you sure you want to permanently erase all learned typing patterns, bias corrections, and word frequencies?",
            button1 = "Yes, Reset",
            button2 = "Cancel",
            OnAccept = function()
                local yallm = YapperTable and YapperTable.Spellcheck and YapperTable.Spellcheck.YALLM
                if yallm and yallm.Reset then
                    yallm:Reset()
                    Interface:BuildConfigUI() -- Refresh
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
    end

    if not StaticPopupDialogs["YAPPER_CONFIRM_DICTIONARY_PURGE"] then
        StaticPopupDialogs["YAPPER_CONFIRM_DICTIONARY_PURGE"] = {
            text =
            "Spellchecker disabled. Would you like to immediately purge the dictionary from memory (causes a brief stutter) or wait for natural collection?",
            button1 = "Purge Now",
            button2 = "Wait (No Stutter)",
            OnAccept = function()
                if YapperTable.Spellcheck and YapperTable.Spellcheck.UnloadAllDictionaries then
                    YapperTable.Spellcheck:UnloadAllDictionaries(true)
                end
            end,
            OnCancel = function()
                if YapperTable.Spellcheck and YapperTable.Spellcheck.UnloadAllDictionaries then
                    YapperTable.Spellcheck:UnloadAllDictionaries(false)
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
    end

    if not StaticPopupDialogs["YAPPER_RESET_CONFIRM"] then
        StaticPopupDialogs["YAPPER_RESET_CONFIRM"] = {
            text =
            "Are you sure you want to restore all settings to their default values?  This will not affect your learned dictionary data or history.",
            button1 = "Yes, Reset Everything",
            button2 = "Cancel",
            OnAccept = function()
                Interface:ResetAllSettings()
                Interface:BuildConfigUI()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
    end

    if not StaticPopupDialogs["YAPPER_YALLM_RESET_CONFIRM"] then
        StaticPopupDialogs["YAPPER_YALLM_RESET_CONFIRM"] = {
            text = "Reset all YALLM adaptive learning data? This will clear your vocabulary trends and bias history.",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                local yallm = YapperTable and YapperTable.Spellcheck and YapperTable.Spellcheck.YALLM
                if yallm and yallm.Reset then
                    yallm:Reset()
                    if Interface.MainWindowFrame and Interface.MainWindowFrame:IsShown() then
                        Interface:RefreshActivePage()
                    end
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
    end

    if not StaticPopupDialogs["YAPPER_RPPREFIX_LOCKDOWN_WARNING"] then
        StaticPopupDialogs["YAPPER_RPPREFIX_LOCKDOWN_WARNING"] = {
            text = "|cFFFF6600Warning: RP Prefix detected|r\n\nRP Prefix works by replacing a protected Blizzard API with addon Lua code, which taints it. This will prevent you from being able to send chat messages entirely during combat lockdown — boss fights, Mythic+, PvP, and any other protected environment.\n\nYou can dismiss this warning and continue using both addons, or unload RP Prefix now.",
            button1 = "Confirm",
            button2 = "Unload RP Prefix",
            OnAccept = function()
                if type(_G.YapperDB) == "table" then
                    _G.YapperDB.RPPrefixWarningAcknowledged = true
                end
            end,
            OnCancel = function()
                if C_AddOns and C_AddOns.DisableAddOn then
                    C_AddOns.DisableAddOn("RPPrefix")
                elseif DisableAddOn then
                    DisableAddOn("RPPrefix")
                end
                ReloadUI()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = false,
        }
    end
end

-- ---------------------------------------------------------------------------
-- BuildConfigUI — master renderer
-- (CATEGORIES and FRIENDLY_LABELS are loaded by Schema.lua after this file
--  but used at runtime, so read from the module table.)
-- ---------------------------------------------------------------------------
function Interface:BuildConfigUI()
    local CATEGORIES     = Interface._CATEGORIES
    local FRIENDLY_LABELS = Interface._FRIENDLY_LABELS
    local frame = self.MainWindowFrame
    if not frame or not frame.ContentFrame then return end

    self:ClearConfigControls()

    -- Reset scroll position when rebuilding (e.g. category switch).
    if frame.ScrollFrame then
        frame.ScrollFrame:SetVerticalScroll(0)
        if frame.ScrollFrame.ScrollBar then
            frame.ScrollFrame.ScrollBar:SetValue(0)
        end
    end

    local schema    = self:GetRenderSchema()
    local catId     = self._activeCategory or "general"
    local activeCat = nil
    for _, c in ipairs(CATEGORIES) do
        if c.id == catId then
            activeCat = c; break
        end
    end
    if not activeCat then activeCat = CATEGORIES[1] end

    -- Build a set of paths owned by this category for fast lookup.
    local catPaths = {}
    if activeCat.paths then
        for _, p in ipairs(activeCat.paths) do
            catPaths[p] = true
        end
    end

    -- Custom flags for conditional blocks.
    local customSet = {}
    if activeCat.custom then
        for _, c in ipairs(activeCat.custom) do
            customSet[c] = true
        end
    end

    -- Small autosave hint at the top of every page.
    local autosaveLabel = self:CreateLabel(
        frame.ContentFrame,
        "Settings are saved automatically.",
        LAYOUT.WINDOW_PADDING,
        -6,
        500,
        self:GetTooltip("HEADER.AUTOSAVE")
    )
    autosaveLabel:SetFontObject(GameFontHighlightSmall)

    -- Dynamic content begins below the fixed header area.
    -- Push further down when font is scaled up so the autosave label has room.
    local cursor = LayoutCursor.New(LAYOUT.CONTENT_START_Y - self:GetUIFontOffset())

    -- Render schema items that belong to this category, preserving render
    -- order but skipping anything not claimed by the active category.
    for _, item in ipairs(schema) do
        if item.kind ~= "section" and catPaths[item.full] then
            -- Verify the key actually exists in DEFAULTS so we never render
            -- a control for a removed setting.
            local existsInDefaults = self:GetDefaultsRoot()
            local defaultsCursor = existsInDefaults
            for i = 1, #item.path do
                if type(defaultsCursor) ~= "table" then
                    defaultsCursor = nil
                    break
                end
                defaultsCursor = defaultsCursor[item.path[i]]
            end

            if defaultsCursor ~= nil then
                if item.kind == "boolean" then
                    self:CreateCheckBox(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                elseif item.kind == "text" then
                    self:CreateTextInput(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                elseif item.kind == "color" then
                    self:CreateColorPickerControl(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                elseif item.kind == "fontsize" then
                    self:CreateFontSizeDropdown(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                elseif item.kind == "fontflags" then
                    self:CreateFontOutlineDropdown(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                elseif item.kind == "spellcheck_locale" then
                    self:CreateSpellcheckLocaleDropdown(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                elseif item.kind == "spellcheck_keyboard_layout" then
                    self:CreateSpellcheckKeyboardLayoutDropdown(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                elseif item.kind == "spellcheck_underline" then
                    self:CreateSpellcheckUnderlineDropdown(
                        frame.ContentFrame,
                        self:GetFriendlyLabel(item),
                        item.path,
                        cursor
                    )
                elseif item.kind == "theme" then
                    self:CreateThemeDropdown(
                        frame.ContentFrame,
                        "Active Theme",
                        item.path,
                        cursor
                    )
                end
            end
        end
    end

    ----- Custom blocks appended per-category -----

    -- Border colour: only when active theme declares a border.
    if customSet["borderColor"] then
        local activeThemeName = self:GetConfigPath({ "System", "ActiveTheme" })
            or (YapperTable.Theme and YapperTable.Theme._current)
        if activeThemeName and YapperTable and YapperTable.Theme then
            local t = YapperTable.Theme:GetTheme(activeThemeName)
            if type(t) == "table" and t.border == true then
                self:CreateColorPickerControl(
                    frame.ContentFrame,
                    "Border Colour",
                    { "EditBox", "BorderColor" },
                    cursor
                )
            end
        end
    end

    -- Channel colour overrides.
    if customSet["channelOverrides"] then
        if type(self:GetDefaultPath({ "EditBox", "ChannelColorOverrides" })) == "table" then
            self:CreateChannelOverrideControls(frame.ContentFrame, cursor)
        end
    end

    -- Queue diagnostics.
    if customSet["queueDiagnostics"] then
        self:CreateQueueDiagnostics(frame.ContentFrame, cursor)
    end

    -- Credits.
    if customSet["credits"] then
        self:CreateCreditsPage(frame.ContentFrame, cursor)
    end

    -- YALLM Learning.
    if customSet["yallmLearning"] then
        self:CreateYALLMLearningPage(frame.ContentFrame, cursor)
    end

    -- Message Bridges.
    if customSet["bridges"] then
        cursor:Pad(10)
        self:CreateLabel(
            frame.ContentFrame,
            "Message Bridges",
            LAYOUT.WINDOW_PADDING,
            cursor:Y(),
            500,
            "Enable or disable integration with third-party protocols.",
            "GameFontNormal"
        )
        cursor:Advance(self:ScaledRow(LAYOUT.ROW_SECTION))

        self:CreateCheckBox(
            frame.ContentFrame,
            FRIENDLY_LABELS["System.EnableGopherBridge"],
            { "System", "EnableGopherBridge" },
            cursor
        )

        -- Visible warning note for Gopher toggle.
        local gopherWarning = self:CreateLabel(
            frame.ContentFrame,
            "BAD IDEA: Disabling this while using Gopher-powered addons (CrossRP, etc.) will cause stalls.",
            LAYOUT.WINDOW_PADDING + 28,
            cursor:Y() + 4,
            460
        )
        gopherWarning:SetFontObject(GameFontHighlightSmall)
        gopherWarning:SetTextColor(1, 0.4, 0.4, 1) -- Light red warning colour.
        cursor:Advance(14)

        self:CreateCheckBox(
            frame.ContentFrame,
            FRIENDLY_LABELS["System.EnableTypingTrackerBridge"],
            { "System", "EnableTypingTrackerBridge" },
            cursor
        )
    end

    -- Spellcheck user dictionary editor.
    if customSet["spellcheckUserDict"] then
        self:CreateSpellcheckUserDictEditor(frame.ContentFrame, cursor)
    end


    if activeCat.id == "advanced" then
        -- Reset all Yapper data to defaults (wipes SavedVariables and reloads UI).
        cursor:Pad(10)
        self:CreateLabel(
            frame.ContentFrame,
            "Reset Yapper",
            LAYOUT.WINDOW_PADDING,
            cursor:Y(),
            520,
            "Reset all Yapper settings and wipe saved data (this will reload the UI).",
            "GameFontNormal"
        )
        cursor:Advance(self:ScaledRow(LAYOUT.ROW_SECTION))

        -- Lazy popup initialization here was causing crashes.
        -- Moved to Interface:InitPopups() called at boot.

        local resetBtn = self:AcquireWidget("ActionButton", frame.ContentFrame, "UIPanelButtonTemplate", "Button")
        resetBtn:SetSize(160, 24)
        resetBtn:SetPoint("TOPLEFT", frame.ContentFrame, "TOPLEFT", LAYOUT.WINDOW_PADDING, cursor:Y() - 28)
        resetBtn:SetText("Reset to Defaults")
        resetBtn:SetScript("OnClick", function()
            StaticPopup_Show("YAPPER_RESET_CONFIRM")
        end)
        self:AddControl(resetBtn)
        cursor:Advance(36)
    end

    cursor:Advance(0)

    -- Finish layout and size the content child so the scroll range is correct.
    cursor:Pad(20)
    frame.ContentFrame:SetHeight(math_abs(cursor:Y()) + 20)
    frame.ScrollFrame:UpdateScrollChildRect()

    -- Apply UI font scaling and refresh the sidebar size readout.
    self:RefreshFontScaleLabel()
    self:ApplyUIFontScale()
end

function Interface:ShowMainWindow()
    if not Interface.MainWindowFrame then
        Interface:Init()
    end
    Interface:ApplyMainWindowPosition(Interface.MainWindowFrame)
    Interface.MainWindowFrame:Show()
end

function Interface:ToggleMainWindow()
    if not Interface.MainWindowFrame then
        Interface:Init()
    end
    if Interface.MainWindowFrame:IsShown() then
        Interface:CloseFrame(Interface.MainWindowFrame)
    else
        Interface:ApplyMainWindowPosition(Interface.MainWindowFrame)
        Interface.MainWindowFrame:Show()
    end
end

local function NormalizeMouseButton(button)
    if type(button) == "number" then
        if button == 2 then return "RightButton" end
        if button == 1 then return "LeftButton" end
        return nil
    end

    if type(button) ~= "string" then return nil end
    local b = string.lower(button)
    if b == "rightbutton" or b == "rightbuttonup" then
        return "RightButton"
    end
    if b == "leftbutton" or b == "leftbuttonup" then
        return "LeftButton"
    end
    return nil
end

function Interface:HandleLauncherClick(mouseButton)
    NormalizeMouseButton(mouseButton)
    Interface:ToggleMainWindow()
end

function Yapper_FromCompartment(...)
    local button
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        local normalized = NormalizeMouseButton(v)
        if normalized then
            button = normalized
            break
        end
    end
    Interface:HandleLauncherClick(button)
end

function Interface:CloseFrame(frame)
    if not frame or not frame:IsObjectType("Frame") then
        YapperTable.Utils:DebugPrint("Attempted to close an undefined frame.")
        return
    end
    self:SaveMainWindowPosition(frame)
    self:OnWindowClosed()
    frame:Hide()
end

-- Instantiation --
function Interface:Init()
    Interface:SanitizeLocalConfig()
    Interface:CreateMainWindow()
    Interface:BuildConfigUI()

    -- Then we're gonna hook into Show() and Hide() to track visibility.
    hooksecurefunc(Interface.MainWindowFrame, "Show", function()
        Interface.IsVisible = true -- Set visibility to true.
    end)
    hooksecurefunc(Interface.MainWindowFrame, "Hide", function()
        Interface.IsVisible = false
        Interface:OnWindowClosed()
    end)

    -- Create the launcher (Addon Compartment preferred, LDB fallback).
    Interface:CreateLauncher()

    -- Check if we should show the welcome/theme choice popup.
    if Interface:ShouldShowWelcomeChoice() then
        Interface:CreateWelcomeChoiceFrame()
    end
end

-- Create a launcher (Addon Compartment preferred, LDB fallback)
function Interface:CreateLauncher()
    if self.LauncherCreated then return end

    local tooltipLines = self:GetLauncherTooltipLines()

    -- Add to addon compartment if exists.
    ---@diagnostic disable: undefined-global
    local compartment = AddonCompartmentFrame or AddonCompartment
    if type(compartment) == "table" and type(compartment.RegisterAddon) == "function" then
        local ok, err = pcall(function()
            compartment:RegisterAddon({
                text = YapperName,
                icon = "6624474", -- fileID icon
                registerForAnyClick = true,
                func = Yapper_FromCompartment,
                funcOnEnter = function(menuItem)
                    GameTooltip:SetOwner(menuItem, "ANCHOR_BOTTOMLEFT", -15, 20)
                    ---@diagnostic disable-next-line: missing-parameter
                    GameTooltip:SetText(YapperName)
                    GameTooltip:AddLine(" ")
                    for _, line in ipairs(tooltipLines) do
                        GameTooltip:AddLine("|cFF00FF00" .. line .. "|r")
                    end
                    GameTooltip:Show()
                end,
                funcOnLeave = function()
                    GameTooltip:Hide()
                end,
            })
        end)
        if not ok then
            -- don't fail silently
            YapperTable.Utils:DebugPrint(YapperName .. ": AddonCompartment register failed:", tostring(err))
        end
    end

    -- Minimap button implement via LibStub if available.
    local ldb = _G.LibStub and _G.LibStub("LibDataBroker-1.1", true)
    if ldb then
        if not self.MinimapLDBObject then
            self.MinimapLDBObject = ldb:NewDataObject(YapperName, {
                type = "launcher",
                icon = "6624474", -- fileID string
                OnClick = function(_, button)
                    Interface:HandleLauncherClick(button)
                end,
                OnTooltipShow = function(tt)
                    tt:AddLine(YapperName)
                    tt:AddLine(" ")
                    for _, line in ipairs(tooltipLines) do
                        tt:AddLine(line, 0.6, 0.6, 0.6)
                    end
                end,
            })
        end

        local DBIcon = _G.LibStub and _G.LibStub("LibDBIcon-1.0", true)
        if DBIcon then
            self.DBIcon = DBIcon
            local minimapCfg = self:GetMinimapButtonSettings()
            pcall(function()
                DBIcon:Register(YapperName, self.MinimapLDBObject, minimapCfg)
            end)
            self:ApplyMinimapButtonVisibility()
            self.LauncherCreated = true
            return
        end
    end

    -- Manual minimap button fallback when LibStub/DBIcon are unavailable.
    if _G.Minimap then
        if not self.MinimapButton then
            local btn = CreateFrame("Button", "YapperMinimapButton", _G.Minimap)
            btn:SetSize(31, 31)
            btn:SetFrameStrata("MEDIUM")
            btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:RegisterForDrag("LeftButton")

            local background = btn:CreateTexture(nil, "BACKGROUND")
            background:SetSize(20, 20)
            background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
            background:SetPoint("TOPLEFT", btn, "TOPLEFT", 7, -5)

            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetSize(20, 20)
            icon:SetTexture("6624474")
            icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
            icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 7, -5)

            local border = btn:CreateTexture(nil, "OVERLAY")
            border:SetSize(53, 53)
            border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
            border:SetPoint("TOPLEFT", btn, "TOPLEFT")

            btn:SetScript("OnClick", function(_, button)
                Interface:HandleLauncherClick(button)
            end)
            btn:SetScript("OnDragStart", function(selfFrame)
                selfFrame:SetScript("OnUpdate", function()
                    Interface:UpdateMinimapButtonAngleFromCursor()
                end)
            end)
            btn:SetScript("OnDragStop", function(selfFrame)
                selfFrame:SetScript("OnUpdate", nil)
            end)
            btn:SetScript("OnEnter", function(selfFrame)
                GameTooltip:SetOwner(selfFrame, "ANCHOR_TOPLEFT")
                GameTooltip:SetText(YapperName)
                GameTooltip:AddLine(" ")
                for _, line in ipairs(tooltipLines) do
                    GameTooltip:AddLine(line, 0.6, 0.6, 0.6)
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            self.MinimapButton = btn
            self:PositionMinimapButton()
        end

        self:ApplyMinimapButtonVisibility()
    end

    self.LauncherCreated = true
end

