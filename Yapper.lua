--[[
    Entry point.  Loaded last; boots the addon and wires modules together.
]]

local YapperName, YapperTable = ...

-- Localise Lua globals for performance
local string_format = string.format
local type   = type
local pairs  = pairs
local select = select
local tostring = tostring

local _unitPopupWhisperOriginalOnClick = nil

local function InstallUnitPopupWhisperOverride()
    if YapperTable._unitPopupWhisperOverrideInstalled then
        return true
    end

    local mixin = _G.UnitPopupWhisperButtonMixin
    if type(mixin) ~= "table" or type(mixin.OnClick) ~= "function" then
        return false
    end

    if not _unitPopupWhisperOriginalOnClick then
        _unitPopupWhisperOriginalOnClick = mixin.OnClick
    end

    mixin.OnClick = function(self, contextData)
        local eb = YapperTable and YapperTable.EditBox
        local utils = YapperTable and YapperTable.Utils

        if not eb or type(eb.Show) ~= "function" or not contextData then
            return _unitPopupWhisperOriginalOnClick(self, contextData)
        end

        if utils and utils.IsChatLockdown and utils:IsChatLockdown() then
            return _unitPopupWhisperOriginalOnClick(self, contextData)
        end

        local isBNetAccount = contextData.bnetIDAccount
        if not isBNetAccount then
            local playerLocation = contextData.playerLocation
            if playerLocation and playerLocation.IsBattleNetGUID then
                isBNetAccount = playerLocation:IsBattleNetGUID()
            end
        end

        -- Keep Blizzard's native BNet path untouched.
        if isBNetAccount then
            return _unitPopupWhisperOriginalOnClick(self, contextData)
        end

        local unit = contextData.unit
        if unit and not UnitIsHumanPlayer(unit) then
            return
        end

        local fullName = nil
        if UnitPopupSharedUtil and UnitPopupSharedUtil.GetFullPlayerName then
            fullName = UnitPopupSharedUtil.GetFullPlayerName(contextData)
        end

        if type(fullName) ~= "string" or fullName == "" then
            return _unitPopupWhisperOriginalOnClick(self, contextData)
        end

        local blizzBox = contextData.chatFrame and contextData.chatFrame.editBox
        if not blizzBox then
            blizzBox = eb.OrigEditBox or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox) or _G.ChatFrame1EditBox
        end

        local existingText = ""
        if blizzBox and blizzBox.GetText then
            existingText = blizzBox:GetText() or ""
        end

        print(string_format("[Yapper] Mixin whisper override -> %s", tostring(fullName)))

        -- If already open, retarget in place via the shared routing helper so
        -- this path and the SendTell hook cannot drift apart.
        if eb.Overlay and eb.Overlay:IsShown() then
            eb:RetargetOpenWhisper(fullName, blizzBox)
            return
        end

        if blizzBox and blizzBox.Hide then
            blizzBox:Hide()
            if blizzBox.SetText then
                blizzBox:SetText("")
            end
        end

        eb:Show(blizzBox or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox) or _G.ChatFrame1EditBox)
        eb.ChatType = "WHISPER"
        eb.Target = fullName
        eb.ChannelName = nil
        eb._externalWhisperTarget = fullName

        if existingText ~= "" and eb.OverlayEdit and eb.OverlayEdit.SetText then
            eb.OverlayEdit:SetText(existingText)
        end

        eb:RefreshLabel()
    end

    YapperTable._unitPopupWhisperOverrideInstalled = true

    return true
end

local function RegisterUnitPopupOverrideFallback()
    if YapperTable._unitPopupWhisperFallbackRegistered then
        return
    end

    if not YapperTable.Events or not YapperTable.Events.Register then
        return
    end

    YapperTable.Events:Register("PARENT_FRAME", "ADDON_LOADED", function(addonName)
        if addonName ~= "Blizzard_UnitPopup" and addonName ~= "Blizzard_UnitPopupShared" then
            return
        end
        InstallUnitPopupWhisperOverride()
    end, "UNITPOPUP_WHISPER_OVERRIDE")

    YapperTable._unitPopupWhisperFallbackRegistered = true
end

local function GetBypassBindingHint()
    local key1, key2 = nil, nil
    if GetBindingKey then
        -- Primary lookup: binding name as defined in Bindings.xml.
        key1, key2 = GetBindingKey("Bypass Yapper")
        if not key1 then
            return "Bypass Yapper keybind (currently unbound; default Shift+Enter)" -- but how???
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
local REQUIRED_MODULES = {
    "Utils", "Migrations", "Config",
    "Frame", "EventFrames", "Events",
    "API", "State",
    "Spellcheck", "IconGallery",
    "EditBox", "EditBoxHooksCore",
    "Router", "Chunking", "Queue", "Chat",
    "Multiline", "Autocomplete", "Emotes", "History", "Theme",
    "Interface",
}
for _, mod in ipairs(REQUIRED_MODULES) do
    if not YapperTable[mod] then
        YapperTable.Error:Throw("MISSING_" .. mod:upper())
    end
