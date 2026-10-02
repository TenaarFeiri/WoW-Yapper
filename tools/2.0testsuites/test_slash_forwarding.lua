#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_slash_forwarding.lua  —  native Blizzard slash forwarding
-- Run from the repo root: lua tools/2.0testsuites/test_slash_forwarding.lua
-- ---------------------------------------------------------------------------

local PASS, FAIL, TESTS, FAILURES = "PASS", "FAIL", 0, 0

local function check(label, condition)
    TESTS = TESTS + 1
    if condition then
        print("  [" .. PASS .. "] " .. label)
    else
        FAILURES = FAILURES + 1
        print("  [" .. FAIL .. "] " .. label)
    end
end

local attrs = {}
local nativeText = ""
local nativeShown = false
local nativeDeactivateCalls = 0
local forwardedText
local forwardedSecure, forwardedSlash, forwardedEmote

local nativeEditBox = {}
function nativeEditBox:GetAttribute(key) return attrs[key] end
function nativeEditBox:SetAttribute(key, value) attrs[key] = value end
function nativeEditBox:SetText(value) nativeText = value end
function nativeEditBox:GetText() return nativeText end
function nativeEditBox:IsShown() return nativeShown end
function nativeEditBox:Deactivate() nativeDeactivateCalls = nativeDeactivateCalls + 1 end

local function NativeParseAndSend(editBox)
    forwardedText = editBox:GetText()
    local command, args = forwardedText:match("^%s*(/[^%s]+)%s*([%s%S]*)$")
    command = command and command:upper() or ""
    args = (args or ""):match("^%s*(.-)%s*$")

    if hash_SecureCmdList[command] then
        forwardedSecure = command
        hash_SecureCmdList[command](args, editBox)
    elseif hash_SlashCmdList[command] then
        forwardedSlash = command
        hash_SlashCmdList[command](args, editBox)
    elseif hash_EmoteTokenList[command] then
        forwardedEmote = hash_EmoteTokenList[command]
        C_ChatInfo.PerformEmote(forwardedEmote, args)
    end
end

function nativeEditBox:SendText() NativeParseAndSend(self) end
_G.strtrim = function(value)
    return (value or ""):match("^%s*(.-)%s*$")
end
_G.strupper = string.upper

local handedOff = false
local inCombat = false
local printedLine
local YapperTable = {
    EditBox = {
        OrigEditBox = nativeEditBox,
        ChatType = "SAY",
        Target = nil,
        Language = nil,
        GetResolvedChatType = function(_, chatType) return chatType end,
        HandoffToBlizzard = function() handedOff = true end,
    },
    Utils = {
        IsChatLockdown = function() return false end,
        IsCombatLockdown = function() return inCombat end,
        IsSecret = function() return false end,
        Print = function(_, preset, ...)
            printedLine = table.concat({ preset, ... }, " ")
        end,
    },
    EditBoxHooksCore = {
        CHATTYPE_TO_OVERRIDE_KEY = {
            SAY = "SAY",
            EMOTE = "EMOTE",
            CHANNEL = "CHANNEL",
        },
    },
}

_G.hash_SecureCmdList = {}
_G.hash_SlashCmdList = {}
_G.hash_EmoteTokenList = {
    ["/SILLY"] = "SILLY",
}
-- Mirror Blizzard's IsSecureCmd: checks the secure command hash.
_G.IsSecureCmd = function(command)
    return hash_SecureCmdList[strupper(command)] ~= nil
