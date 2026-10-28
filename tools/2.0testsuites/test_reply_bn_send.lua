#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_reply_bn_send.lua — BN whisper reply send-path regression tests
-- Run from the repo root:  lua tools/2.0testsuites/test_reply_bn_send.lua
--
-- Regression: a bnet whisper typed in the overlay after opening a reply
-- tell with the reply keybind did nothing on Enter. Blizzard's remembered
-- BN tell target is a "|K" presence token (or a secret value under addon
-- restrictions); ResolveWhisperTarget preferred it over the usable
-- ReplyQueue-sourced target, so the token either failed Router's
-- friend-list scan (didSend=false -> silent no-op, box stays open) or
-- errored the handler outright on a secret boolean test. The send path
-- now resolves the remembered BN target through BNet_GetBNetIDAccount —
-- the same C call Blizzard's own SendText uses — and never boolean-tests
-- the remembered value before checking its plain-string type tag.
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
-- Minimal WoW environment mock (same shape as test_whisper_tab_target.lua)
-- ===========================================================================

_G.date = os.date
_G.GetTime = function() return 100 end
_G.UnitGUID = function() return "Player-1-AABBCCDD" end
_G.IsInGroup = function() return false end
_G.IsInRaid = function() return false end
_G.IsInGuild = function() return false end
_G.IsInInstance = function() return false end
_G.LE_PARTY_CATEGORY_HOME = 1
_G.LE_PARTY_CATEGORY_INSTANCE = 2

_G.InCombatLockdown = function() return false end
_G.C_ChatInfo = { InChatMessagingLockdown = function() return false end }

-- A sentinel standing in for a genuine secret value: IsSecret's issecretvalue
-- path flags it, and nothing may compare/boolean-test it safely.
local SECRET = {}
_G.issecretvalue = function(value) return value == SECRET end
_G.canaccessvalue = function(value) return value ~= SECRET end
_G.issecrettable = function(value) return value == SECRET end
_G.canaccesstable = function(value) return value ~= SECRET end

-- Mutable Blizzard remembered-tell stores.
local tell = { target = nil, ctype = nil, err = nil }
local told = { target = nil, ctype = nil, err = nil }

_G.ChatFrameUtil = {
    GetLastTellTarget = function()
        if tell.err then error(tell.err) end
        return tell.target, tell.ctype
    end,
    GetLastToldTarget = function()
        if told.err then error(told.err) end
        return told.target, told.ctype
    end,
    SetLastToldTarget = function() end,
    SetChatFocusOverride = function() end,
    ClearChatFocusOverride = function() end,
    DeactivateChat = function() end,
    OpenChat = function() end,
}

-- The C API consumes |K tokens/secrets Lua can't read and returns the ID.
_G.BNet_GetBNetIDAccount = function(token)
    if token == "|Kf42|k" then return 42 end
    if token == "|Kf99|k" then return 99 end
    return nil
end

