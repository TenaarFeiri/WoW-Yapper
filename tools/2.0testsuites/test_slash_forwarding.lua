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

_G.ChatEdit_SendText = NativeParseAndSend
_G.strtrim = function(value)
    return (value or ""):match("^%s*(.-)%s*$")
end

local handedOff = false
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
        IsSecret = function() return false end,
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
_G.C_ChatInfo = {
    PerformEmote = function(token, message)
        forwardedText = token .. ":" .. message
    end,
}
_G.ChatFrameUtil = {}

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

print("\nTest 5: native cleanup is preserved")
nativeShown = true
YapperTable.EditBox:ForwardSlashCommand("/reload")
check("native editbox is cleaned after forwarding", nativeDeactivateCalls == 1 and nativeText == "")
nativeShown = false

print("\nTest 6: lockdown remains handed off")
YapperTable.Utils.IsChatLockdown = function() return true end
YapperTable.EditBox:ForwardSlashCommand("/reload")
check("lockdown hands control to Blizzard", handedOff == true)

print(("\nResults: %d/%d passed"):format(TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    os.exit(1)
end
print("All slash forwarding tests passed.")