end
-- Localised alias globals used by the slash-command policy tests.
_G.SLASH_MACRO1 = "/macro"
_G.SLASH_MACRO2 = "/m"
_G.SLASH_TARGET1 = "/target"
_G.SLASH_TARGET2 = "/tar"
_G.SLASH_JOIN1 = "/join"
_G.SLASH_JOIN2 = "/channel"
_G.SLASH_JOIN3 = "/chan"
-- Mocks for the emulated /join path (JoinPermanentChannel + frame echo).
local joinCalls = {}
local addedMessages = {}
local joinResult = 7 -- zoneChannel; nil simulates an invalid channel name
_G.JoinPermanentChannel = function(name, password, frameID, hasVoice)
    joinCalls[#joinCalls + 1] = { name = name, password = password, frameID = frameID, hasVoice = hasVoice }
    return joinResult
end
_G.DEFAULT_CHAT_FRAME = {
    GetID = function() return 1 end,
    AddMessage = function(_, msg) addedMessages[#addedMessages + 1] = msg end,
}
_G.ChatTypeInfo = {
    SYSTEM = { r = 1, g = 1, b = 1, id = 0 },
    CHANNEL = { r = 1, g = 1, b = 1, id = 0 },
}
_G.CHAT_JOIN_HELP = "CHAT_JOIN_HELP_TEXT"
_G.CHAT_INVALID_NAME_NOTICE = "CHAT_INVALID_NAME_NOTICE_TEXT"
_G.CHAT_YOU_CHANGED_NOTICE = "Changed Channel: [%d. %s]"
_G.C_ChatInfo = {
    PerformEmote = function(token, message)
        forwardedText = token .. ":" .. message
    end,
    IsChannelRegionalForChannelID = function() return false end,
}
_G.ChatFrameUtil = {}

local policyLoader, policyErr = loadfile("Src/Policies/LockdownPolicy.lua")
assert(policyLoader, policyErr)
policyLoader("Yapper", YapperTable)

local loader, err = loadfile("Src/Hooks/Slash.lua")
assert(loader, err)
loader("Yapper", YapperTable)

local called, receivedArgs, receivedEditBox
_G.hash_SlashCmdList["/RELOAD"] = function(args, editBox)
    called = true
    receivedArgs = args
    receivedEditBox = editBox
end
_G.hash_SecureCmdList["/CAST"] = function(args, editBox)
    forwardedSecure = args
    receivedEditBox = editBox
end

print("Test 1: normal slash command uses native parser")
local ok = pcall(function()
    YapperTable.EditBox:ForwardSlashCommand("/reload   ")
end)
check("forwarding succeeds", ok)
check("native parser receives full command", forwardedText == "/reload   ")
check("registered handler is called", called == true)
check("arguments are trimmed by native parser", receivedArgs == "")
check("handler receives native editbox", receivedEditBox == nativeEditBox)

print("\nTest 2: command arguments are preserved")
called = false
ok = pcall(function()
    YapperTable.EditBox:ForwardSlashCommand("/run  print('test')  ")
end)
check("argument forwarding succeeds", ok)
check("native parser receives arguments", forwardedText == "/run  print('test')  ")

print("\nTest 3: secure commands remain Blizzard-owned")
ok = pcall(function()
    YapperTable.EditBox:ForwardSlashCommand("/cast  Fireball  ")
end)
check("secure command reaches native parser", ok and forwardedSecure == "Fireball")
check("secure handler receives native editbox", receivedEditBox == nativeEditBox)

print("\nTest 4: named emotes remain Blizzard-owned")
ok = pcall(function()
    YapperTable.EditBox:ForwardSlashCommand("/silly  hello  ")
end)
check("named emote reaches native parser", ok and forwardedEmote == "SILLY")
check("named emote keeps message", forwardedText == "SILLY:hello")

print("\nTest 5: permanently forbidden target command is not forwarded")
forwardedText, printedLine = nil, nil
YapperTable.EditBox:ForwardSlashCommand("/target Boss")
check("target command is not forwarded", forwardedText == nil)
check("target command explains the Blizzard fallback", printedLine ~= nil and printedLine:find("Blizzard chat box") ~= nil)

print("\nTest 6: native cleanup is preserved")
nativeShown = true
YapperTable.EditBox:ForwardSlashCommand("/reload")
check("native editbox is cleaned after forwarding", nativeDeactivateCalls == 1 and nativeText == "")
nativeShown = false

print("\nTest 7: lockdown remains handed off")
YapperTable.Utils.IsChatLockdown = function() return true end
YapperTable.EditBox:ForwardSlashCommand("/reload")
check("lockdown hands control to Blizzard", handedOff == true)
YapperTable.Utils.IsChatLockdown = function() return false end

print("\nTest 8: protected non-secure command blocked during combat lockdown")
inCombat = true
forwardedText, printedLine = nil, nil
YapperTable.EditBox:ForwardSlashCommand("/m")
check("/m is not forwarded", forwardedText == nil)
check("/m prints a user-facing explanation", printedLine ~= nil and printedLine:find("/m") ~= nil)

print("\nTest 9: secure command blocked during combat lockdown")
forwardedSecure, forwardedText, printedLine = nil, nil, nil
YapperTable.EditBox:ForwardSlashCommand("/cast Fireball")
check("/cast is not forwarded", forwardedText == nil and forwardedSecure == nil)
check("/cast prints a user-facing explanation", printedLine ~= nil and printedLine:find("/cast") ~= nil)

print("\nTest 10: unprotected command still forwards during combat lockdown")
called, forwardedText = false, nil
YapperTable.EditBox:ForwardSlashCommand("/reload")
check("/reload reaches native parser", forwardedText == "/reload")
check("registered handler is called", called == true)
inCombat = false

print("\nTest 11: protected command forwards normally out of combat")
forwardedText, printedLine = nil, nil
YapperTable.EditBox:ForwardSlashCommand("/m")
check("/m reaches native parser", forwardedText == "/m")
check("no warning is printed", printedLine == nil)

print("\nTest 12: SendText errors are contained and fall back to handoff")
local origSendText = nativeEditBox.SendText
nativeEditBox.SendText = function()
    error("attempt to compare local 'server' (a secret string value)")
end
handedOff, printedLine = false, nil
ok = pcall(function()
    YapperTable.EditBox:ForwardSlashCommand("/invite")
end)
check("secret-compare error is contained", ok == true)
check("handoff preserves the draft", handedOff == true)
check("user-facing warning printed", printedLine ~= nil and printedLine:find("restrictions") ~= nil)
nativeEditBox.SendText = origSendText

print("\nTest 13: /join is emulated via JoinPermanentChannel, never forwarded")
forwardedText, printedLine = nil, nil
joinCalls, addedMessages = {}, {}
YapperTable.EditBox:ForwardSlashCommand("/join somechannel")
check("join does not reach the native parser", forwardedText == nil)
check("join calls JoinPermanentChannel", #joinCalls == 1)
local join = joinCalls[1] or {}
check("join forwards channel name", join.name == "somechannel")
check("join passes empty password", join.password == "")
check("join targets the default frame", join.frameID == 1 and join.hasVoice == 1)
check("non-regional join echoes a confirmation", addedMessages[1] == "Changed Channel: [7. somechannel]")

print("\nTest 14: /channel alias and password are parsed like Blizzard's handler")
forwardedText, printedLine = nil, nil
joinCalls = {}
YapperTable.EditBox:ForwardSlashCommand("/channel  somechannel  s3cret  ")
join = joinCalls[1] or {}
check("channel alias is emulated too", #joinCalls == 1 and forwardedText == nil)
check("alias join forwards channel name", join.name == "somechannel")
check("alias join forwards password", join.password == "s3cret")

print("\nTest 15: /join with no name prints the join help message")
forwardedText, printedLine = nil, nil
joinCalls, addedMessages = {}, {}
YapperTable.EditBox:ForwardSlashCommand("/join")
check("empty join does not call JoinPermanentChannel", #joinCalls == 0)
check("empty join prints join help", addedMessages[1] == "CHAT_JOIN_HELP_TEXT")

print("\nTest 16: invalid channel name prints the invalid-name notice")
joinCalls, addedMessages = {}, {}
joinResult = nil
YapperTable.EditBox:ForwardSlashCommand("/join notachannel")
check("invalid name still calls JoinPermanentChannel", #joinCalls == 1)
check("invalid name prints the notice", addedMessages[1] == "CHAT_INVALID_NAME_NOTICE_TEXT")
joinResult = 7

print(("\nResults: %d/%d passed"):format(TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    os.exit(1)
end
print("All slash forwarding tests passed.")
