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

-- ---------------------------------------------------------------------------
-- Slash command forwarding
-- ---------------------------------------------------------------------------

-- Dispatch SendText on Blizzard's editbox without letting a secret-value
-- error inside Blizzard's slash handlers escape our tainted call (e.g.
-- /invite → GetUnitName compares a secret realm under active restrictions).
local function SafeSendText(editBox)
    return pcall(editBox.SendText, editBox)
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

    -- If chat is locked down (combat/m+ lockdown), save draft and handoff.
    -- Non-chat restrictions are deliberately NOT gated here: most commands
    -- (ready check, countdown, emotes, ...) touch no unit data and forward
    -- fine even while secrets exist. Handlers that do read restricted data
    -- (e.g. /invite's GetUnitName) fail inside the pcall'd SendText below
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
                -- Bypass SetAttribute taint by letting Blizzard cleanly parse the target.
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

    -- Clean up in case SendText didn't close it.
    if self.OrigEditBox:IsShown() then
        self.OrigEditBox:SetText("")
        self.OrigEditBox:Deactivate()
    end

    if not sendOk then
        -- A restriction flipped between the checks above and dispatch, and a
        -- Blizzard slash handler hit a secret value inside our tainted call.
        -- The overlay still holds the command, so HandoffToBlizzard keeps it
        -- as a draft instead of erroring out.
        if utils then
            utils:Print("warn", (command or "That command") .. " can't run while addon restrictions are active; the draft was saved.")
        end
        self:HandoffToBlizzard()
    end
end
