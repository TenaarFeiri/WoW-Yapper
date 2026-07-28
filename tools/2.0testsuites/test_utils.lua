#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_utils.lua  --  Utils module unit tests
-- Run from the repo root:  lua tools/2.0testsuites/test_utils.lua
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

-- ===========================================================================
-- Minimal WoW environment mock
-- ===========================================================================

_G = _G or {}
_G.UIParent = {}
_G.print = print

local YapperName = "Yapper"
local YapperTable = {
    Config = { System = { DEBUG = false, VERBOSE = false } },
    LockdownPolicy = nil,
}

-- Load Utils.lua
local loader, err = loadfile("Src/Utils.lua")
if not loader then
    print("FATAL: " .. tostring(err))
    os.exit(1)
end
loader(YapperName, YapperTable)

local Utils = YapperTable.Utils

-- ===========================================================================
-- Test 1: EnsureTable
-- ===========================================================================
print("\nTest 1: EnsureTable")

check("returns table when given table", type(Utils:EnsureTable({1,2,3})) == "table")
check("preserves existing table", Utils:EnsureTable({1,2,3})[2] == 2)
check("returns empty table for nil", type(Utils:EnsureTable(nil)) == "table")
check("returns empty table for string", type(Utils:EnsureTable("hello")) == "table")
check("returns empty table for number", type(Utils:EnsureTable(42)) == "table")
check("returns empty table for boolean", type(Utils:EnsureTable(true)) == "table")

-- ===========================================================================
-- Test 2: EnsureTablePath
-- ===========================================================================
print("\nTest 2: EnsureTablePath")

local root = {}
local deep = Utils:EnsureTablePath(root, "a", "b", "c")
check("creates nested path", type(root.a) == "table")
check("creates intermediate tables", type(root.a.b) == "table")
check("creates deepest table", type(root.a.b.c) == "table")
check("returns deepest table", deep == root.a.b.c)

-- Setting a value on the returned table should be reflected in root.
deep.value = 42
check("value accessible through root", root.a.b.c.value == 42)

-- Calling again on existing path should not destroy data.
local deep2 = Utils:EnsureTablePath(root, "a", "b", "c")
check("re-traversal preserves data", deep2.value == 42)

-- Single segment path.
local root2 = {}
local single = Utils:EnsureTablePath(root2, "x")
check("single segment works", type(root2.x) == "table")
check("single segment returns table", single == root2.x)

-- nil root should return an empty table (not crash).
local nilRoot = Utils:EnsureTablePath(nil, "a")
check("nil root returns table", type(nilRoot) == "table")

-- Numeric key path.
local root3 = {}
local numPath = Utils:EnsureTablePath(root3, 1, 2)
check("numeric keys work", type(root3[1]) == "table")
check("nested numeric keys work", type(root3[1][2]) == "table")

-- Invalid key type should bail gracefully.
local root4 = { valid = { nested = "data" } }
local invalid = Utils:EnsureTablePath(root4, "valid", true)
check("boolean key returns current table", type(invalid) == "table")

-- ===========================================================================
-- Test 3: AssertType
-- ===========================================================================
print("\nTest 3: AssertType")

check("string matches string type", Utils:AssertType("hello", "string", "") == "hello")
check("number matches number type", Utils:AssertType(42, "number", 0) == 42)
check("table matches table type", type(Utils:AssertType({}, "table", nil)) == "table")
check("nil returns default for string", Utils:AssertType(nil, "string", "default") == "default")
check("number returns default for string type", Utils:AssertType(42, "string", "default") == "default")
check("string returns default for number type", Utils:AssertType("hello", "number", 0) == 0)
check("boolean false returns default for string", Utils:AssertType(false, "string", "nope") == "nope")

-- ===========================================================================
-- Test 4: Deleet
-- ===========================================================================
print("\nTest 4: Deleet (leetspeak reversal)")

check("0 -> o", Utils.Deleet("h3ll0") == "hello")
check("1 -> i", Utils.Deleet("n1ce") == "nice")
check("3 -> e", Utils.Deleet("h3llo") == "hello")
check("4 -> a", Utils.Deleet("4m4zing") == "amazing")
check("5 -> s", Utils.Deleet("5up3r") == "super")
check("7 -> t", Utils.Deleet("7es7") == "test")
check("$ -> s", Utils.Deleet("ca$h") == "cash")
check("! -> i", Utils.Deleet("n!ce") == "nice")
check("+ -> t", Utils.Deleet("+es+") == "test")
check("mixed leet", Utils.Deleet("h4ck3r5") == "hackers")
check("no leet unchanged", Utils.Deleet("normal") == "normal")
check("empty string", Utils.Deleet("") == "")
check("all leet", Utils.Deleet("73$7") == "test")

-- ===========================================================================
-- Test 5: IsSecret
-- ===========================================================================
print("\nTest 5: IsSecret")

check("nil is secret", Utils:IsSecret(nil) == true)
check("false is secret", Utils:IsSecret(false) == true)
check("empty string is secret (whitespace)", Utils:IsSecret("") == true)
check("whitespace-only is secret", Utils:IsSecret("   ") == true)
check("|K token is secret", Utils:IsSecret("some|Ktoken") == true)
check("normal string is not secret", Utils:IsSecret("Hello World") == false)
check("number is not secret", Utils:IsSecret(42) == false)

-- ===========================================================================
-- Test 6: IsChatLockdown / IsCombatLockdown / IsChatOrCombatLockdown
-- ===========================================================================
print("\nTest 6: Lockdown helpers")

