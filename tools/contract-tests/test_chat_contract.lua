#!/usr/bin/env lua
-- Master client/server contract tests for Yapper's real Router, Chunking,
-- Queue, and Chat modules. The server is deterministic and intentionally
-- models outcomes, not undocumented production throttle limits.

local Harness = dofile("tools/contract-tests/harness.lua")

local PASS, FAIL = "PASS", "FAIL"
local TESTS, FAILURES = 0, 0

local function check(label, condition)
    TESTS = TESTS + 1
    if condition then
        print("  [" .. PASS .. "] " .. label)
    else
        FAILURES = FAILURES + 1
        print("  [" .. FAIL .. "] " .. label)
    end
end

local function drain(harness, turns)
    for _ = 1, (turns or 8) do
        if #harness.timers == 0 then return end
        harness:fire_timers()
    end
end

local function start_queue(harness, chunks, chatType)
    harness:reset()
    harness:enqueue(chunks, chatType or "EMOTE", "Common", nil)
    harness.Queue:Flush(false)
end

local h = Harness.new()

-- ===========================================================================
-- 1. Router contract matrix
-- ===========================================================================
print("\nContract 1: Router dispatch matrix")

local routerCases = {
    { "SAY", "SAY", nil },
    { "YELL", "YELL", nil },
    { "EMOTE", "EMOTE", nil },
    { "PARTY", "PARTY", nil },
    { "RAID", "RAID", nil },
    { "GUILD", "GUILD", nil },
    { "OFFICER", "OFFICER", nil },
    { "GUILD_DISCORD", "GUILD_DISCORD", nil },
    { "CHANNEL", "CHANNEL", "3" },
    { "WHISPER", "WHISPER", "Target" },
}

for _, case in ipairs(routerCases) do
    h.server:reset()
    local chatType, expectedType, target = case[1], case[2], case[3]
    local ok = h.Router:Send("contract message", chatType, "Common", target)
    local sent = h.server.sent[1]
    check(chatType .. " returns success", ok == true)
    check(chatType .. " preserves chat type", sent and sent.chatType == expectedType)
    check(chatType .. " preserves target", (sent and sent.target) == target)
end

