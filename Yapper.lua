--[[
    Entry point.  Loaded last; boots the addon and wires modules together.
]]

local YapperName, YapperTable = ...

-- Localise Lua globals for performance
local math_max    = math.max
local string_format = string.format
local type   = type
local pairs  = pairs
local select = select

local function GetBypassBindingHint()
    local key1, key2 = nil, nil
    if GetBindingKey then
        -- Primary lookup: binding name as defined in Bindings.xml.
        key1, key2 = GetBindingKey("Bypass Yapper")
        if not key1 then
            -- Fallback in case client indexes by command text.
            key1, key2 = GetBindingKey("Yapper.EditBox:OpenBlizzardChat()")
        end
    end

    local function PrettyKey(key)
        if not key then return nil end
        if GetBindingText then
            local text = GetBindingText(key, "KEY_")
            if text and text ~= "" then
                return text
            end
        end
        return key
    end

    if key1 and key2 then
        return "'Bypass Yapper' keybind (currently " .. PrettyKey(key1) .. " / " .. PrettyKey(key2) .. ")"
    end
    if key1 then
        return "'Bypass Yapper' keybind (currently " .. PrettyKey(key1) .. ")"
    end
    return "'Bypass Yapper' keybind (currently unbound; default Shift+Enter)"
end

-- ---------------------------------------------------------------------------
-- Sanity checks — abort early if anything critical failed to load.
-- ---------------------------------------------------------------------------
if not YapperTable then
    error(YapperName .. ": addon table missing. Yapper cannot start.")
end
if not YapperTable.Error then
    error(YapperName .. ": Error module missing. Yapper cannot start.")
end
if not YapperTable.Config  then YapperTable.Error:Throw("MISSING_CONFIG")  end
if not YapperTable.Events  then YapperTable.Error:Throw("MISSING_EVENTS")  end
if not YapperTable.Frame   then YapperTable.Error:Throw("MISSING_FRAMES")  end
if not YapperTable.Interface then YapperTable.Error:Throw("MISSING_INTERFACE") end

-- ---------------------------------------------------------------------------
-- Boot sequence
-- ---------------------------------------------------------------------------

-- 1. Expose YapperTable as Yapper globally and create the hidden event frame.
Yapper = YapperTable
YapperTable.EventFrames:Init()

-- Slash command entry point for quickly opening/toggling settings.
SLASH_YAPPER1 = "/yapper"
SlashCmdList["YAPPER"] = function(msg)
    local input = tostring(msg or "")
    input = (input:match("^%s*(.-)%s*$") or "")
    input = string.lower(input)

    if not YapperTable.Interface then
        YapperTable.Utils:Print("warn", "Interface module unavailable.")
        return
    end

    if input == "" or input == "toggle" then
        YapperTable.Interface:ToggleMainWindow()
        return
    end

    if input == "open" or input == "show" then
        YapperTable.Interface:ShowMainWindow()
        return
    end

    if input == "close" or input == "hide" then
        if YapperTable.Interface.MainWindowFrame and YapperTable.Interface.MainWindowFrame:IsShown() then
            YapperTable.Interface:CloseFrame(YapperTable.Interface.MainWindowFrame)
        end
        return
    end

    YapperTable.Utils:Print("info", "Usage: /yapper [toggle|open|close]")
end

