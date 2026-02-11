--[[
    Core.lua — Yapper 1.0.0
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
        VERBOSE = false,
        DEBUG   = false,
        FRAME_ID_PARENT  = "PARENT_FRAME",
        RUN_ALL_PATCHES  = true,
    },
    Chat = {
        USE_DELINEATORS   = true,
        CHARACTER_LIMIT   = 255,
        MAX_HISTORY_LINES = 15,
        DELINEATOR        = " >>",
        PREFIX            = ">> ",
        MIN_POST_INTERVAL = 1.0,
        POST_TIMEOUT      = 2,
        BATCH_SIZE        = 3,
        BATCH_THROTTLE    = 2.0,
        STALL_TIMEOUT     = 1.0,
    },
    -- ── EditBox appearance (defaults until a settings panel exists) ───
    EditBox = {
        -- Input area background
        InputBg = {
            r = 0.05, g = 0.05, b = 0.05, a = 1.0,
        },
        -- Label area background
        LabelBg = {
            r = 0.06, g = 0.06, b = 0.06, a = 1.0,
        },
        -- Font: nil means "inherit from Blizzard editbox".
        -- Set a string like "Fonts\\FRIZQT__.TTF" to override.
        FontFace  = nil,
        FontSize  = 0,          -- 0 = inherit from Blizzard editbox
        FontFlags = "",         -- e.g. "OUTLINE", "THICKOUTLINE"
        -- Text colour (nil = white)
        TextColor = { r = 1, g = 1, b = 1, a = 1 },
        -- Vertical sizing
        MinHeight  = 0,         -- 0 = match Blizzard editbox height (auto)
        FontPad    = 8,         -- extra pixels above + below the text baseline
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
    -- 1. YapperDB — account-wide defaults / settings.
    if not _G.YapperDB then _G.YapperDB = {} end
    ApplyDefaults(_G.YapperDB, DEFAULTS)

    -- 2. YapperLocalConf — per-character config (inherits from YapperDB).
    if not _G.YapperLocalConf then _G.YapperLocalConf = {} end
    InheritDefaults(_G.YapperLocalConf, _G.YapperDB)

    -- Switch the live Config reference to the per-character table.
    YapperTable.Config = _G.YapperLocalConf

    -- 3. YapperLocalHistory — per-character history / drafts.
    if not _G.YapperLocalHistory then _G.YapperLocalHistory = {} end
end

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

function YapperTable.Core:GetVersion()
    return C_AddOns.GetAddOnMetadata(YapperName, "Version")
end

function YapperTable.Core:SetVerbose(bool)
    if type(bool) ~= "boolean" then
        YapperTable.Error:PrintError("BAD_ARG", "SetVerbose", "boolean", type(bool))
        return
    end
    YapperTable.Config.System.VERBOSE = bool
    YapperTable.Utils:Print("Verbose mode " .. (bool and "enabled." or "disabled."))
end