end

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

    if input == "help" or input == "?" then
        YapperTable.Interface:OpenToCategory("help")
        return
    end

    if input == "close" or input == "hide" then
        if YapperTable.Interface.MainWindowFrame and YapperTable.Interface.MainWindowFrame:IsShown() then
            YapperTable.Interface:CloseFrame(YapperTable.Interface.MainWindowFrame)
        end
        return
    end

    if input == "export" then
        local sc = YapperTable.Spellcheck
        if sc and sc.YAS and sc.YAS.Export then
            local locale = sc:GetLocale()
            local report = sc.YAS:Export(locale)
            print(report)
        else
            YapperTable.Utils:Print("warn", "YAS module unavailable.")
        end
        return
    end

    if input == "whatsnew" or input == "changelog" then
        YapperTable.Interface:CreateWhatsNewFrame()
        return
    end

    YapperTable.Utils:Print("info", "Usage: /yapper [toggle | open | close | whatsnew | help | ?]")
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

    -- Restore the previously selected theme name so Theme:GetTheme() reflects
    -- the active choice for this session.
    --
    -- Important: do NOT call SetTheme() during boot; SetTheme re-seeds colour
    -- fields into config and can stomp user-saved colours on reload. Colours
    -- are already persisted in SavedVariables and applied from config.
    if YapperTable.Theme then
        local savedTheme = nil
        if type(_G.YapperLocalConf) == "table"
            and type(_G.YapperLocalConf.System) == "table" then
            savedTheme = _G.YapperLocalConf.System.ActiveTheme
        end
        if (type(savedTheme) ~= "string" or savedTheme == "")
            and type(_G.YapperDB) == "table"
            and type(_G.YapperDB.System) == "table" then
            savedTheme = _G.YapperDB.System.ActiveTheme
        end
        if type(savedTheme) == "string"
            and savedTheme ~= ""
            and YapperTable.Theme.GetTheme
            and YapperTable.Theme:GetTheme(savedTheme) then
            YapperTable.Theme._current = savedTheme
        end
    end

    -- Register launcher at startup (Addon Compartment preferred, fallbacks inside Interface).
    if YapperTable.Interface and YapperTable.Interface.CreateLauncher then
        YapperTable.Interface:CreateLauncher()
    end

    if YapperTable.Spellcheck and YapperTable.Spellcheck.Init then
        YapperTable.Spellcheck:Init(1)
    end

    -- Initialise persistent history store.
    if YapperTable.History then
        YapperTable.History:InitDB()
    end

    -- Initialise keybind system if enabled.
    if YapperTable.EditBox then
        YapperTable.EditBox:InitKeybinds()
        YapperTable.EditBox:CreateFocusTrap()
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

    -- Override unit-popup whisper button to route menu-based character whispers
    -- directly into Yapper before Blizzard opens/parses the native editbox.
    if not InstallUnitPopupWhisperOverride() then
        RegisterUnitPopupOverrideFallback()
    end

    -- Register keybind overrides if enabled.
    if YapperTable.EditBox then
        YapperTable.EditBox:RegisterKeybindOverrides()
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

    -- First-run appearance choice (once per schema bump),
    -- or What's New frame for returning users on a version bump.
    if YapperTable.Interface then
        if YapperTable.Interface.ShouldShowWelcomeChoice
            and YapperTable.Interface:ShouldShowWelcomeChoice() then
            YapperTable.Interface:CreateWelcomeChoiceFrame()
        elseif YapperTable.Interface.CheckForChangelogUpdate then
            YapperTable.Interface:CheckForChangelogUpdate()
        end
    end

    YapperTable.Events:Unregister("PARENT_FRAME", "PLAYER_ENTERING_WORLD")

    -- After unregistering, build the language cache.
    YapperTable.Core:BuildLanguageCache()

    -- Register for language change events to keep cache current
    if YapperTable.Events then
        YapperTable.Events:Register("PARENT_FRAME", "LANGUAGE_LIST_CHANGED", function()
            YapperTable.Utils:DebugPrint("LANGUAGE_LIST_CHANGED: Rebuilding language cache")
            YapperTable.Core:BuildLanguageCache()
        end)

        YapperTable.Events:Register("PARENT_FRAME", "CAN_PLAYER_SPEAK_LANGUAGE_CHANGED", function()
            YapperTable.Utils:DebugPrint("CAN_PLAYER_SPEAK_LANGUAGE_CHANGED: Rebuilding language cache")
            YapperTable.Core:BuildLanguageCache()
        end)
    end

    -- Final transition to IDLE: Boot sequence complete.
    if YapperTable.State then
        if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
            YapperTable.State:ToLockdown()
            if YapperTable.EditBox then
                YapperTable.EditBox._lockdown.handedOff = true
            end
        else
            YapperTable.State:ToIdle()
        end
    end
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
        if YapperTable.EventFrames then
            YapperTable.EventFrames:HideParent()
        end
        YapperTable.Utils:Print("|cFFFF4444Disabled.|r Control returned to Blizzard.")
    else
        if YapperTable.EventFrames then
            YapperTable.EventFrames:Init()
        end
        if YapperTable.EditBox then
            YapperTable.EditBox:HookAllChatFrames()
        end
        if YapperTable.Chat then
            YapperTable.Chat:Init()
        end
        YapperTable.Utils:Print("|cFF00FF00Enabled.|r Yapper is back in control.")
    end
end
