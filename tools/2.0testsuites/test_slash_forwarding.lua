#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_slash_forwarding.lua  —  direct Blizzard slash-handler dispatch
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

_G.strtrim = function(value)
    return (value or ""):match("^%s*(.-)%s*$")
end

local imported = 0
local YapperTable = {
    EditBox = {
        OrigEditBox = {
            SetAttribute = function() error("native attribute write") end,
            SetText = function() error("native text write") end,
            Deactivate = function() error("native deactivation") end,
        },
        ChatType = "SAY",
        Target = nil,
        GetResolvedChatType = function(_, chatType) return chatType end,
    },
    Utils = {
        IsChatLockdown = function() return false end,
        VerbosePrint = function() end,
    },
    EditBoxHooksCore = {},
}

_G.ChatFrameUtil = {
    ImportAllListsToHash = function() imported = imported + 1 end,
}
_G.hash_SlashCmdList = {}

local loader, err = loadfile("Src/Hooks/Slash.lua")
assert(loader, err)
loader("Yapper", YapperTable)

local called, receivedArgs
_G.hash_SlashCmdList["/RELOAD"] = function(args)
    called = true
    receivedArgs = args
end

print("Test 1: direct handler dispatch")
local ok, result = pcall(function()
    return YapperTable.EditBox:ForwardSlashCommand("  /reload   ")
end)
check("direct handler succeeds", ok and result == true)
check("Blizzard command tables are imported", imported == 1)
check("registered handler is called", called == true)
check("handler receives trimmed args", receivedArgs == "")

print("\nTest 2: command arguments are preserved")
called = false
_G.hash_SlashCmdList["/RUN"] = function(args)
    called = true
    receivedArgs = args
end
local argsOK, argsResult = pcall(function()
    return YapperTable.EditBox:ForwardSlashCommand("/run  print('test')  ")
end)
check("argument command succeeds", argsOK and argsResult == true)
check("argument handler is called", called == true)
check("arguments are trimmed but preserved", receivedArgs == "print('test')")

print("\nTest 3: native editbox is not used for slash dispatch")
local unknownOK, unknownResult = pcall(function()
    return YapperTable.EditBox:ForwardSlashCommand("/unknown command")
end)
check("missing handler is a clean no-op", unknownOK and unknownResult == false)

print("\nTest 4: handler errors are not swallowed")
_G.hash_SlashCmdList["/BLOCKED"] = function()
    error("blocked by Blizzard")
end
local blockedOK = pcall(function()
    YapperTable.EditBox:ForwardSlashCommand("/blocked")
end)
check("handler errors propagate normally", blockedOK == false)

print(("\nResults: %d/%d passed"):format(TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    os.exit(1)
end
print("All slash forwarding tests passed.")
