#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_queue_stall.lua  —  Queue stall recovery & policy test suite
-- Run from the repo root:  lua tools/2.0testsuites/test_queue_stall.lua
-- ---------------------------------------------------------------------------
-- Coverage:
--   1. Normal ack-driven delivery (auto-continue policies)
--   2. Stall timeout → Continue prompt shown → manual resume → delivery completes
--   3. QUEUE_STALL and QUEUE_COMPLETE callbacks fire at the right moments
--   4. GetQueueState() reflects stalled/active/pending correctly
--   5. CancelQueue() discards entries and fires QUEUE_COMPLETE
--   6. OPEN_WORLD_LOCAL (promptEveryChunk) requires hardware event from the start
--   7. INSTANCE_LOCAL auto-continues but stall-recovers via prompt (same path)
-- ---------------------------------------------------------------------------

local PASS, FAIL = "PASS", "FAIL"
local TESTS, FAILURES = 0, 0

local function check(label, condition)
    TESTS = TESTS + 1
    if condition then
        print("  [" .. PASS .. "] " .. label)
    else
        FAILURES = FAILURES + 1
        print("  [" .. FAIL .. "] " .. label)
        -- Uncomment for stack traces during development:
        -- error("FAILED: " .. label, 2)
    end
end

-- ===========================================================================
-- Minimal WoW environment mock
-- ===========================================================================

_G = _G or {}

-- Controllable timer: we drive it manually instead of real time.
local pendingTimers = {}
_G.C_Timer = {
    NewTimer = function(duration, callback)
        local t = { duration = duration, callback = callback, _cancelled = false }
        t.Cancel = function(self) self._cancelled = true end
        pendingTimers[#pendingTimers + 1] = t
        return t
    end,
    After = function(duration, callback)
        local t = { duration = duration, callback = callback, _cancelled = false }
        t.Cancel = function(self) self._cancelled = true end
        pendingTimers[#pendingTimers + 1] = t
        return t
    end,
}

local function FireAllTimers()
    local batch = pendingTimers
    pendingTimers = {}
    for _, t in ipairs(batch) do
        if not t._cancelled then
            t.callback()
        end
    end
end

_G.GetTime = function() return 0 end
_G.UnitGUID = function() return "Player-1-AABBCCDD" end
_G.IsInInstance = function() return false end  -- open world by default

-- Minimal frame factory (no real rendering needed).
local function MockFrame()
    local f = {}
    f.shown = false
    f.scripts = {}
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:GetParent() return _G.UIParent end
    function f:SetParent(p) end
    function f:GetNumPoints() return 0 end
    function f:ClearAllPoints() end
    function f:SetPoint(...) end
    function f:SetSize(...) end
    function f:SetFrameStrata(...) end
    function f:SetBackdrop(...) end
    function f:SetBackdropColor(...) end
    function f:SetBackdropBorderColor(...) end
    function f:SetScript(evt, fn) self.scripts[evt] = fn end
    function f:EnableKeyboard(...) end
    function f:SetPropagateKeyboardInput(...) end
    function f:CreateFontString()
        local fs = { text = "" }
        function fs:SetPoint(...) end
        function fs:SetJustifyH(...) end
        function fs:SetTextColor(...) end
        function fs:SetWordWrap(...) end
        function fs:SetText(t) self.text = t end
        function fs:GetText() return self.text end
        function fs:SetFont(...) end
        return fs
    end
    return f
end

_G.UIParent = MockFrame()
_G.CreateFrame = function(frameType, name, parent, template)
    return MockFrame()
end
_G.hooksecurefunc = function(tbl, name, fn)
    local orig = tbl[name]
    tbl[name] = function(...) orig(...); fn(...) end
end
_G.ChatFrameUtil = { OpenChat = function() end }
_G.ChatFrame1EditBox = MockFrame()
_G.FrameUtil = nil   -- not needed
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) end }

-- ===========================================================================
-- Build YapperTable with stubs
-- ===========================================================================

local YapperTable = {}

-- Config
YapperTable.Config = { Chat = { STALL_TIMEOUT = 1.5 } }

-- Utils stub
YapperTable.Utils = {
    IsChatLockdown  = function() return false end,
    GetChatParent   = function() return _G.UIParent end,
    MakeFullscreenAware = function() end,
    DebugPrint      = function(_, ...) end,
    Print           = function(_, msg) end,
}

-- Events stub (Queue:Init registers chat events; we capture them so we can
-- fire them manually to simulate server acks).
local registeredEvents = {}
YapperTable.Events = {
    Register = function(_, scope, event, fn, key)
        registeredEvents[event] = fn
    end,
}

local unpack = table.unpack or unpack

