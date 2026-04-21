--[[
    Addon-wide configuration and version info.
    Loaded first; every other module reads from YapperTable.Config.
]]

local YapperName, YapperTable = ...

YapperTable.Core = {}

-- ---------------------------------------------------------------------------
-- Centralised configuration (hardcoded defaults)
-- ---------------------------------------------------------------------------
local DEFAULTS = {
    System = {
        -- Schema version for SavedVariables migration; bump only when data structure changes.
        VERSION                   = 1.2,

        -- VERBOSE and DEBUG are largely for debugging.
        -- VERBOSE is for general debugging messages, or just declaring certain actions.
        -- DEBUG is for more detailed debugging messages.
        VERBOSE                   = false,
        DEBUG                     = false,

        -- The name we give to the parent frame. CAN be anything but...
        -- I'm not very original...
        FRAME_ID_PARENT           = "PARENT_FRAME",

        -- If settings have changed, reparse and recache our interface schema.
        ["SettingsHaveChanged"]   = false,

        -- Bridge Toggles
        EnableGopherBridge        = true,
        EnableTypingTrackerBridge = true,

        -- Default active theme name (registered by `Src/Theme.lua`).
        ActiveTheme               = "Yapper Default",

        -- Global Settings: when true, changes are saved to the account-wide YapperDB
        -- instead of character-specific YapperLocalConf.
        UseGlobalProfile          = false,

        -- Storyteller animation duration
        StorytellerSlideSpeed     = 0.3,

        -- Tracks whether the welcome/appearance-choice popup has been shown.
        -- Set to the VERSION at which it was last displayed; 0 means never.
        _welcomeShown             = 0,

        -- Tracks the addon version string last seen at login.
        -- Used to trigger the What's New frame on version bumps.
        _lastSeenVersion          = "",
    },

    -- Obviously this holds settings for our interface frames.
    -- Don't worry about these unless you know what you're doing. They're
    -- for things like scrolling and moving the window.
    ["FrameSettings"] = {
        ["MouseWheelStepRate"] = 30,
        ["UIFontOffset"] = 0,
        ["EnableMinimapButton"] = true,
        ["MinimapButtonOffset"] = 0,
        ["MainWindowPosition"] = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = 0,
        },
    },

    Chat = {

        USE_DELINEATORS   = true,

        -- Anything above the character limit gets chunked.
        CHARACTER_LIMIT   = 255,

        -- How many lines to keep in memory.
        MAX_HISTORY_LINES = 50, -- 50 by default.

        -- The delineator used to split posts.
        -- Posting system normalises this by prepending/appending a whitespace to the delineator
        -- at the end and beginning of a split post. You can always assume this to be the case.
        DELINEATOR        = "»", -- We never rename or move this specific var out of here (other addons use it)

        -- Always synced to DELINEATOR.
        PREFIX            = "»",

        -- How long to wait before giving up.
        STALL_TIMEOUT     = 1.0,
    },

    -- EditBox appearance defaults
    EditBox = {
        -- Visuals
        RoundedCorners        = false,
        Shadow                = false,
        ShadowColor           = { r = 0, g = 0, b = 0, a = 0.5 },
        ShadowSize            = 4,

        -- Input area background
        InputBg               = {
            r = 0.05, g = 0.05, b = 0.05, a = 1.0,
        },

        -- Label area background
        LabelBg               = {
            r = 0.06, g = 0.06, b = 0.06, a = 1.0,
        },

        -- Font: nil means "inherit from Blizzard editbox".
        -- Set a string like "Fonts\\FRIZQT__.TTF" to override.
        FontFace              = nil,
        FontSize              = 14,
        FontFlags             = "",   -- e.g. "OUTLINE", "THICKOUTLINE"
        AutoFitLabel          = true, -- true = shrink label font to fit, false = truncate with ellipsis

        -- Text colour (nil = white)
        TextColor             = { r = 1, g = 1, b = 1, a = 1 },
        -- Optional border colour for themes that expose a border element.
        BorderColor           = { r = 0.00, g = 0.00, b = 0.00, a = 0 },
        ChannelColorMaster    = "",
        ChannelColorOverrides = {
            SAY = false,
            YELL = false,
            PARTY = false,
            WHISPER = false,
            BN_WHISPER = false,
            CHANNEL = false,
            CLUB = false,
            INSTANCE_CHAT = false,
            RAID = false,
            RAID_WARNING = false,
        },

        ChannelTextColors     = {
            SAY = { r = 1.00, g = 1.00, b = 1.00, a = 1 },
            YELL = { r = 1.00, g = 0.25, b = 0.25, a = 1 },
            PARTY = { r = 0.67, g = 0.67, b = 1.00, a = 1 },
            WHISPER = { r = 1.00, g = 0.50, b = 1.00, a = 1 },
            BN_WHISPER = { r = 0.25, g = 0.78, b = 0.94, a = 1 },
            CHANNEL = { r = 1.00, g = 0.75, b = 0.75, a = 1 },
            CLUB = { r = 0.25, g = 0.78, b = 0.94, a = 1 },
            INSTANCE_CHAT = { r = 1.00, g = 0.50, b = 0.00, a = 1 },
            RAID = { r = 1.00, g = 0.50, b = 0.00, a = 1 },
            RAID_WARNING = { r = 1.00, g = 0.28, b = 0.03, a = 1 },
        },

        -- Vertical sizing
        MinHeight             = 0, -- minimum overlay height; only applies if larger than the native editbox height
        FontPad               = 8, -- extra pixels above + below the text baseline

        -- Tier 1 integration: keep the Blizzard editbox alive (text invisible)
        -- so its native skin/backdrop wraps the Yapper overlay while typing.
        UseBlizzardSkinProxy  = true,

        -- Sticky channel: remember last-used channel across opens.
        -- Group channels (Party/Instance/Raid) stay sticky even when StickyChannel
        -- is off, unless StickyGroupChannel is also disabled.
        StickyChannel         = true,
        StickyGroupChannel    = true,

        -- When true, ESC will store the current text as a recoverable draft.
        -- When false, ESC adds to text history but does not save drafts.
        RecoverOnEscape       = false,

        -- Storyteller configuration
        StorytellerAutoExpand = true,
        StorytellerShowHint   = true,
        _multilineHintShown   = false, -- Session flag (persisted as false on reload)

        -- Storyteller manual dimensions
        StorytellerWidth      = 400,
        StorytellerHeight     = 250,

        -- Autocomplete (ghost text): on by default but only active when
        -- Spellcheck.Enabled is also true (depends on dictionary data).
        AutocompleteEnabled   = true,
    },

    Spellcheck = {
        Enabled            = false,
        Locale             = "enGB",
        MaxSuggestions     = 4,
        MaxCandidates      = 800,
        ReshuffleAttempts  = 3,
        MaxWrongLetters    = 4,
        -- N-gram index (bigram) settings
        UseNgramIndex      = true,
        NgramTopCandidates = 300,
        NgramN             = 2,
        NgramMaxPosting    = 200,
        -- Cap on unique bigram keys built during dictionary indexing.
        -- More keys = better suggestion recall but higher memory cost (~10MB+ extra).
        -- Set to 0 for uncapped (maximum accuracy, no memory limit).
        NgramKeyCapSize    = 0,
        MinWordLength      = 2,
        UnderlineStyle     = "line",
        UnderlineColor     = { r = 1.0, g = 0.2, b = 0.2, a = 0.9 },
        HighlightColor     = { r = 1.0, g = 0.18, b = 0.18, a = 0.36 },
        KeyboardLayout     = "QWERTY",
        Dict               = {},
        -- YALLM adaptive learning data caps
        YALLMFreqCap        = 2000,  -- Max unique vocabulary words tracked
        YALLMBiasCap        = 500,   -- Max typo→correction pairs stored
        YALLMAutoThreshold  = 10,    -- Times a word must be sent before auto-adding to dictionary
        SuggestionCacheSize = 50,    -- Max unique word suggestion results cached per session (0 = disabled)
    },
}

