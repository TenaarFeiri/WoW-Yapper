#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_state.lua  --  State machine module unit tests
-- Run from the repo root:  lua tools/2.0testsuites/test_state.lua
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
_G.date = os.date

-- C_Timer stub: capture scheduled callbacks.
local timerCallbacks = {}
_G.C_Timer = {
    After = function(sec, fn)
        timerCallbacks[#timerCallbacks + 1] = fn
    end,
}
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

-- API event stub.
local firedEvents = {}

local YapperName = "Yapper"
local YapperTable = {
    Config = { System = { DEBUG = false, VERBOSE = false } },
    Error = {
        PrintError = function(self, code, ...) end,
    },
    API = {
        Fire = function(self, event, ...)
            firedEvents[#firedEvents + 1] = { event = event, args = { ... } }
        end,
    },
}

-- Load State.lua
local loader, err = loadfile("Src/State.lua")
if not loader then
    print("FATAL: " .. tostring(err))
    os.exit(1)
end
loader(YapperName, YapperTable)

local State = YapperTable.State

-- ===========================================================================
-- Test 1: Initial state
-- ===========================================================================
print("\nTest 1: Initial state")

check("starts in INITIALISING", State:Get() == "INITIALISING")
check("IsInitialising true", State:IsInitialising())
check("IsInitialised false", not State:IsInitialised())
check("IsIdle false", not State:IsIdle())

-- ===========================================================================
-- Test 2: Basic transitions
-- ===========================================================================
print("\nTest 2: Basic transitions")

State:Transition("IDLE")
check("transition to IDLE", State:Get() == "IDLE")
check("IsIdle true", State:IsIdle())
check("IsInitialised true", State:IsInitialised())

State:Transition("EDITING")
check("transition to EDITING", State:Get() == "EDITING")
check("IsEditing true", State:IsEditing())
check("IsIdle false after transition", not State:IsIdle())

State:Transition("MULTILINE")
check("transition to MULTILINE", State:Get() == "MULTILINE")
check("IsMultiline true", State:IsMultiline())

State:Transition("SENDING")
check("transition to SENDING", State:Get() == "SENDING")
check("IsSending true", State:IsSending())

State:Transition("STALLED")
check("transition to STALLED", State:Get() == "STALLED")
check("IsStalled true", State:IsStalled())

State:Transition("LOCKDOWN")
check("transition to LOCKDOWN", State:Get() == "LOCKDOWN")
check("IsLockdown true", State:IsLockdown())

State:Transition("CONFIG")
check("transition to CONFIG", State:Get() == "CONFIG")
check("IsConfig true", State:IsConfig())

-- ===========================================================================
-- Test 3: No-op on same state
-- ===========================================================================
print("\nTest 3: No-op transition to same state")

firedEvents = {}
State:Transition("CONFIG")  -- already in CONFIG
check("no event fired on same-state", #firedEvents == 0)
check("state unchanged", State:Get() == "CONFIG")

-- ===========================================================================
-- Test 4: Invalid state rejected
-- ===========================================================================
print("\nTest 4: Invalid state rejection")

State:Transition("IDLE")
State:Transition("INVALID_STATE")
check("invalid transition keeps current state", State:Get() == "IDLE")

-- ===========================================================================
-- Test 5: Semantic transition helpers
-- ===========================================================================
print("\nTest 5: Semantic transition helpers")

State:Transition("INITIALISING")  -- reset

State:ToIdle()
check("ToIdle sets IDLE", State:Get() == "IDLE")

State:ToEditing()
check("ToEditing sets EDITING", State:Get() == "EDITING")

State:ToMultiline()
check("ToMultiline sets MULTILINE", State:Get() == "MULTILINE")

State:ToSending()
check("ToSending sets SENDING", State:Get() == "SENDING")

State:ToStalled()
check("ToStalled sets STALLED", State:Get() == "STALLED")

State:ToLockdown()
check("ToLockdown sets LOCKDOWN", State:Get() == "LOCKDOWN")

State:ToConfig()
check("ToConfig sets CONFIG", State:Get() == "CONFIG")

-- ===========================================================================
-- Test 6: Composite helpers
-- ===========================================================================
print("\nTest 6: Composite state helpers")

State:ToEditing()
check("IsInputActive true in EDITING", State:IsInputActive())
check("IsBusy false in EDITING", not State:IsBusy())

State:ToMultiline()
check("IsInputActive true in MULTILINE", State:IsInputActive())

State:ToSending()
check("IsBusy true in SENDING", State:IsBusy())
check("IsInputActive false in SENDING", not State:IsInputActive())

State:ToStalled()
check("IsBusy true in STALLED", State:IsBusy())

State:ToLockdown()
check("IsBusy true in LOCKDOWN", State:IsBusy())

State:ToIdle()
check("IsBusy false in IDLE", not State:IsBusy())
check("IsInputActive false in IDLE", not State:IsInputActive())

-- ===========================================================================
-- Test 7: Reset
-- ===========================================================================
print("\nTest 7: Reset")

State:ToSending()
check("in SENDING before reset", State:IsSending())
State:Reset()
check("reset goes to IDLE", State:IsIdle())

-- ===========================================================================
-- Test 8: API events fire on transition
-- ===========================================================================
print("\nTest 8: STATE_CHANGED events")

firedEvents = {}
State:ToEditing()
check("event fired", #firedEvents == 1)
check("event name is STATE_CHANGED", firedEvents[1].event == "STATE_CHANGED")
check("new state in args", firedEvents[1].args[1] == "EDITING")
check("old state in args", firedEvents[1].args[2] == "IDLE")

-- ===========================================================================
-- Test 9: Logging
-- ===========================================================================
print("\nTest 9: State logging")

-- Clear log by resetting the internal buffer.
State._logBuffer = {}
State:ToIdle()
State:ToSending()
State:ToIdle()

check("log count matches transitions", State:GetLogCount() == 3)
local log1 = State:GetLog(1)
check("first log old state", log1.old == "EDITING")
check("first log new state", log1.new == "IDLE")
check("log has time", log1.time ~= nil)

local log2 = State:GetLog(2)
check("second log old state", log2.old == "IDLE")
check("second log new state", log2.new == "SENDING")

local allLogs = State:GetLogs()
check("GetLogs returns all entries", #allLogs == 3)

-- ===========================================================================
-- Test 10: Log buffer max size (circular)
-- ===========================================================================
print("\nTest 10: Log buffer max size")

State._logBuffer = {}
for i = 1, 250 do
    if State:IsIdle() then
        State:ToEditing()
    else
        State:ToIdle()
    end
end
check("log buffer capped at MAX_LOGS", State:GetLogCount() <= State.MAX_LOGS)

-- ===========================================================================
-- Test 11: Flags (session and persistent)
-- ===========================================================================
print("\nTest 11: State flags")

check("unset flag returns default", State:GetFlag("testFlag", 42) == 42)

State:SetFlag("testFlag", "hello")
check("session flag set", State:GetFlag("testFlag") == "hello")

State:SetFlag("testFlag", nil)
check("nil flag returns default", State:GetFlag("nilFlag", "fallback") == "fallback")

-- Persistent flag stored in config.
YapperTable.Config.System.StateFlags = nil
State:SetFlag("persistentFlag", true, true)
check("persistent flag set in config",
    YapperTable.Config.System.StateFlags and YapperTable.Config.System.StateFlags.persistentFlag == true)

-- Session flag takes precedence over config.
YapperTable.Config.System.StateFlags = { fromConfig = "configValue" }
State._flags.fromConfig = "sessionValue"
check("session flag overrides config", State:GetFlag("fromConfig") == "sessionValue")

-- Config flag used when session doesn't have it.
State._flags.fromConfig = nil
check("config flag used as fallback", State:GetFlag("fromConfig") == "configValue")

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