local function SimulateAckEvent(event, text, ...)
    -- arg1=text, rest varies; arg12=GUID for local echoes
    -- Pack as Queue:OnChatEvent expects: (event, text, arg2..arg11, guid, ...)
    local args = { text }
    for i = 2, 11 do args[i] = nil end
    args[12] = _G.UnitGUID()   -- player GUID → passes the GUID check
    if registeredEvents[event] then
        registeredEvents[event](unpack(args, 1, 12))
    end
end

-- Router stub: captures sends for inspection.
local sentMessages = {}
YapperTable.Router = {
    Send = function(self, text, chatType, lang, target)
        sentMessages[#sentMessages + 1] = { text=text, type=chatType }
        return true
    end,
    DetectCommunityChannel = function() return false end,
}

-- EditBox stub (needed by ShowContinuePrompt)
YapperTable.EditBox = { Overlay = MockFrame() }

-- Load Queue.lua
local loader, err = loadfile("Src/Queue.lua")
if not loader then
    print("FATAL: " .. tostring(err))
    os.exit(1)
end
loader("Yapper", YapperTable)
local Queue = YapperTable.Queue

-- Load API.lua so QUEUE_STALL/QUEUE_COMPLETE callbacks work.
local api_loader, aerr = loadfile("Src/API.lua")
if not api_loader then
    print("FATAL: " .. tostring(aerr))
    os.exit(1)
end
api_loader("Yapper", YapperTable)
local YapperAPI = _G.YapperAPI

-- Wire Queue → API for the Fire calls.
-- (In production Yapper.lua does this; in tests we do it here.)

local function ResetAll()
    pendingTimers = {}
    sentMessages  = {}
    registeredEvents = {}
    Queue:Reset()
    Queue:Init()  -- re-registers events
end

Queue:Init()

-- ===========================================================================
-- Test helpers
-- ===========================================================================

local function EnqueueSAY(chunks)
    for _, text in ipairs(chunks) do
        Queue.Entries[#Queue.Entries + 1] = { text=text, type="SAY", lang="Common", target=nil }
    end
end

local function EnqueueGROUP(chunks, chatType)
    for _, text in ipairs(chunks) do
        Queue.Entries[#Queue.Entries + 1] = { text=text, type=chatType or "PARTY", lang="Common", target=nil }
    end
end

-- ===========================================================================
-- 1. Normal ack-driven delivery — INSTANCE_LOCAL auto-continues
-- ===========================================================================
print("\nTest 1: INSTANCE_LOCAL auto-continue (ack arrives in time)")

_G.IsInInstance = function() return true end  -- → INSTANCE_LOCAL
ResetAll()

local chunks = { "Hello world part one.", "Hello world part two.", "Hello world part three." }
EnqueueSAY(chunks)
Queue:Flush(false)  -- no hardware event needed for INSTANCE_LOCAL

-- First chunk should be in-flight
check("Queue active after Flush", Queue.Active == true)
check("First chunk sent", #sentMessages == 1 and sentMessages[1].text == chunks[1])
check("PendingEntry set", Queue.PendingEntry ~= nil)

-- Simulate server echo for chunk 1
SimulateAckEvent("CHAT_MSG_SAY", chunks[1])
check("Chunk 1 acked: chunk 2 now in-flight", #sentMessages == 2)
check("No stall prompt after clean ack", Queue.ContinueFrame == nil or not Queue.ContinueFrame.shown)

SimulateAckEvent("CHAT_MSG_SAY", chunks[2])
check("Chunk 2 acked: chunk 3 now in-flight", #sentMessages == 3)

SimulateAckEvent("CHAT_MSG_SAY", chunks[3])
check("All chunks delivered, queue inactive", Queue.Active == false)
check("No entries remain", #Queue.Entries == 0)

-- ===========================================================================
-- 2. Stall timeout → Continue prompt → manual resume
-- ===========================================================================
print("\nTest 2: INSTANCE_LOCAL stall → Continue prompt → manual resume")

_G.IsInInstance = function() return true end
ResetAll()

local stallCallbacks = {}
YapperAPI:RegisterCallback("QUEUE_STALL", function(chatType, policyClass, remaining)
    stallCallbacks[#stallCallbacks + 1] = { chatType=chatType, policyClass=policyClass, remaining=remaining }
end)

local completeCount = 0
YapperAPI:RegisterCallback("QUEUE_COMPLETE", function()
    completeCount = completeCount + 1
end)

EnqueueSAY({ "Chunk A.", "Chunk B." })
Queue:Flush(false)
check("Chunk A sent immediately", #sentMessages == 1)

-- Don't ack — let the stall timer fire
FireAllTimers()

check("Stall prompt shown", Queue.ContinueFrame ~= nil and Queue.ContinueFrame.shown)
check("NeedsContinue = true", Queue.NeedsContinue == true)
check("Stalled chunk re-queued", #Queue.Entries == 2)  -- A back + B still waiting
check("QUEUE_STALL fired", #stallCallbacks == 1)
check("QUEUE_STALL chatType = SAY", stallCallbacks[1].chatType == "SAY")
check("QUEUE_STALL policyClass = INSTANCE_LOCAL", stallCallbacks[1].policyClass == "INSTANCE_LOCAL")
check("QUEUE_STALL remaining = 2", stallCallbacks[1].remaining == 2)

local stateStalled = YapperAPI:GetQueueState()
check("GetQueueState: stalled = true", stateStalled.stalled == true)
check("GetQueueState: pending = 2", stateStalled.pending == 2)
check("GetQueueState: active = true", stateStalled.active == true)

-- User presses Enter → OnOpenChat fires
Queue:OnOpenChat()
-- Prompt is hidden by HandleAck, not OnOpenChat itself — just check delivery resumes.
check("Chunk A re-sent", #sentMessages == 2)

SimulateAckEvent("CHAT_MSG_SAY", "Chunk A.")
check("Chunk B sent after ack", #sentMessages == 3)

SimulateAckEvent("CHAT_MSG_SAY", "Chunk B.")
check("Queue complete after all acks", Queue.Active == false)
check("QUEUE_COMPLETE fired once", completeCount == 1)

-- ===========================================================================
-- 3. OPEN_WORLD_LOCAL requires hardware event from the start
-- ===========================================================================
print("\nTest 3: OPEN_WORLD_LOCAL requires hardware event on every chunk")

_G.IsInInstance = function() return false end  -- open world
ResetAll()

local promptShownCount = 0
local origShow = Queue.ShowContinuePrompt
Queue.ShowContinuePrompt = function(self)
    promptShownCount = promptShownCount + 1
    origShow(self)
end

EnqueueSAY({ "Open world chunk 1.", "Open world chunk 2." })
Queue:Flush(false)  -- no hardware event → should prompt immediately

check("Prompt shown without hardware event (open world)", promptShownCount == 1)
check("No message sent yet", #sentMessages == 0)
check("Queue still has both entries", #Queue.Entries == 2)

-- Simulate hardware event via OnOpenChat
Queue:OnOpenChat()
check("Chunk 1 sent after hardware event", #sentMessages == 1)

SimulateAckEvent("CHAT_MSG_SAY", "Open world chunk 1.")
check("Prompt shown again for chunk 2", promptShownCount == 2)

Queue:OnOpenChat()
check("Chunk 2 sent after second hardware event", #sentMessages == 2)

SimulateAckEvent("CHAT_MSG_SAY", "Open world chunk 2.")
check("Queue complete (open world)", Queue.Active == false)

Queue.ShowContinuePrompt = origShow  -- restore

-- ===========================================================================
-- 4. CancelQueue via API
-- ===========================================================================
print("\nTest 4: CancelQueue() via YapperAPI")

_G.IsInInstance = function() return true end
ResetAll()

local cancelCompleteCount = 0
YapperAPI:RegisterCallback("QUEUE_COMPLETE", function()
    cancelCompleteCount = cancelCompleteCount + 1
end)

EnqueueSAY({ "Cancel me 1.", "Cancel me 2.", "Cancel me 3." })
Queue:Flush(false)
check("Queue active before cancel", Queue.Active == true)

local discarded = YapperAPI:CancelQueue()
check("CancelQueue returns 3 (1 in-flight + 2 pending)", discarded == 3)
check("Queue inactive after cancel", Queue.Active == false)
check("QUEUE_COMPLETE fired on cancel", cancelCompleteCount == 1)

-- ===========================================================================
-- 5. GROUP policy (PARTY) — auto-continue, no hardware event
-- ===========================================================================
print("\nTest 5: GROUP policy auto-continue (PARTY)")

_G.IsInInstance = function() return false end
ResetAll()

EnqueueGROUP({ "Party line 1.", "Party line 2." }, "PARTY")
Queue:Flush(false)
check("Party chunk 1 sent", #sentMessages == 1)

SimulateAckEvent("CHAT_MSG_PARTY", "Party line 1.")
check("Party chunk 2 sent after ack", #sentMessages == 2)

SimulateAckEvent("CHAT_MSG_PARTY", "Party line 2.")
check("Party queue complete", Queue.Active == false)

-- ===========================================================================
-- 6. GetQueueState when queue is idle
-- ===========================================================================
print("\nTest 6: GetQueueState when idle")

ResetAll()
local idle = YapperAPI:GetQueueState()
check("Idle: active = false", idle.active == false)
check("Idle: stalled = false", idle.stalled == false)
check("Idle: pending = 0", idle.pending == 0)
check("Idle: inFlight = 0", idle.inFlight == 0)
check("Idle: expectedAckEvent not exposed", idle.expectedAckEvent == nil)

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