local function CopyChatTypeColor(chatType, fallback)
    local info = ChatTypeInfo and chatType and ChatTypeInfo[chatType]
    if not info then
        return fallback
    end
    return {
        r = (type(info.r) == "number") and info.r or fallback.r,
        g = (type(info.g) == "number") and info.g or fallback.g,
        b = (type(info.b) == "number") and info.b or fallback.b,
        a = fallback.a or 1,
    }
end

local function SeedChannelDefaults()
    local colors = DEFAULTS.EditBox and DEFAULTS.EditBox.ChannelTextColors
    if not colors then
        return
    end
    colors.CHANNEL = CopyChatTypeColor("CHANNEL", colors.CHANNEL)
    colors.CLUB = CopyChatTypeColor("COMMUNITIES_CHANNEL", colors.CLUB)
end

SeedChannelDefaults()

local HISTORY_DEFAULTS = {
    VERSION = DEFAULTS.System.VERSION,
    chatHistory = {},
    draft = {
        ring     = {},
        pos      = 0,
        chatType = nil,
        target   = nil,
        dirty    = false,
    },
}

local KEEP_TABLE_CONTENTS = {}

local HISTORY_PARITY_SCHEMA = {
    VERSION = HISTORY_DEFAULTS.VERSION,
    chatHistory = KEEP_TABLE_CONTENTS,
    draft = {
        ring     = KEEP_TABLE_CONTENTS,
        pos      = 0,
        chatType = nil,
        target   = nil,
        dirty    = false,
    },
}

