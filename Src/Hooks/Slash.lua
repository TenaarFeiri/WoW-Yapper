--[[
    Hooks/Slash.lua
    Slash command forwarding to Blizzard.
]]

local _, YapperTable = ...
local EditBox = YapperTable.EditBox

-- Resolve locals from Hub.lua
local Core = YapperTable.EditBoxHooksCore
local CHATTYPE_TO_OVERRIDE_KEY = Core.CHATTYPE_TO_OVERRIDE_KEY

-- Re-localise Lua globals.
local type = type
local string_format = string.format

-- ---------------------------------------------------------------------------
-- Slash command forwarding
-- ---------------------------------------------------------------------------

-- Dispatch SendText on Blizzard's editbox without letting a secret-value
-- error inside Blizzard's slash handlers escape our tainted call (e.g.
-- /invite -> GetUnitName compares a secret realm under restrictions).
local function SafeSendText(editBox)
    return pcall(editBox.SendText, editBox)
end

--- Emulate Blizzard's /join handler without running it. Blizzard's JOIN
--- slash handler writes the channel name into DEFAULT_CHAT_FRAME.channelList
--- (and the zone channel id into zoneChannelList); forwarded through SendText
--- that write lands under our tainted execution, and MessageEventHandler's
--- pairs(channelList) then re-taints every CHANNEL* event dispatch that
--- touches it -- exploding Blizzard's secret-value compares under addon
--- restrictions (delves etc.). The client maintains channel membership
--- itself, so we call JoinPermanentChannel directly and never touch
--- channelList; regional channels re-add cleanly on their first YOU_CHANGED
--- notice via ChatFrame_CheckAddChannel, and RegisterForChannels rebuilds
--- the list from client state on the next UPDATE_CHAT_WINDOWS.
--- @param text string  Full command text, e.g. "/join channel password".
function EditBox:ForwardJoinChannel(text)
    local utils = YapperTable.Utils
    local frame = DEFAULT_CHAT_FRAME
    if type(JoinPermanentChannel) ~= "function"
        or not (frame and frame.GetID and frame.AddMessage) then
        if utils then
            utils:Print("warn", "/join can't be executed through Yapper; use the Blizzard chat box instead.")
        end
        return
    end

    -- Same argument parsing as Blizzard's JOIN handler.
    local rest = text:match("^%s*/%S+%s*(.-)%s*$") or ""
    local name = rest:match("^%s*([^%s]+)") or ""
    local password = rest:match("^%s*[^%s]+%s*(.-)%s*$") or ""

    local info = ChatTypeInfo and (name ~= "" and ChatTypeInfo["CHANNEL"] or ChatTypeInfo["SYSTEM"])
    if name == "" then
        if info then frame:AddMessage(CHAT_JOIN_HELP, info.r, info.g, info.b, info.id) end
        return
    end

    local ok, zoneChannel, channelName = pcall(JoinPermanentChannel, name, password, frame:GetID(), 1)
    if not ok then
        if utils then
            utils:Print("warn", "/join can't be executed through Yapper right now; use the Blizzard chat box instead.")
        end
    elseif not zoneChannel then
        if info then frame:AddMessage(CHAT_INVALID_NAME_NOTICE, info.r, info.g, info.b, info.id) end
    else
        -- Regional channels re-add to channelList on their YOU_CHANGED
        -- notice and display it normally; for other channels that notice
        -- (and the channel's messages) drop until channelList is rebuilt by
        -- the next UPDATE_CHAT_WINDOWS, so echo the join ourselves.
        local regional = C_ChatInfo and C_ChatInfo.IsChannelRegionalForChannelID
            and C_ChatInfo.IsChannelRegionalForChannelID(zoneChannel)
        if not regional and info then
            local notice = CHAT_YOU_CHANGED_NOTICE or "Changed Channel: [%d. %s]"
            frame:AddMessage(string_format(notice, zoneChannel, channelName or name), info.r, info.g, info.b, info.id)
        end
    end
end

--- Forward an unrecognised slash command to Blizzard.
function EditBox:ForwardSlashCommand(text)
    if not self.OrigEditBox then return end

    local utils  = YapperTable.Utils
    local policy = YapperTable.LockdownPolicy
    local command = text:match("^%s*(/%S+)")

    if policy and command
        and type(policy.IsAlwaysForbiddenSlashCommand) == "function"
        and policy:IsAlwaysForbiddenSlashCommand(command) then
        if utils then
            utils:Print("warn", command .. " can't be executed through Yapper; use the Blizzard chat box instead.")
        end
        return
    end

    -- Commands whose Blizzard handlers persist our text into chat-frame
    -- state are emulated locally instead of forwarded (ForwardJoinChannel).
    if policy and command
        and type(policy.IsEmulatedSlashCommand) == "function"
        and policy:IsEmulatedSlashCommand(command) then
        self:ForwardJoinChannel(text)
        return
    end

    -- Chat lockdown: save draft and handoff. Non-chat restrictions are
    -- deliberately NOT gated here: most commands touch no unit data and
    -- forward fine while secrets exist. Handlers that do read restricted
    -- data (e.g. /invite's GetUnitName) fail inside the pcall'd SendText
    -- and fall back to the same handoff, so nothing errors out.
    if utils and utils:IsChatLockdown() then
        self:HandoffToBlizzard()
        return
    end

    -- During combat lockdown, commands that invoke protected Blizzard APIs
    -- (/m opening the macro frame, /cast, /target, ...) trip "Interface
    -- action blocked" when dispatched through our tainted call. Print an
    -- explanation instead of forwarding.
    if utils and utils:IsCombatLockdown()
        and policy and type(policy.IsProtectedSlashCommand) == "function" then
        if command and policy:IsProtectedSlashCommand(command) then
            utils:Print("warn", command .. " is a protected command and can't be used during combat lockdown.")
            return
        end
    end

    local chosenCT = self:GetResolvedChatType(self.ChatType)
    local eb = self.OrigEditBox
    local overrideCT = CHATTYPE_TO_OVERRIDE_KEY[chosenCT] or chosenCT

    local currentTell = eb:GetAttribute("tellTarget")
    local diffTell = true
    pcall(function() diffTell = (currentTell ~= self.Target) end)

    local diffChannel = (eb:GetAttribute("channelTarget") ~= self.Target)

    eb:SetAttribute("chatType", overrideCT)
    if overrideCT == "WHISPER" or overrideCT == "BN_WHISPER" then
        if diffTell then
            if YapperTable.Utils and YapperTable.Utils:IsSecret(self.Target) then
                -- Secret target: bypass SetAttribute taint by letting
                -- Blizzard parse it via "/r <text>".
                eb:SetAttribute("chatType", "SAY")
                eb:SetAttribute("tellTarget", nil)
                eb:SetAttribute("channelTarget", nil)
                self._ignoreSetText = true
                eb:SetText("/r " .. text)
                self._ignoreSetText = false
                if not SafeSendText(eb) then
                    if utils then
                        utils:Print("warn", (command or "That command") .. " can't run while addon restrictions are active; the draft was saved.")
                    end
                    self:HandoffToBlizzard()
                end
                return
            end
            eb:SetAttribute("tellTarget", self.Target)
        end
        eb:SetAttribute("channelTarget", nil)
    elseif overrideCT == "CHANNEL" then
        eb:SetAttribute("tellTarget", nil)
        if diffChannel then
            eb:SetAttribute("channelTarget", self.Target)
        end
    else
        eb:SetAttribute("tellTarget", nil)
        eb:SetAttribute("channelTarget", nil)
    end
    if self.Language then
        self.OrigEditBox:SetAttribute("language", self.Language)
    else
        self.OrigEditBox:SetAttribute("language", nil)
    end

    self._ignoreSetText = true
    eb:SetText(text)
    self._ignoreSetText = false
    local sendOk = SafeSendText(eb)

    -- SendText may not close the box; clean up if it didn't.
    if self.OrigEditBox:IsShown() then
        self.OrigEditBox:SetText("")
        self.OrigEditBox:Deactivate()
    end

    if not sendOk then
        -- A restriction flipped between the checks and dispatch, so a
        -- Blizzard slash handler hit a secret inside our tainted call. The
        -- overlay still holds the command; HandoffToBlizzard keeps it as a
        -- draft instead of erroring.
        if utils then
            utils:Print("warn", (command or "That command") .. " can't run while addon restrictions are active; the draft was saved.")
        end
        self:HandoffToBlizzard()
    end
end