-- 2. ADDON_LOADED — access SavedVariables.
local function OnAddonLoaded(addonName)
    if addonName ~= YapperName then return end

    -- Initialise all three SavedVariables (YapperDB, YapperLocalConf, YapperLocalHistory).
    YapperTable.Core:InitSavedVars()

    -- Initialise StaticPopup definitions.
    if YapperTable.Interface and YapperTable.Interface.InitPopups then
        YapperTable.Interface:InitPopups()
    end

    -- Restore the previously selected theme so Theme._current is valid for the
    -- entire session.  SetTheme re-seeds non-overridden colour values from the
    -- theme into YapperLocalConf.EditBox.*, but honours _themeOverrides so any
    -- colours the user explicitly changed are kept intact.
    if YapperTable.Theme and _G.YapperLocalConf then
        local savedTheme = _G.YapperLocalConf.System
                       and _G.YapperLocalConf.System.ActiveTheme
        if type(savedTheme) == "string" and savedTheme ~= "" then
            pcall(function() YapperTable.Theme:SetTheme(savedTheme) end)
        end
    end

    local cfg = YapperTable.Config or {}

    -- Register launcher at startup (Addon Compartment preferred, fallbacks inside Interface).
    if YapperTable.Interface and YapperTable.Interface.CreateLauncher then
        YapperTable.Interface:CreateLauncher()
    end

    if YapperTable.Spellcheck and YapperTable.Spellcheck.Init then
        YapperTable.Spellcheck:Init(math_max(1, cfg.SpellcheckThreads or 1))
    end

    -- Initialise persistent history store.
    if YapperTable.History then
        YapperTable.History:InitDB()
    end

    YapperTable.Events:Unregister("PARENT_FRAME", "ADDON_LOADED")
end

YapperTable.Events:Register("PARENT_FRAME", "ADDON_LOADED", OnAddonLoaded)

-- 3. PLAYER_ENTERING_WORLD — hook chat frames and initialise pipeline.
local function OnPlayerEnteringWorld()
    if not YapperTable.Interface.PurgeRenderCache then
        YapperTable.Error:Throw("MISSING_INTERFACE")
    end
    YapperTable.Interface:PurgeRenderCache()

    -- Hook all Blizzard chat editboxes with our taint-free overlay.
    if YapperTable.EditBox then
        YapperTable.EditBox:HookAllChatFrames()
    end

    -- Boot the chat pipeline (Chat → Router + Queue).
    if YapperTable.Chat then
        YapperTable.Chat:Init()
    end

    -- Hook the overlay EditBox for undo/redo and persistent history.
    if YapperTable.History then
        YapperTable.History:HookOverlayEditBox()
    end

    YapperTable.Utils:Print("v" .. YapperTable.Core:GetVersion() .. " loaded. Use /yapper for settings. Use the " .. GetBypassBindingHint() .. " to drop down to Blizzard's text box if you run into issues like blocked actions (often caused by things like /target and /gquit).")

    -- First-run appearance choice (once per schema bump, or every reload in DEBUG).
    if YapperTable.Interface and YapperTable.Interface.ShouldShowWelcomeChoice then
        if YapperTable.Interface:ShouldShowWelcomeChoice() then
            YapperTable.Interface:CreateWelcomeChoiceFrame()
        end
    end

    YapperTable.Events:Unregister("PARENT_FRAME", "PLAYER_ENTERING_WORLD")
end

YapperTable.Events:Register("PARENT_FRAME", "PLAYER_ENTERING_WORLD", OnPlayerEnteringWorld)

-- 4. PLAYER_LOGOUT — persist data.
YapperTable.Events:Register("PARENT_FRAME", "PLAYER_LOGOUT", function()
    if YapperTable.History then
        YapperTable.History:SaveDB()
    end
end)

-- ---------------------------------------------------------------------------
-- Override toggle (disable Yapper and hand control back to Blizzard).
-- ---------------------------------------------------------------------------
function YapperTable:OverrideYapper(disable)
    if type(disable) ~= "boolean" then
        YapperTable.Error:PrintError("BAD_ARG", "OverrideYapper", "boolean", type(disable))
        return
    end
    YapperTable.YAPPER_DISABLED = disable
    if disable then
        -- Cancel any in-flight sends.
        if YapperTable.Queue then
            YapperTable.Queue:Cancel()
        end
        YapperTable.Events:UnregisterAll()
        YapperTable.Frames:HideParent()
        YapperTable.Utils:Print("|cFFFF4444Disabled.|r Control returned to Blizzard.")
    else
        YapperTable.Frames:Init() -- edit this
        if YapperTable.EditBox then
            YapperTable.EditBox:HookAllChatFrames()
        end
        if YapperTable.Chat then
            YapperTable.Chat:Init()
        end
        YapperTable.Utils:Print("|cFF00FF00Enabled.|r Yapper is back in control.")
    end
end