-- Pre-ADDON_LOADED fallback — modules that read Config at load time get defaults.
YapperTable.Config = DEFAULTS

-- ---------------------------------------------------------------------------
-- SavedVariable initialisation
-- ---------------------------------------------------------------------------

--- Deep-apply missing keys from `src` into `dest`.
local function ApplyDefaults(dest, src)
    for k, v in pairs(src) do
        if dest[k] == nil then
            if type(v) == "table" then
                dest[k] = {}
                ApplyDefaults(dest[k], v)
            else
                dest[k] = v
            end
        elseif type(v) == "table" and type(dest[k]) == "table" then
            ApplyDefaults(dest[k], v)
        end
    end
end

local function DeepCopy(src)
    if type(src) ~= "table" then
        return src
    end

    local out = {}
    for k, v in pairs(src) do
        out[k] = DeepCopy(v)
    end
    return out
end

local function SyncParity(dest, schema)
    if type(dest) ~= "table" or type(schema) ~= "table" then
        return
    end

    for key, schemaVal in pairs(schema) do
        local currentVal = dest[key]

        if schemaVal == KEEP_TABLE_CONTENTS then
            if type(currentVal) ~= "table" then
                dest[key] = {}
            end
        elseif type(schemaVal) == "table" then
            if type(currentVal) ~= "table" then
                dest[key] = DeepCopy(schemaVal)
            else
                SyncParity(currentVal, schemaVal)
            end
        else
            if currentVal == nil or type(currentVal) ~= type(schemaVal) then
                dest[key] = schemaVal
            end
        end
    end

    for key in pairs(dest) do
        if schema[key] == nil then
            dest[key] = nil
        end
    end
end

local function GetConfigVersion(tbl)
    if type(tbl) ~= "table" then return nil end
    if type(tbl.System) ~= "table" then return nil end
    return tonumber(tbl.System.VERSION)
end

local function GetHistoryVersion(tbl)
    if type(tbl) ~= "table" then return nil end
    return tonumber(tbl.VERSION)
end

--- Recursively wire `child` tables to inherit from `parent` via metatables.
--- Strips any stale metatable on `child` before recursing and uses raw access
--- while walking, to avoid accidental self-referential __index chains.
local function InheritDefaults(child, parent)
    -- Defensive no-op for invalid inputs and accidental self-link attempts.
    if type(child) ~= "table" or type(parent) ~= "table" then return end
    if child == parent then return end

    -- Remove stale inheritance first so prior __index links cannot influence
    -- the raw child table shape we build below.
    setmetatable(child, nil)

    for key, parentVal in pairs(parent) do
        if type(parentVal) == "table" then
            local raw = rawget(child, key)
            if type(raw) ~= "table" then
                raw = {}
                rawset(child, key, raw)
            end
            InheritDefaults(raw, parentVal)
        end
    end

    setmetatable(child, { __index = parent })
