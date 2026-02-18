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
        VERSION                   = 1.02,

        -- VERBOSE and DEBUG are largely for debugging.
        -- VERBOSE is for general debugging messages, or just declaring certain actions.
        -- DEBUG is for more detailed debugging messages.
        VERBOSE                   = false,
        DEBUG                     = false,

        -- The name we give to the parent frame. CAN be anything but...
        -- I'm not very original...
        FRAME_ID_PARENT           = "PARENT_FRAME",

        -- RUN_ALL_PATCHES is a setup for a future feature where developers are given
        -- a framework they can write their own patches for Yapper in their addons.
        -- Rather than, you know, digging through the guts of everything.
        RUN_ALL_PATCHES           = true,

        -- If settings have changed, reparse and recache our interface schema.
        ["SettingsHaveChanged"]   = false,

        -- Bridge Toggles
        EnableGopherBridge        = true,
        EnableTypingTrackerBridge = true,

        -- Default active theme name (registered by `Src/Theme.lua`).
        ActiveTheme               = "Yapper Default",

        -- Possibly used for system messages where some customisation is necessary. Reset to nil after every use.
        SYSTEM_PREFIX             = nil,
    },

    -- Obviously this holds settings for our interface frames.
    -- Don't worry about these unless you know what you're doing. They're
    -- for things like scrolling and moving the window.
    ["FrameSettings"] = {
        ["MouseWheelStepRate"] = 30,
        ["SettingsViewMode"] = "basic",
        ["EnableMinimapButton"] = true,
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
        DELINEATOR        = ">>",

        -- Always synced to DELINEATOR.
        PREFIX            = ">>",

        -- Minimum time between posts.
        MIN_POST_INTERVAL = 1.0,

        -- How long to wait before sending the next post.
        POST_TIMEOUT      = 2,

        -- How many posts to send at once.
        BATCH_SIZE        = 3,

        -- How long to wait between batches.
        BATCH_THROTTLE    = 2.0,

        -- How long to wait before giving up.
        STALL_TIMEOUT     = 1.0,
    },

    -- EditBox appearance defaults
    EditBox = {
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
            INSTANCE_CHAT = false,
            RAID = false,
            RAID_WARNING = false,
        },

        ChannelTextColors     = {
            SAY = { r = 1.00, g = 1.00, b = 1.00, a = 1 },
            YELL = { r = 1.00, g = 0.25, b = 0.25, a = 1 },
            PARTY = { r = 0.67, g = 0.67, b = 1.00, a = 1 },
            WHISPER = { r = 1.00, g = 0.50, b = 1.00, a = 1 },
            INSTANCE_CHAT = { r = 1.00, g = 0.50, b = 0.00, a = 1 },
            RAID = { r = 1.00, g = 0.50, b = 0.00, a = 1 },
            RAID_WARNING = { r = 1.00, g = 0.28, b = 0.03, a = 1 },
        },

        -- Vertical sizing
        MinHeight             = 0, -- minimum overlay height; only applies if larger than the native editbox height
        FontPad               = 8, -- extra pixels above + below the text baseline

        -- Sticky channel: remember last-used channel across opens.
        -- Group channels (Party/Instance/Raid) stay sticky even when StickyChannel
        -- is off, unless StickyGroupChannel is also disabled.
        StickyChannel         = true,
        StickyGroupChannel    = true,
    },
}

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
local function InheritDefaults(child, parent)
    for key, parentVal in pairs(parent) do
        if type(parentVal) == "table" then
            if type(child[key]) ~= "table" then
                child[key] = {}
            end
            InheritDefaults(child[key], parentVal)
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
