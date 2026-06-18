--[[
    Addon-wide configuration and version info.
    Loaded first; every other module reads from YapperTable.Config.
]]

local YapperName, YapperTable = ...

YapperTable.Core = YapperTable.Core or {}
YapperTable.Core.UI = YapperTable.Core.UI or {}
YapperTable.Core.UI.Frames = YapperTable.Core.UI.Frames or {}
local State = YapperTable.State
-- Note: Core.lua loads before Utils.lua, so use full path YapperTable.Utils

-- ---------------------------------------------------------------------------
-- Centralised configuration (hardcoded defaults)
-- ---------------------------------------------------------------------------
local DEFAULTS = {
    System = {
        -- Schema version for SavedVariables migration; bump only when data structure changes.
        VERSION                   = 2.3,
        WELCOME_VERSION           = 1,

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
        ["WhatsNewFontSize"] = 12,
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
        ChannelColorMode = {
            SAY = "blizzard",
            EMOTE = "blizzard",
            YELL = "blizzard",
            PARTY = "blizzard",
            WHISPER = "blizzard",
            BN_WHISPER = "blizzard",
            CHANNEL = "blizzard",
            CLUB = "blizzard",
            INSTANCE_CHAT = "blizzard",
            RAID = "blizzard",
            RAID_WARNING = "blizzard",
        },

        ChannelTextColors     = {
            SAY = { r = 1.00, g = 1.00, b = 1.00, a = 1 },
            EMOTE = { r = 1.00, g = 0.50, b = 0.25, a = 1 },
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

        -- Try to imitate Blizzard's editbox appearance
        UseBlizzardSkinProxy  = false,

        -- Hide Blizzard's editbox when Yapper is open (only when not using proxy mode)
        HideBlizzardEditbox   = true,

        -- Sticky channel: remember last-used channel across opens.
        -- Group channels (Party/Instance/Raid) stay sticky even when StickyChannel
        -- is off, unless StickyGroupChannel is also disabled.
        StickyChannel         = true,
        StickyGroupChannel    = true,

        -- When true, ESC will store the current text as a recoverable draft.
        -- When false, ESC adds to text history but does not save drafts.
        RecoverOnEscape       = false,

        -- Storyteller manual dimensions
        StorytellerWidth      = 400,
        StorytellerHeight     = 250,

        -- Autocomplete (ghost text): on by default but only active when
        -- Spellcheck.Enabled is also true (depends on dictionary data).
        AutocompleteEnabled   = true,

        -- Sticky state: tracks the last-used channel, target, and language.
        -- Persisted per-character in YapperLocalConf.
        LastUsed = {
            chatType = "SAY",
            target   = nil,
            language = nil,
        },
        
        -- Emote auto-send: true = pressing enter/clicking sends it, false = fills editbox + space.
        EmoteAutoSend         = false,
    },

    Spellcheck = {
        Enabled             = false,
        Locale              = "enGB",
        MaxSuggestions      = 4,
        MaxCandidates       = 800,
        ReshuffleAttempts   = 3,
        MaxWrongLetters     = 4,
        -- N-gram index (bigram) settings
        UseNgramIndex       = true,
        NgramTopCandidates  = 300,
        NgramN              = 2,
        NgramMaxPosting     = 200,
        -- Cap on unique bigram keys built during dictionary indexing.
        -- More keys = better suggestion recall but higher memory cost (~10MB+ extra).
        -- Set to 0 for uncapped (maximum accuracy, no memory limit).
        NgramKeyCapSize     = 0,
        MinWordLength       = 2,
        UnderlineStyle      = "line",
        UnderlineColor      = { r = 1.0, g = 0.2, b = 0.2, a = 0.9 },
        HighlightColor      = { r = 1.0, g = 0.18, b = 0.18, a = 0.36 },
        KeyboardLayout      = "QWERTY",
        Dict                = KEEP_TABLE_CONTENTS,
        YASEnabled          = true,
        -- YAS adaptive learning data caps
        YASFreqCap          = 2000, -- Max unique vocabulary words tracked
        YASBiasCap          = 500,  -- Max typo→correction pairs stored
        YASNegBiasCap       = 500,  -- Max rejected suggestion pairs tracked (decays over time)
        YASAutoThreshold    = 10,   -- Times a word must be sent before auto-adding to dictionary
        YASAutoCap          = 500,  -- Max pending auto-learn tracking entries
        SuggestionCacheSize = 50,   -- Max unique word suggestion results cached per session (0 = disabled)
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

-- Add a cache for player languages.
YapperTable.SpokenLanguages = {}
YapperTable._languageCacheHash = nil

function YapperTable.Core:BuildLanguageCache()
    -- Wipe the cache so we can repopulate.
    YapperTable.SpokenLanguages = {}
    YapperTable._languageCacheHash = nil

    local count = GetNumLanguages()
    if not count or count == 0 then
        YapperTable.Utils:DebugPrint("BuildLanguageCache: No languages available")
        return
    end

    local hash = 0
    for i = 1, count do
        local langStr, langId = GetLanguageByIndex(i)
        if langId and langStr then
            -- Store both original and uppercase versions for case-insensitive lookup
            YapperTable.SpokenLanguages[langStr] = langId
            YapperTable.SpokenLanguages[langStr:upper()] = langId
            -- Simple hash: sum of language IDs (efficient for comparison)
            hash = hash + langId
        end
    end

    YapperTable._languageCacheHash = hash
    YapperTable.Utils:DebugPrint("BuildLanguageCache: Cached " .. count .. " languages (hash: " .. hash .. ")")
end

--- Check if the language cache is still valid for the current character.
--- Returns true if cache matches current languages, false if it needs rebuilding.
--- @return boolean isValid
function YapperTable.Core:IsLanguageCacheValid()
    local currentCount = GetNumLanguages()
    if not currentCount or currentCount == 0 then
        return false
    end

    -- Quick count check first
    local cachedCount = 0
    for _ in pairs(YapperTable.SpokenLanguages) do
        cachedCount = cachedCount + 1
    end
    -- Since we store both original and uppercase, cachedCount should be 2x currentCount
    if cachedCount ~= (currentCount * 2) then
        return false
    end

    -- Hash comparison for efficient validation
    local currentHash = 0
    for i = 1, currentCount do
        local _, langId = GetLanguageByIndex(i)
        if langId then
            currentHash = currentHash + langId
        end
    end

    return currentHash == YapperTable._languageCacheHash
end

--- Get the language or defaults if not present.
--- @param lang string|number|nil lang is case-insensitive. "Common", "common", "COMMON" all work.
--- @return number langId
function YapperTable.Core:GetCharacterLanguage(lang)
    if type(lang) ~= "string" then
        if type(lang) == "number" then
            return lang
        end
    end

    -- Ensure cache is valid before lookup
    if not self:IsLanguageCacheValid() then
        self:BuildLanguageCache()
    end

    -- Find language in cache (case-insensitive via uppercase fallback)
    if YapperTable.SpokenLanguages[lang] then
        return YapperTable.SpokenLanguages[lang]
    end
    -- Try uppercase version for case-insensitive match
    if lang and YapperTable.SpokenLanguages[lang:upper()] then
        return YapperTable.SpokenLanguages[lang:upper()]
    end

    -- If not present, use default.
    local _, langId = GetDefaultLanguage()
    if lang and lang ~= "" then
        YapperTable.Utils:DebugPrint("GetCharacterLanguage: '" .. lang .. "' not found, using default")
    end
    return langId
end

--- Register a frame in the central UI registry for external access.
--- @param category string  The functional category (e.g. "Overlay", "Spellcheck")
--- @param key      string  Unique identifier within that category
--- @param frame    table   The WoW frame object
function YapperTable.Core:RegisterFrame(category, key, frame)
    if type(category) ~= "string" or type(key) ~= "string" or not frame then return end
    self.UI.Frames[category] = self.UI.Frames[category] or {}
    self.UI.Frames[category][key] = frame
end

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

local PROTECTED_KEYS = {
    InterfaceUI     = true,
    _Stash          = true,
    _appliedTheme   = true,
    _themeOverrides = true,
    minimapbutton   = true,
    SpellcheckLearned = true,
    SpellcheckLocale = true,
}

--- Sync user config with schema defaults.
--- Ensures user config has all keys from schema with correct types/values.
--- Preserves user's existing values where compatible, removes obsolete keys.
--- @param dest table   User's config table (e.g., YapperDB)
--- @param schema table Default schema (DEFAULTS)
local function SyncParity(dest, schema)
    if type(dest) ~= "table" or type(schema) ~= "table" then
        return
    end

    -- First pass: ensure all schema keys exist in dest with correct types
    for key, schemaVal in pairs(schema) do
        local currentVal = dest[key]

        if schemaVal == KEEP_TABLE_CONTENTS then
            -- Preserve user's table contents, just ensure it's a table
            if type(currentVal) ~= "table" then
                dest[key] = {}
            end
        elseif type(schemaVal) == "table" then
            -- Recursively sync nested tables
            if type(currentVal) ~= "table" then
                dest[key] = DeepCopy(schemaVal)
            else
                SyncParity(currentVal, schemaVal)
            end
        else
            -- Primitive values: overwrite if missing or wrong type
            if currentVal == nil or type(currentVal) ~= type(schemaVal) then
                dest[key] = schemaVal
            end
        end
    end

    -- Second pass: remove keys that no longer exist in schema (unless protected)
    for key in pairs(dest) do
        if schema[key] == nil and not PROTECTED_KEYS[key] then
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

    _G.YapperDB = YapperTable.Utils:EnsureTable(_G.YapperDB)
    _G.YapperLocalConf = YapperTable.Utils:EnsureTable(_G.YapperLocalConf)
    _G.YapperLocalHistory = YapperTable.Utils:EnsureTable(_G.YapperLocalHistory)

    local dbVersion   = GetConfigVersion(_G.YapperDB)
    local confVersion = GetConfigVersion(_G.YapperLocalConf)
    local histVersion = GetHistoryVersion(_G.YapperLocalHistory)

    if dbVersion == nil then
        _G.YapperDB = {}
    end
    if confVersion == nil then
        _G.YapperLocalConf = {}
    end
    if histVersion == nil then
        _G.YapperLocalHistory = {}
    end

    -- Mark current versions immediately to avoid recursive migration loops
    -- or stale version data if the boot sequence errors later.
    _G.YapperDB.System = YapperTable.Utils:EnsureTable(_G.YapperDB.System)
    _G.YapperLocalConf.System = YapperTable.Utils:EnsureTable(_G.YapperLocalConf.System)
    _G.YapperDB.System.VERSION = currentVersion
    _G.YapperLocalConf.System.VERSION = currentVersion
    _G.YapperLocalHistory.VERSION = currentVersion

    -- 1. YapperDB — account-wide defaults / settings.
    ApplyDefaults(_G.YapperDB, DEFAULTS)

    if dbVersion and currentVersion > dbVersion then
        SyncParity(_G.YapperDB, DEFAULTS)
    end

    -- Run detached migrations for configuration key changes
    if YapperTable.Migrations then
        YapperTable.Migrations:RunMigrations(_G.YapperDB, "DB")
    end

    -- Migration: older saved DBs may carry an incorrect WHISPER/BN_WHISPER
    -- colour from prior versions. Force-correct BN_WHISPER to the new
    -- default when the saved DB version predates this change.
    if dbVersion and dbVersion < 1.2 then
        local teal = DEFAULTS.EditBox and DEFAULTS.EditBox.ChannelTextColors and
            DEFAULTS.EditBox.ChannelTextColors.BN_WHISPER
        if type(teal) == "table" then
            _G.YapperDB.EditBox = YapperTable.Utils:EnsureTable(_G.YapperDB.EditBox)
            _G.YapperDB.EditBox.ChannelTextColors = YapperTable.Utils:EnsureTable(_G.YapperDB.EditBox.ChannelTextColors)
            _G.YapperDB.EditBox.ChannelTextColors.BN_WHISPER = {
                r = teal.r, g = teal.g, b = teal.b, a = (teal.a ~= nil and teal.a or 1),
            }
            _G.YapperDB.EditBox.ChannelColorMode = YapperTable.Utils:EnsureTable(_G.YapperDB.EditBox.ChannelColorMode)
            _G.YapperDB.EditBox.ChannelColorMode.BN_WHISPER = "custom"
            YapperTable.Utils:Print("Migrated BN_WHISPER colour to defaults for older SavedVariables.")
        end
    end

    _G.YapperDB.chatHistory = nil
    _G.YapperDB.draft = nil

    -- 2. YapperLocalConf — per-character config.
    -- We no longer call ApplyDefaults here, as it "flattens" the table and
    -- blocks metatable inheritance from the Global Profile.
    if type(_G.YapperLocalConf.System) ~= "table" then
        _G.YapperLocalConf.System = {}
    end

    if confVersion and currentVersion ~= confVersion then
        SyncParity(_G.YapperLocalConf, DEFAULTS)
    end

    -- Run detached migrations for configuration key changes
    if YapperTable.Migrations then
        YapperTable.Migrations:RunMigrations(_G.YapperLocalConf, "LOCAL")
    end

    _G.YapperLocalConf.System.VERSION = currentVersion

    -- Initialise inheritance chain (Global vs Local).
    self:RefreshInheritance()

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

    if histVersion and currentVersion ~= histVersion then
        SyncParity(_G.YapperLocalHistory, HISTORY_PARITY_SCHEMA)
    end

    _G.YapperLocalHistory.VERSION = currentVersion
end

--- Update the inheritance chain of the active local configuration.
--- Called when the user toggles the Global Profile on or off.
function YapperTable.Core:RefreshInheritance()
    local localConf = _G.YapperLocalConf
    local globalDB  = _G.YapperDB
    if not localConf or not globalDB then return end

    local useGlobal = localConf.System and localConf.System.UseGlobalProfile == true

    if useGlobal then
        InheritDefaults(localConf, globalDB)
    else
        InheritDefaults(localConf, DEFAULTS)
    end
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
    self:SaveSetting("System", "VERBOSE", bool)
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
    if YapperTable.Multiline and State and State:IsMultiline()
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

    if type(localConf._Stash) ~= "table" then
        localConf._Stash = {}
    end

    local categories = { "EditBox", "Chat", "Spellcheck" }
    for _, category in ipairs(categories) do
        if type(localConf[category]) ~= "table" then
            localConf[category] = {}
        else
            setmetatable(localConf[category], nil)

            if type(localConf._Stash[category]) ~= "table" then
                localConf._Stash[category] = {}
            end

            if category == "Spellcheck" then
                for k, v in pairs(localConf[category]) do
                    if k ~= "Dict" then
                        -- Only stash if it's not an empty proxy table
                        if type(v) ~= "table" or next(v) ~= nil then
                            localConf._Stash[category][k] = v
                        end
                        localConf[category][k] = nil
                    end
                end
            else
                for k, v in pairs(localConf[category]) do
                    if type(v) ~= "table" or next(v) ~= nil then
                        localConf._Stash[category][k] = v
                    end
                    localConf[category][k] = nil
                end
            end
        end
    end

    if type(localConf.FrameSettings) ~= "table" then
        localConf.FrameSettings = {}
    else
        setmetatable(localConf.FrameSettings, nil)
        if type(localConf._Stash.FrameSettings) ~= "table" then
            localConf._Stash.FrameSettings = {}
        end
        for key, v in pairs(localConf.FrameSettings) do
            if not FRAME_SETTINGS_LOCAL_ONLY_KEYS[key] then
                -- Only stash if it's not an empty proxy table
                if type(v) ~= "table" or next(v) ~= nil then
                    localConf._Stash.FrameSettings[key] = v
                end
                localConf.FrameSettings[key] = nil
            end
        end
    end

    if type(localConf.System) ~= "table" then
        localConf.System = {}
    else
        setmetatable(localConf.System, nil)
    end

    if type(localConf._Stash.System) ~= "table" then
        localConf._Stash.System = {}
    end

    -- Intentionally clear only global-sync keys; preserve local-only system keys.
    for key in pairs(SYSTEM_GLOBAL_SYNC_KEYS) do
        if localConf.System[key] ~= nil then
            localConf._Stash.System[key] = localConf.System[key]
            localConf.System[key] = nil
        end
    end

    localConf._themeOverrides = nil
    localConf._appliedTheme = nil

    self:RefreshInheritance()

    local activeTheme = type(globalDB.System) == "table" and globalDB.System.ActiveTheme or nil
    if type(activeTheme) == "string"
        and YapperTable.Theme
        and type(YapperTable.Theme.SetTheme) == "function" then
        pcall(function() YapperTable.Theme:SetTheme(activeTheme) end)
    end

    RefreshProfileVisuals()
end

--- Unpack stashed local settings when switching away from Global Profile.
function YapperTable.Core:DemoteGlobalToCharacter()
    local localConf = _G.YapperLocalConf
    if type(localConf) ~= "table" then return end

    if type(localConf._Stash) == "table" then
        for category, stashTable in pairs(localConf._Stash) do
            if type(localConf[category]) ~= "table" then
                localConf[category] = {}
            end
            for k, v in pairs(stashTable) do
                localConf[category][k] = v
            end
        end
        localConf._Stash = nil
    end

    self:RefreshInheritance()
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
        globalDB[category] = YapperTable.Utils:EnsureTable(globalDB[category])

        setmetatable(settings, nil)

        for k, v in pairs(settings) do
            if not (skipKeys and skipKeys[k]) then
                -- Only push if it's a scalar or a table with actual data.
                -- Empty tables are just inheritance proxies and should be skipped.
                if type(v) ~= "table" or next(v) ~= nil then
                    globalDB[category][k] = DeepCopy(v)
                end
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
        globalDB.System = YapperTable.Utils:EnsureTable(globalDB.System)
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