end

--- Initialise all three SavedVariables.  Call once from ADDON_LOADED.
function YapperTable.Core:InitSavedVars()
    local currentVersion = tonumber(DEFAULTS.System.VERSION) or 0

    if type(_G.YapperDB) ~= "table" then _G.YapperDB = {} end
    if type(_G.YapperLocalConf) ~= "table" then _G.YapperLocalConf = {} end
    if type(_G.YapperLocalHistory) ~= "table" then _G.YapperLocalHistory = {} end

    local dbVersion   = GetConfigVersion(_G.YapperDB)
    local confVersion = GetConfigVersion(_G.YapperLocalConf)
    local histVersion = GetHistoryVersion(_G.YapperLocalHistory)

    -- Missing version markers indicate old/invalid schema.
    -- Rebuild ONLY the affected table, not everything.
    if dbVersion == nil then
        _G.YapperDB = {}
    end
    if confVersion == nil then
        _G.YapperLocalConf = {}
    end
    if histVersion == nil then
        _G.YapperLocalHistory = {}
    end

    -- 1. YapperDB — account-wide defaults / settings.
    ApplyDefaults(_G.YapperDB, DEFAULTS)

    if dbVersion and currentVersion > dbVersion then
        SyncParity(_G.YapperDB, DEFAULTS)
    end

    -- Migration: older saved DBs may carry an incorrect WHISPER/BN_WHISPER
    -- colour from prior versions. Force-correct BN_WHISPER to the new
    -- default when the saved DB version predates this change.
    if dbVersion and dbVersion < 1.2 then
        local teal = DEFAULTS.EditBox and DEFAULTS.EditBox.ChannelTextColors and
            DEFAULTS.EditBox.ChannelTextColors.BN_WHISPER
        if type(teal) == "table" then
            if type(_G.YapperDB.EditBox) ~= "table" then _G.YapperDB.EditBox = {} end
            if type(_G.YapperDB.EditBox.ChannelTextColors) ~= "table" then _G.YapperDB.EditBox.ChannelTextColors = {} end
            _G.YapperDB.EditBox.ChannelTextColors.BN_WHISPER = {
                r = teal.r, g = teal.g, b = teal.b, a = (teal.a ~= nil and teal.a or 1),
            }
            if type(_G.YapperDB.EditBox.ChannelColorOverrides) ~= "table" then _G.YapperDB.EditBox.ChannelColorOverrides = {} end
            _G.YapperDB.EditBox.ChannelColorOverrides.BN_WHISPER = false
            if YapperTable and YapperTable.Utils and YapperTable.Utils.Print then
                pcall(function()
                    YapperTable.Utils:Print("Migrated BN_WHISPER colour to defaults for older SavedVariables.")
                end)
            end
        end
    end

    if type(_G.YapperDB.System) ~= "table" then
        _G.YapperDB.System = {}
    end
    _G.YapperDB.System.VERSION = currentVersion
    _G.YapperDB.chatHistory = nil
    _G.YapperDB.draft = nil

    -- 2. YapperLocalConf — per-character config (inherits from YapperDB).
    ApplyDefaults(_G.YapperLocalConf, DEFAULTS)

    if confVersion and currentVersion > confVersion then
        SyncParity(_G.YapperLocalConf, DEFAULTS)
    end

    if type(_G.YapperLocalConf.System) ~= "table" then
        _G.YapperLocalConf.System = {}
    end
    _G.YapperLocalConf.System.VERSION = currentVersion

    InheritDefaults(_G.YapperLocalConf, _G.YapperDB)

    -- Switch the live Config reference to the per-character table.
    YapperTable.Config = _G.YapperLocalConf

    -- Runtime validation flags should always start clean on login/reload.
    if type(_G.YapperLocalConf.System) ~= "table" then
        _G.YapperLocalConf.System = {}
    end
    _G.YapperLocalConf.System.SettingsHaveChanged = false

    if type(_G.YapperDB.InterfaceUI) ~= "table" then
        _G.YapperDB.InterfaceUI = {}
    end
    _G.YapperDB.InterfaceUI.VERSION = currentVersion
    _G.YapperDB.InterfaceUI.dirty = false

    -- 3. YapperLocalHistory — per-character history / drafts.
    ApplyDefaults(_G.YapperLocalHistory, HISTORY_DEFAULTS)

    if histVersion and currentVersion > histVersion then
        SyncParity(_G.YapperLocalHistory, HISTORY_PARITY_SCHEMA)
    end

    _G.YapperLocalHistory.VERSION = currentVersion