-- Empty whispers must be rejected before reaching the API.
h.server:reset()
check("empty whisper target is rejected", h.Router:Send("message", "WHISPER", nil, "") == false)
check("empty whisper is not dispatched", #h.server.sent == 0)

-- ===========================================================================
-- 2. Message transformation and link contract
-- ===========================================================================
print("\nContract 2: Canonical message and link preservation")

local legacyLink = "look |cffa335ee|Hitem:1234|h[Shiny Sword]|h|r here"
local modernLink = "look |cnIQ4:|Hitem:1234|h[Coiled Serpent Idol]|h|r here"

for _, sample in ipairs({ legacyLink, modernLink }) do
    h.server:reset()
    local ok = h.Chat:SendPosts({ sample }, "SAY", "Common", nil)
    local sent = h.server.sent[1]
    check("link send succeeds: " .. sample:sub(1, 8), ok == true)
    check("link wrapper survives: " .. sample:sub(1, 8), sent and sent.message == sample)
end

local recoloured = "I |cffff3333mispelled|r this"
h.server:reset()
local recolourOK = h.Chat:SendPosts({ recoloured }, "SAY", "Common", nil)
check("standalone display colour is stripped", recolourOK and h.server.sent[1].message == "I mispelled this")

local chunks = h.Chunking:Split("before " .. modernLink .. " after", 255, { useDelineators = false })
check("modern link fits as one atomic chunk", #chunks == 1 and chunks[1]:find(modernLink, 1, true) ~= nil)

local longWithLink = "prefix " .. modernLink .. " " .. string.rep("tail ", 30)
local splitWithLink = h.Chunking:Split(longWithLink, 80, { useDelineators = false })
local linkChunkCount = 0
for _, chunk in ipairs(splitWithLink) do
    if chunk:find(modernLink, 1, true) then linkChunkCount = linkChunkCount + 1 end
    check("chunk respects byte limit", #chunk <= 80)
end
check("long modern link stays whole in one chunk", linkChunkCount == 1)

-- The common Chat pipeline must queue and deliver a multi-chunk post in order.
h:reset()
h.YapperTable.Config.Chat.CHARACTER_LIMIT = 40
local longPost = "one two three four five six seven eight nine ten eleven twelve"
local expectedLongChunks = h.Chunking:Split(longPost, 40, { useDelineators = false })
h.Chat:SendPosts({ longPost }, "EMOTE", "Common", nil)
local expectedChunks = h:sent_count()
check("long Chat post starts delivery", expectedChunks == 1)
while h.Queue:IsActive() do
    drain(h, 1)
end
check("long Chat post delivers multiple chunks", #h.server.sent > 1)
check("long Chat post chunks match real chunker", #h.server.sent == #expectedLongChunks)
check("long Chat post chunks preserve order", (function()
    for i, expected in ipairs(expectedLongChunks) do
        if not h.server.sent[i] or h.server.sent[i].message ~= expected then return false end
    end
    return true
end)())
h.YapperTable.Config.Chat.CHARACTER_LIMIT = 255

h:reset()
local filterHandle = h.YapperAPI:RegisterFilter("PRE_SEND", function(payload)
    payload.text = payload.text .. " [filtered]"
    return payload
end)
h.Chat:SendPosts({ "filter input" }, "SAY", "Common", nil)
check("PRE_SEND filter changes delivered text", h.server.sent[1].message == "filter input [filtered]")
check("history records canonical input before filter", h.history[1] and h.history[1].text == "filter input")
h.YapperAPI:UnregisterFilter(filterHandle)

-- ===========================================================================
-- 3. Queue happy path and ordering
-- ===========================================================================
print("\nContract 3: Queue ordering and acknowledgements")

start_queue(h, { "emote one", "emote two", "emote three" }, "EMOTE")
check("queue sends first chunk", h:sent_count() == 1)
check("queue owns first pending chunk", h.Queue.PendingEntry and h.Queue.PendingEntry.text == "emote one")

drain(h, 1)
check("first echo advances exactly one chunk", h:sent_count() == 2)
check("second chunk is next", h.server.sent[2].message == "emote two")

drain(h, 1)
check("second echo advances exactly one chunk", h:sent_count() == 3)
check("third chunk is next", h.server.sent[3].message == "emote three")

drain(h, 1)
local state = h:queue_state()
check("final echo completes queue", state.pending == 0 and state.inFlight == 0 and not state.active and not state.stalled)

-- ===========================================================================
-- 4. Silent server outcome and recovery contract
-- ===========================================================================
print("\nContract 4: Silent drop becomes one stall and one requeue")

h:reset()
h.server:set_behavior("drop")
h:enqueue({ "drop one", "drop two" }, "EMOTE", "Common", nil)
h.Queue:Flush(false)
-- The first timer is the stall timer because the fake server dropped the echo.
drain(h, 1)
state = h:queue_state()
check("silent drop enters stalled state", state.stalled == true)
check("silent drop requeues the in-flight chunk", #h.Queue.Entries == 2)
check("silent drop does not duplicate-send automatically", h:sent_count() == 1)
check("stall prompt requests continuation", h.Queue.NeedsContinue == true)

-- User continuation is a hardware event; the next send is allowed.
h.server:set_behavior("echo")
h.Queue:OnOpenChat()
check("manual continuation resends the head once", h:sent_count() == 2)
drain(h, 1)
check("requeued chunk acknowledges", h:sent_count() == 3)
drain(h, 1)
check("remaining chunk acknowledges", h:queue_state().pending == 0)

-- ===========================================================================
-- 5. Ack validation contract
-- ===========================================================================
print("\nContract 5: Ack validation and late events")

h:reset()
h.server:set_behavior("wrong-text")
h:enqueue({ "strict text" }, "EMOTE", "Common", nil)
h.Queue.StrictAckMatching = true
h.Queue:Flush(false)
h:fire_next_timer()
check("wrong-text echo does not acknowledge strict queue", h.Queue.PendingEntry ~= nil)
-- Force the stall, then send a late correct echo while stalled.
drain(h, 1)
check("wrong-text echo causes a stall", h.Queue.NeedsContinue == true)
h.Queue.StrictAckMatching = false
h:emit("CHAT_MSG_EMOTE", "strict text", nil, nil, nil, nil, nil, nil, nil, nil, nil, h.playerGUID)
check("late echo is harmless after stall", h.Queue.PendingEntry == nil and h.Queue.NeedsContinue == true)

h:reset()
h.server:set_behavior("wrong-event")
h:enqueue({ "wrong event" }, "EMOTE", "Common", nil)
h.Queue:Flush(false)
h:fire_next_timer()
check("wrong event does not acknowledge pending entry", h.Queue.PendingEntry ~= nil)
drain(h, 1)
check("wrong event eventually stalls", h.Queue.NeedsContinue == true)

-- ===========================================================================
-- 6. Hard API failure contract
-- ===========================================================================
print("\nContract 6: Hard API failure cancels delivery")

h:reset()
h.server:set_behavior("error")
h:enqueue({ "will fail", "must not send" }, "EMOTE", "Common", nil)
h.Queue:Flush(false)
-- Router catches the fake API error and Queue:RawSend cancels the sequence.
local failureState = h:queue_state()
check("hard API failure leaves no pending entry", h.Queue.PendingEntry == nil)
check("hard API failure clears queued entries", #h.Queue.Entries == 0)
check("hard API failure leaves queue idle", failureState.pending == 0 and not failureState.active)
check("hard API failure dispatched only once", h:sent_count() == 1)

-- ===========================================================================
-- 7. Hardware policy contract
-- ===========================================================================
print("\nContract 7: Hardware-gated open-world delivery")

h:reset()
h.inInstance = false
h:enqueue({ "open world one", "open world two" }, "SAY", "Common", nil)
h.Queue:Flush(false)
check("open-world SAY waits for hardware", h:sent_count() == 0 and h.Queue.NeedsContinue == true)
h.Queue:OnOpenChat()
check("hardware event sends first open-world chunk", h:sent_count() == 1)
drain(h, 1)
check("open-world ack prompts for next chunk", h.Queue.NeedsContinue == true)
h.Queue:OnOpenChat()
check("second hardware event sends next chunk", h:sent_count() == 2)
drain(h, 1)
check("open-world sequence completes", h:queue_state().pending == 0)

for _, case in ipairs({
    { "GUILD", "CHAT_MSG_GUILD" },
    { "OFFICER", "CHAT_MSG_OFFICER" },
}) do
    local chatType = case[1]
    h:reset()
    h:enqueue({ chatType .. " one", chatType .. " two" }, chatType, "Common", nil)
    h.Queue:Flush(false)
    check(chatType .. " auto-sends first chunk", h:sent_count() == 1 and not h.Queue.NeedsContinue)
    drain(h, 1)
    check(chatType .. " auto-sends after ACK", h:sent_count() == 2 and not h.Queue.NeedsContinue)
    drain(h, 1)
    check(chatType .. " auto-advancing sequence completes", h:queue_state().pending == 0)
end

h:reset()
h.inInstance = true
h:enqueue({ "GUILD_DISCORD one", "GUILD_DISCORD two" }, "GUILD_DISCORD", "Common", nil)
h.Queue:Flush(false)
check("GUILD_DISCORD waits for hardware", h:sent_count() == 0 and h.Queue.NeedsContinue == true)
h.Queue:OnOpenChat()
check("GUILD_DISCORD sends after hardware", h:sent_count() == 1)
drain(h, 1)
check("GUILD_DISCORD prompts after first ACK", h.Queue.NeedsContinue == true)
h.Queue:OnOpenChat()
check("GUILD_DISCORD sends second chunk after hardware", h:sent_count() == 2)
drain(h, 1)
check("GUILD_DISCORD hardware-gated sequence completes", h:queue_state().pending == 0)

local oldIsSecretValue = _G.issecretvalue
_G.issecretvalue = function(value)
    return value == "secret ack payload"
        or value == "secret ack GUID"
        or value == "secret Discord metadata"
end

h:reset()
h.server:set_behavior("drop")
h:enqueue({ "secret ack" }, "GUILD", "Common", nil)
h.Queue:Flush(true)
h:emit("CHAT_MSG_OFFICER", "secret ack payload", nil, nil, nil, nil, nil, nil, nil, nil, nil, h.playerGUID)
check("secret wrong-event ACK is rejected", h.Queue.PendingEntry ~= nil)
h:emit("CHAT_MSG_GUILD", "secret ack payload", nil, nil, nil, nil, nil, nil, nil, nil, nil, h.playerGUID)
check("secret guild ACK advances queue", h.Queue.PendingEntry == nil and not h.Queue:IsActive())

h:reset()
h.server:set_behavior("drop")
h:enqueue({ "accessible ack" }, "GUILD", "Common", nil)
h.Queue:Flush(true)
h:emit("CHAT_MSG_GUILD", "accessible ack", nil, nil, nil, nil, nil, nil, nil, nil, nil, "secret ack GUID")
check("secret GUID ACK advances queue", h.Queue.PendingEntry == nil and not h.Queue:IsActive())

h:reset()
h.server:set_behavior("drop")
h:enqueue({ "whisper ack" }, "WHISPER", "Common", "Target")
h.Queue:Flush(true)
h:emit("CHAT_MSG_WHISPER_INFORM", "whisper ack", "secret ack payload", nil, nil, nil, nil, nil, nil, nil, nil, h.playerGUID)
check("secret whisper target ACK advances queue", h.Queue.PendingEntry == nil and not h.Queue:IsActive())
_G.issecretvalue = oldIsSecretValue

-- ===========================================================================
-- 8. Queue cancellation contract
-- ===========================================================================
print("\nContract 8: Cancellation is terminal")

start_queue(h, { "cancel one", "cancel two", "cancel three" }, "EMOTE")
local sentBeforeCancel = h:sent_count()
h.Queue:Cancel()
drain(h, 3)
check("cancel clears pending entry", h.Queue.PendingEntry == nil)
check("cancel clears queued entries", #h.Queue.Entries == 0)
check("cancel prevents future sends", h:sent_count() == sentBeforeCancel)
check("cancel leaves queue idle", h:queue_state().pending == 0 and not h:queue_state().active)

print("\n" .. string.rep("-", 60))
print(("Results: %d/%d passed"):format(TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    os.exit(1)
end
print("All contract tests passed.")
