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

--- Forward an unrecognised slash command to Blizzard.
function EditBox:ForwardSlashCommand(text)
    if not self.OrigEditBox then return end

    -- If chat is locked down (combat/m+ lockdown), save draft and handoff
    if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
        self:HandoffToBlizzard()
        return
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
                ChatEdit_SendText(eb)
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
    ChatEdit_SendText(eb)

    -- Clean up in case ChatEdit_SendText didn't close it.
    if self.OrigEditBox:IsShown() then
        self.OrigEditBox:SetText("")
        self.OrigEditBox:Deactivate()
    end
end