end

-- Remove duplicate entries from common SavedVariables lists (user-invoked maintenance).
-- NOTE: The RemoveSavedDuplicates maintenance routine was intentionally removed.
-- If maintenance functionality is desired in future, reintroduce here with
-- careful validation and user confirmation flows.

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

function YapperTable.Core:GetVersion()
    return C_AddOns.GetAddOnMetadata(YapperName, "Version")
end

function YapperTable.Core:GetDefaults()
    return DEFAULTS
end

function YapperTable.Core:SetVerbose(bool)
    if type(bool) ~= "boolean" then
        YapperTable.Error:PrintError("BAD_ARG", "SetVerbose", "boolean", type(bool))
        return
    end
    YapperTable.Config.System.VERBOSE = bool
    YapperTable.Utils:Print("Verbose mode " .. (bool and "enabled." or "disabled."))
end

--- Centralised setting saver that handles Global/Local redirection.
--- @param category string  The category name (e.g. "EditBox", "System")
--- @param key string       The setting key
--- @param value any        The new value
function YapperTable.Core:SaveSetting(category, key, value)
    local iface = YapperTable.Interface
    if iface and type(iface.SetLocalPath) == "function" then
        return iface:SetLocalPath({ category, key }, value)
    end

    local localConf = _G.YapperLocalConf
    local globalDB  = _G.YapperDB

    if not localConf or not globalDB then return end

    if localConf.System and localConf.System.UseGlobalProfile == true then
        -- Writing to Global Profile
        if not globalDB[category] then globalDB[category] = {} end
        globalDB[category][key] = value

        -- Nil out the local override so the character falls back to the global value.
        if localConf[category] then
            localConf[category][key] = nil
        end
    else
        -- Writing to Character Local
        if not localConf[category] then localConf[category] = {} end
        localConf[category][key] = value
    end

    -- Trigger a refresh for components listening for setting changes.
    if YapperTable.Config and YapperTable.Config.System then
        YapperTable.Config.System.SettingsHaveChanged = true
    end
end

local SYSTEM_GLOBAL_SYNC_KEYS = {
    ActiveTheme = true,
    StorytellerSlideSpeed = true,
    EnableGopherBridge = true,
    EnableTypingTrackerBridge = true,
    DEBUG = true,
    VERBOSE = true,
}

local FRAME_SETTINGS_LOCAL_ONLY_KEYS = {
    MainWindowPosition = true,
}

local function RefreshProfileVisuals()
    if YapperTable.EditBox and type(YapperTable.EditBox.ApplyConfigToLiveOverlay) == "function" then
        pcall(function() YapperTable.EditBox:ApplyConfigToLiveOverlay(true) end)
    end
    if YapperTable.Multiline and YapperTable.Multiline.Active
            and type(YapperTable.Multiline.ApplyTheme) == "function" then
        pcall(function() YapperTable.Multiline:ApplyTheme() end)
    end
    if YapperTable.Interface then
        if type(YapperTable.Interface.ApplyMinimapButtonVisibility) == "function" then
            pcall(function() YapperTable.Interface:ApplyMinimapButtonVisibility() end)
        end
        if type(YapperTable.Interface.PositionMinimapButton) == "function" then
            pcall(function() YapperTable.Interface:PositionMinimapButton() end)
        end
        if type(YapperTable.Interface.SetDirty) == "function" then
            YapperTable.Interface:SetDirty(true)
        end
    end