local sentWhispers = {}
_G.C_BattleNet = {
    GetAccountInfoByID = function(id)
        if id == 42 then return { accountName = "Carol" } end
        return nil
    end,
    SendWhisper = function(id, msg)
        sentWhispers[#sentWhispers + 1] = { id = id, msg = msg }
        return true
    end,
}

_G.C_Timer = {
    NewTimer = function() return { Cancel = function() end } end,
    NewTicker = function() return { Cancel = function() end } end,
    After = function() end,
}

-- ===========================================================================
-- Build YapperTable and load the real modules
-- ===========================================================================

local YapperTable = {}

YapperTable.Config = { System = { DEBUG = false }, EditBox = {} }
YapperTable.Core = { GetCharacterLanguage = function(_, v) return v end }
YapperTable.Error = {
    Throw = function(_, key) error(key) end,
    PrintError = function() end,
}

local function loadModule(path)
    local loader, err = loadfile(path)
    if not loader then
        print("FATAL: cannot load " .. path .. ": " .. tostring(err))
        os.exit(1)
    end
    loader("Yapper", YapperTable)
end

loadModule("Src/Utils.lua")
YapperTable.Utils.Print = function() end
YapperTable.Utils.DebugPrint = function() end
YapperTable.Utils.VerbosePrint = function() end

loadModule("Src/EditBox.lua")
loadModule("Src/Router.lua")

local EditBox = YapperTable.EditBox
local Router = YapperTable.Router

-- ===========================================================================
-- 1. ResolveWhisperTarget — BN_WHISPER remembered targets
-- ===========================================================================
print("\nTest 1: ResolveWhisperTarget — BN_WHISPER")

tell.target, tell.ctype = "|Kf42|k", "BN_WHISPER"
local target, secure = EditBox:ResolveWhisperTarget("BN_WHISPER", "tell", "Carol")
check("|K remembered target resolves to account ID",
    target == 42 and secure == true)

tell.ctype = "WHISPER"
target, secure = EditBox:ResolveWhisperTarget("BN_WHISPER", "tell", "Carol")
check("remembered type mismatch keeps the fallback",
    target == "Carol" and secure == false)

tell.ctype = "BN_WHISPER"
tell.err = "attempt to compare secret value"
target, secure = EditBox:ResolveWhisperTarget("BN_WHISPER", "tell", "Carol")
check("erroring remembered list keeps the fallback",
    target == "Carol" and secure == false)
tell.err = nil
tell.target = "|Kf42|k"

local realResolve = _G.BNet_GetBNetIDAccount
_G.BNet_GetBNetIDAccount = function() return nil end
target, secure = EditBox:ResolveWhisperTarget("BN_WHISPER", "tell", "Carol")
check("unresolvable token falls back to Yapper target",
    target == "Carol" and secure == false)
_G.BNet_GetBNetIDAccount = realResolve

told.target, told.ctype = "|Kf99|k", "BN_WHISPER"
target, secure = EditBox:ResolveWhisperTarget("BN_WHISPER", "told", 99)
check("told source resolves remembered token",
    target == 99 and secure == true)

-- ===========================================================================
-- 2. ResolveWhisperTarget — WHISPER remembered targets
-- ===========================================================================
print("\nTest 2: ResolveWhisperTarget — WHISPER")

tell.target, tell.ctype = "Alice", "WHISPER"
target, secure = EditBox:ResolveWhisperTarget("WHISPER", "tell", "Bob")
check("plain remembered name wins", target == "Alice" and secure == true)

tell.target = SECRET
target, secure = EditBox:ResolveWhisperTarget("WHISPER", "tell", "Bob")
check("secret remembered target falls back without erroring",
    target == "Bob" and secure == false)

tell.target, tell.ctype = nil, nil
target, secure = EditBox:ResolveWhisperTarget("WHISPER", "tell", "Bob")
check("empty remembered list keeps the fallback",
    target == "Bob" and secure == false)

-- ===========================================================================
-- 3. Reply-target readers — BN |K/secret recovery
-- ===========================================================================
print("\nTest 3: reply-target readers recover BN |K entries")

EditBox.ReplyQueue = {}
tell.target, tell.ctype = "|Kf42|k", "BN_WHISPER"
local ctype, tgt = EditBox.GetLastTellTargetInfo()
check("|K tell entry recovers the account name",
    ctype == "BN_WHISPER" and tgt == "Carol")

tell.target = "|Kf99|k"
ctype, tgt = EditBox.GetLastTellTargetInfo()
check("|K tell entry without a name falls back to the ID",
    ctype == "BN_WHISPER" and tgt == 99)

ctype, tgt = EditBox.GetLastToldTargetInfo()
check("|K told entry recovers the account ID",
    ctype == "BN_WHISPER" and tgt == 99)

tell.target, tell.ctype = SECRET, "WHISPER"
ctype, tgt = EditBox.GetLastTellTargetInfo()
check("secret WHISPER entry still yields no target",
    ctype == nil and tgt == nil)

-- ===========================================================================
-- 4. Router:Send — BN_WHISPER token and numeric targets
-- ===========================================================================
print("\nTest 4: Router:Send — BN_WHISPER targets")

sentWhispers = {}
local okSend = Router:Send("hello", "BN_WHISPER", nil, "|Kf42|k")
check("|K token sends via C_BattleNet.SendWhisper",
    okSend == true and sentWhispers[1] and sentWhispers[1].id == 42)

sentWhispers = {}
okSend = Router:Send("hello", "BN_WHISPER", nil, 42)
check("numeric account ID still sends",
    okSend == true and sentWhispers[1] and sentWhispers[1].id == 42)

sentWhispers = {}
okSend = Router:Send("hello", "BN_WHISPER", nil, "|Kfunresolvable|k")
check("unresolvable target still fails closed",
    okSend == false and #sentWhispers == 0)

-- ===========================================================================
-- Summary
-- ===========================================================================
print(string.rep("-", 60))
print(string.format("Results: %d/%d passed", TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    print(FAILURES .. " FAILURE(S)")
    os.exit(1)
else
    print("All tests passed!")
end
