-- Shared context for Blizzard hook control modules.

local _, YapperTable = ...
local EditBox = YapperTable.EditBox
local State = YapperTable.State

local Core = YapperTable.EditBoxHooksCore
local CHATTYPE_TO_OVERRIDE_KEY = Core.CHATTYPE_TO_OVERRIDE_KEY
local ResolveChannelName = Core.ResolveChannelName
local UserBypassingYapper = Core.UserBypassingYapper
local SetUserBypassingYapper = Core.SetUserBypassingYapper
local BypassEditBox = Core.BypassEditBox
local SetBypassEditBox = Core.SetBypassEditBox

local type = type
local tonumber = tonumber
local tostring = tostring

local ENABLE_TRIGGER_TRACE = false
local GATE_SKIP_SETTEXT_INTENT_ADOPTION_ON_EXPLICIT = true

local function TriggerTrace(tag, details)
    if not ENABLE_TRIGGER_TRACE then
        return
    end
    print("[Yapper][Trigger] " .. tostring(tag) .. " :: " .. tostring(details or ""))
end

local function StampRecentOpenChatIntent(self, chatType, target)
    self._recentOpenChatIntent = {
        chatType = chatType,
        target = target,
        t = GetTime(),
    }
end

local function ParseLinkType(link)
    if type(link) ~= "string" or link == "" then
        return nil, nil
    end
    local linkType, options = string.match(link, "^([^:]+):?(.*)$")
    if type(linkType) == "string" then
        linkType = string.lower(linkType)
    end
    return linkType, options
end

local Ctl = YapperTable.BlizzardHookCtl or {}
YapperTable.BlizzardHookCtl = Ctl

Ctl.EditBox = EditBox
Ctl.State = State
Ctl.Core = Core
Ctl.CHATTYPE_TO_OVERRIDE_KEY = CHATTYPE_TO_OVERRIDE_KEY
Ctl.ResolveChannelName = ResolveChannelName
Ctl.UserBypassingYapper = UserBypassingYapper
Ctl.SetUserBypassingYapper = SetUserBypassingYapper
Ctl.BypassEditBox = BypassEditBox
Ctl.SetBypassEditBox = SetBypassEditBox
Ctl.TriggerTrace = TriggerTrace
Ctl.StampRecentOpenChatIntent = StampRecentOpenChatIntent
Ctl.ParseLinkType = ParseLinkType
Ctl.GATE_SKIP_SETTEXT_INTENT_ADOPTION_ON_EXPLICIT = GATE_SKIP_SETTEXT_INTENT_ADOPTION_ON_EXPLICIT