end

function YapperTable.Core:PromoteCharacterToGlobal()
    local localConf = _G.YapperLocalConf
    local globalDB  = _G.YapperDB
    if type(localConf) ~= "table" or type(globalDB) ~= "table" then return end

    local categories = { "EditBox", "Chat", "Spellcheck" }
    for _, category in ipairs(categories) do
        if type(localConf[category]) ~= "table" then
            localConf[category] = {}
        else
            setmetatable(localConf[category], nil)
            wipe(localConf[category])
        end
    end

    if type(localConf.FrameSettings) ~= "table" then
        localConf.FrameSettings = {}
    else
        setmetatable(localConf.FrameSettings, nil)
        for key in pairs(localConf.FrameSettings) do
            if not FRAME_SETTINGS_LOCAL_ONLY_KEYS[key] then
                localConf.FrameSettings[key] = nil
            end
        end
    end

    if type(localConf.System) ~= "table" then
        localConf.System = {}
    else
        setmetatable(localConf.System, nil)
    end
    for key in pairs(SYSTEM_GLOBAL_SYNC_KEYS) do
        localConf.System[key] = nil
    end

    localConf._themeOverrides = nil
    localConf._appliedTheme = nil

    InheritDefaults(localConf, globalDB)

    local activeTheme = type(globalDB.System) == "table" and globalDB.System.ActiveTheme or nil
    if type(activeTheme) == "string"
            and YapperTable.Theme
            and type(YapperTable.Theme.SetTheme) == "function" then
        pcall(function() YapperTable.Theme:SetTheme(activeTheme) end)
    end

    RefreshProfileVisuals()
end

--- Copy character settings into the global DB.
function YapperTable.Core:PushToGlobal()
    local localConf = _G.YapperLocalConf
    local globalDB  = _G.YapperDB
    if not localConf or not globalDB then return end

    if type(localConf.System) == "table" and localConf.System.UseGlobalProfile == true then
        if YapperTable.Utils then
            YapperTable.Utils:Print("Already using Global Profile; no local overrides were pushed.")
        end
        return
    end

    local function pushCategory(category, skipKeys)
        local settings = localConf[category]
        if type(settings) ~= "table" then return end
        if type(globalDB[category]) ~= "table" then globalDB[category] = {} end

        setmetatable(settings, nil)

        for k, v in pairs(settings) do
            if not (skipKeys and skipKeys[k]) then
                globalDB[category][k] = DeepCopy(v)
            end
        end

        if skipKeys then
            for key in pairs(settings) do
                if not skipKeys[key] then
                    settings[key] = nil
                end
            end
        else
            wipe(settings)
        end
    end

    pushCategory("EditBox")
    pushCategory("Chat")
    pushCategory("Spellcheck")
    pushCategory("FrameSettings", FRAME_SETTINGS_LOCAL_ONLY_KEYS)

    if type(localConf.System) == "table" then
        if type(globalDB.System) ~= "table" then globalDB.System = {} end
        for key in pairs(SYSTEM_GLOBAL_SYNC_KEYS) do
            if localConf.System[key] ~= nil then
                globalDB.System[key] = DeepCopy(localConf.System[key])
                localConf.System[key] = nil
            end
        end
    end

    if type(localConf._themeOverrides) == "table" then
        globalDB._themeOverrides = DeepCopy(localConf._themeOverrides)
        localConf._themeOverrides = nil
    end
    if localConf._appliedTheme ~= nil then
        globalDB._appliedTheme = DeepCopy(localConf._appliedTheme)
        localConf._appliedTheme = nil
    end

    InheritDefaults(localConf, globalDB)
    RefreshProfileVisuals()

    if YapperTable.Utils then
        YapperTable.Utils:Print("Character settings pushed to Global Profile.")
    end
end