-- No LockdownPolicy, no C_ChatInfo, no InCombatLockdown — defaults to false.
YapperTable.LockdownPolicy = nil
_G.C_ChatInfo = nil
_G.InCombatLockdown = nil

check("IsChatLockdown false by default", Utils:IsChatLockdown() == false)
check("IsCombatLockdown false by default", Utils:IsCombatLockdown() == false)
check("IsChatOrCombatLockdown false by default", Utils:IsChatOrCombatLockdown() == false)

-- With C_ChatInfo returning true.
_G.C_ChatInfo = { InChatMessagingLockdown = function() return true end }
check("IsChatLockdown true via C_ChatInfo", Utils:IsChatLockdown() == true)
check("IsChatOrCombatLockdown true when chat locked", Utils:IsChatOrCombatLockdown() == true)

-- With InCombatLockdown returning true.
_G.C_ChatInfo = nil
_G.InCombatLockdown = function() return true end
check("IsCombatLockdown true via InCombatLockdown", Utils:IsCombatLockdown() == true)
check("IsChatOrCombatLockdown true when combat locked", Utils:IsChatOrCombatLockdown() == true)

-- With LockdownPolicy taking precedence.
YapperTable.LockdownPolicy = {
    IsChatLockdown = function() return false end,
    IsCombatLockdown = function() return false end,
    IsChatOrCombatLockdown = function() return false end,
}
check("LockdownPolicy overrides C_ChatInfo", Utils:IsChatLockdown() == false)
check("LockdownPolicy overrides InCombatLockdown", Utils:IsCombatLockdown() == false)

-- ===========================================================================
-- Test 7: Print / DebugPrint / VerbosePrint (smoke test)
-- ===========================================================================
print("\nTest 7: Print functions (smoke test)")

local printCalled = false
local origPrint = print
_G.print = function(...)
    printCalled = true
    origPrint(...)
end

printCalled = false
Utils:Print("test message")
check("Print outputs something", printCalled)

printCalled = false
Utils:Print("info", "test info message")
check("Print with preset works", printCalled)

-- DebugPrint should NOT print when DEBUG is false.
YapperTable.Config.System.DEBUG = false
printCalled = false
Utils:DebugPrint("hidden message")
check("DebugPrint silent when DEBUG=false", not printCalled)

YapperTable.Config.System.DEBUG = true
printCalled = false
Utils:DebugPrint("visible message")
check("DebugPrint prints when DEBUG=true", printCalled)

-- VerbosePrint should NOT print when VERBOSE is false.
YapperTable.Config.System.VERBOSE = false
YapperTable.Config.System.DEBUG = false
printCalled = false
Utils:VerbosePrint("hidden verbose")
check("VerbosePrint silent when VERBOSE=false", not printCalled)

YapperTable.Config.System.VERBOSE = true
printCalled = false
Utils:VerbosePrint("visible verbose")
check("VerbosePrint prints when VERBOSE=true", printCalled)

_G.print = origPrint

-- ===========================================================================
-- Test 8: StripDisplayEscapes
-- ===========================================================================
print("\nTest 8: StripDisplayEscapes")

check("plain text unchanged", Utils:StripDisplayEscapes("hello world") == "hello world")
check("empty string unchanged", Utils:StripDisplayEscapes("") == "")
check("nil returns empty string", Utils:StripDisplayEscapes(nil) == "")
check("non-string returns empty string", Utils:StripDisplayEscapes(42) == "")
check("colour wrap stripped", Utils:StripDisplayEscapes("|cffff0000hello|r") == "hello")
check("colour open stripped mid-text", Utils:StripDisplayEscapes("say |cff00ff00hi|r there") == "say hi there")
check("lowercase hex stripped", Utils:StripDisplayEscapes("|cff1a2b3cx|r") == "x")
check("uppercase hex stripped", Utils:StripDisplayEscapes("|cFF1A2B3Cx|r") == "x")
check("adjacent spans stripped", Utils:StripDisplayEscapes("|cffff0000a|r|cff00ff00b|r") == "ab")
check("bare reset stripped", Utils:StripDisplayEscapes("a|rb") == "ab")
check("named colour stripped", Utils:StripDisplayEscapes("|cnRED:hi|r") == "hi")
check("texture escape stripped", Utils:StripDisplayEscapes("a|TInterface\\x:0|tb") == "ab")
check("atlas escape stripped", Utils:StripDisplayEscapes("a|Aatlas:0|ab") == "ab")
check("hyperlink preserved", Utils:StripDisplayEscapes("|Hitem:1234|h[Link]|h") == "|Hitem:1234|h[Link]|h")
check("coloured hyperlink keeps link, loses colour",
    Utils:StripDisplayEscapes("|cffff0000|Hitem:1|h[L]|h|r") == "|Hitem:1|h[L]|h")
check("idempotent", (function()
    local once = Utils:StripDisplayEscapes("|cffff0000hello|r world")
    return Utils:StripDisplayEscapes(once) == once
end)())
check("realistic recoloured sentence",
    Utils:StripDisplayEscapes("I |cffff3333mispelled|r a |cffff3333wurd|r here")
        == "I mispelled a wurd here")

-- ===========================================================================
-- Results
-- ===========================================================================
print("\n" .. string.rep("-", 50))
print(string.format("Results: %d/%d passed", TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    print(FAILURES .. " FAILURE(S)")
    os.exit(1)
else
    print("All tests passed.")
end
