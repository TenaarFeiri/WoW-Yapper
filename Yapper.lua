--[[
    Yapper.lua — Yapper 1.0.0
    Entry point.  Loaded last; boots the addon and wires modules together.
]]

local YapperName, YapperTable = ...

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
if not YapperTable.Frames  then YapperTable.Error:Throw("MISSING_FRAMES")  end

-- ---------------------------------------------------------------------------
-- Boot sequence
-- ---------------------------------------------------------------------------

-- 1. Create the hidden event frame.
YapperTable.Frames:Init()

-- 2. ADDON_LOADED — access SavedVariables.
local function OnAddonLoaded(addonName)
    if addonName ~= YapperName then return end

    -- Initialise all three SavedVariables (YapperDB, YapperLocalConf, YapperLocalHistory).
    YapperTable.Core:InitSavedVars()

    -- Initialise persistent history store.
    if YapperTable.History then
        YapperTable.History:InitDB()
    end

    YapperTable.Events:Unregister("PARENT_FRAME", "ADDON_LOADED")
end

YapperTable.Events:Register("PARENT_FRAME", "ADDON_LOADED", OnAddonLoaded)

-- 3. PLAYER_ENTERING_WORLD — hook chat frames and initialise pipeline.
local function OnPlayerEnteringWorld()
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

    YapperTable.Utils:Print("v" .. YapperTable.Core:GetVersion() .. " loaded. Happy roleplaying!")
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
        YapperTable.Frames:Init()
        if YapperTable.EditBox then
            YapperTable.EditBox:HookAllChatFrames()
        end
        if YapperTable.Chat then
            YapperTable.Chat:Init()
        end
        YapperTable.Utils:Print("|cFF00FF00Enabled.|r Yapper is back in control.")
    end
end
