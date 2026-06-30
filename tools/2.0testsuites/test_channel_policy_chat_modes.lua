#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_channel_policy_chat_modes.lua
-- Run from repo root:
--   lua tools/2.0testsuites/test_channel_policy_chat_modes.lua
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

local function baseContext()
    return {
        pendingTabSwitch = nil,
        explicitChannel = nil,
        lockSavedDraft = false,
        blizzHasTarget = false,
        blizzType = nil,
        blizzTell = nil,
        blizzChan = nil,
        blizzLang = nil,
        lastUsed = { chatType = "SAY", target = nil, language = nil },
        frameChatType = nil,
        frameChatTarget = nil,
        frameChannelName = nil,
        incomingWhisperAffinity = nil,
        now = nil,
        existingSelection = { chatType = "SAY", target = nil, language = nil, channelName = nil },
    }
end

local function merge(dst, src)
    for k, v in pairs(src) do
        dst[k] = v
    end
    return dst
end

local YapperTable = {}
local chunk, err = loadfile("Src/Policies/ChannelPolicy.lua")
if not chunk then
    print("FATAL: failed to load Src/Policies/ChannelPolicy.lua: " .. tostring(err))
    os.exit(1)
end
chunk(nil, YapperTable)

local policy = YapperTable.ChannelPolicy
if type(policy) ~= "table" or type(policy.ResolveOpenSelection) ~= "function" then
    print("FATAL: ChannelPolicy.ResolveOpenSelection missing")
    os.exit(1)
end

print("ChannelPolicy loaded\n")

-- ---------------------------------------------------------------------------
-- Case 1: targetless whisper tab keeps active whisper target
-- ---------------------------------------------------------------------------
print("Case 1: targetless whisper tab fallback")
local c1 = merge(baseContext(), {
    pendingTabSwitch = { chatType = "WHISPER", target = nil },
    frameChatType = "WHISPER",
    frameChatTarget = nil,
    existingSelection = { chatType = "WHISPER", target = "Alice", language = "Common", channelName = nil },
})
local r1 = policy:ResolveOpenSelection(c1)
check("preserves whisper type", r1.chatType == "WHISPER")
check("preserves active whisper target", r1.target == "Alice")
check("preserves active language", r1.language == "Common")
print()

-- ---------------------------------------------------------------------------
-- Case 2: incoming whisper affinity applies on matching whisper frame
-- ---------------------------------------------------------------------------
print("Case 2: matching incoming whisper affinity")
local c2 = merge(baseContext(), {
    pendingTabSwitch = { chatType = "WHISPER", target = nil },
    frameChatType = "WHISPER",
    frameChatTarget = "Alice-Realm",
    incomingWhisperAffinity = { chatType = "WHISPER", target = "Alice", t = 99 },
    now = 100,
    existingSelection = { chatType = "WHISPER", target = "OldTarget", language = "Common", channelName = nil },
})
local r2 = policy:ResolveOpenSelection(c2)
check("uses whisper mode", r2.chatType == "WHISPER")
check("uses affinity target", r2.target == "Alice")
print()

-- ---------------------------------------------------------------------------
-- Case 3: stale affinity is ignored
-- ---------------------------------------------------------------------------
print("Case 3: stale incoming whisper affinity")
local c3 = merge(baseContext(), {
    pendingTabSwitch = { chatType = "WHISPER", target = nil },
    frameChatType = "WHISPER",
    frameChatTarget = "Alice",
    incomingWhisperAffinity = { chatType = "WHISPER", target = "Alice", t = 90 },
    now = 100,
    existingSelection = { chatType = "WHISPER", target = "FallbackTarget", language = "Common", channelName = nil },
})
local r3 = policy:ResolveOpenSelection(c3)
check("falls back to existing selection target", r3.target == "FallbackTarget")
print()

-- ---------------------------------------------------------------------------
-- Case 4: affinity mismatched to whisper frame target is ignored
-- ---------------------------------------------------------------------------
print("Case 4: mismatched affinity ignored")
local c4 = merge(baseContext(), {
    pendingTabSwitch = { chatType = "WHISPER", target = nil },
    frameChatType = "WHISPER",
    frameChatTarget = "Bob",
    incomingWhisperAffinity = { chatType = "WHISPER", target = "Alice", t = 99 },
    now = 100,
    existingSelection = { chatType = "WHISPER", target = nil, language = nil, channelName = nil },
})
local r4 = policy:ResolveOpenSelection(c4)
check("does not force mismatched target", r4.chatType == "SAY" and r4.target == nil)
print()

-- ---------------------------------------------------------------------------
-- Case 5: non-whisper frame ignores affinity
-- ---------------------------------------------------------------------------
print("Case 5: non-whisper frame ignores affinity")
local c5 = merge(baseContext(), {
    pendingTabSwitch = { chatType = "WHISPER", target = nil },
    frameChatType = "SAY",
    frameChatTarget = nil,
    incomingWhisperAffinity = { chatType = "WHISPER", target = "Alice", t = 99 },
    now = 100,
    existingSelection = { chatType = "SAY", target = nil, language = nil, channelName = nil },
})
local r5 = policy:ResolveOpenSelection(c5)
check("falls back to SAY", r5.chatType == "SAY" and r5.target == nil)
print()

-- ---------------------------------------------------------------------------
-- Case 6: BN whisper affinity keeps full target identity
-- ---------------------------------------------------------------------------
print("Case 6: BN whisper affinity")
local c6 = merge(baseContext(), {
    pendingTabSwitch = { chatType = "BN_WHISPER", target = nil },
    frameChatType = "BN_WHISPER",
    frameChatTarget = "Alice#1234",
    incomingWhisperAffinity = { chatType = "BN_WHISPER", target = "Alice#1234", t = 10 },
    now = 12,
    existingSelection = { chatType = "BN_WHISPER", target = "Other#9999", language = nil, channelName = nil },
})
local r6 = policy:ResolveOpenSelection(c6)
check("uses BN whisper type", r6.chatType == "BN_WHISPER")
check("keeps full BN target", r6.target == "Alice#1234")
print()

-- ---------------------------------------------------------------------------
-- Case 7: channel behavior remains intact
-- ---------------------------------------------------------------------------
print("Case 7: channel behavior")
local c7 = merge(baseContext(), {
    pendingTabSwitch = { chatType = "CHANNEL", target = "2", channelName = "Trade" },
    frameChatType = "CHANNEL",
    frameChatTarget = "2",
})
local r7 = policy:ResolveOpenSelection(c7)
check("channel type preserved", r7.chatType == "CHANNEL")
check("channel target preserved", r7.target == "2")
check("channel name preserved", r7.channelName == "Trade")
print()

-- ---------------------------------------------------------------------------
-- Case 8: all non-target chat modes clear stale targets
-- ---------------------------------------------------------------------------
print("Case 8: non-target chat modes clear stale targets")
local nonTargetModes = {
    "SAY", "EMOTE", "YELL", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER",
    "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER",
}
for _, mode in ipairs(nonTargetModes) do
    local c8 = merge(baseContext(), {
        pendingTabSwitch = { chatType = mode, target = "LeakyTarget", channelName = "LeakyChannel" },
        frameChatType = mode,
        frameChatTarget = nil,
        existingSelection = { chatType = "WHISPER", target = "Alice", language = "Common", channelName = nil },
    })
    local r8 = policy:ResolveOpenSelection(c8)
    check(mode .. " keeps mode", r8.chatType == mode)
    check(mode .. " clears target", r8.target == nil)
    check(mode .. " clears channelName", r8.channelName == nil)
end
print()

-- ---------------------------------------------------------------------------
-- Case 9: CHANNEL without target falls back to SAY
-- ---------------------------------------------------------------------------
print("Case 9: invalid CHANNEL target")
local c9 = merge(baseContext(), {
    pendingTabSwitch = { chatType = "CHANNEL", target = nil, channelName = "General" },
    frameChatType = "CHANNEL",
    frameChatTarget = nil,
})
local r9 = policy:ResolveOpenSelection(c9)
check("invalid channel falls back to SAY", r9.chatType == "SAY" and r9.target == nil)
print()

-- ---------------------------------------------------------------------------
-- Case 10: commit-time sanitizer enforces invariants
-- ---------------------------------------------------------------------------
print("Case 10: commit-time sanitizer")
local s10a = policy:SanitizeCommittedSelection({
    chatType = "WHISPER",
    target = nil,
    language = "Common",
    channelName = "Trade",
})
check("invalid whisper commit demotes to SAY", s10a and s10a.chatType == "SAY" and s10a.target == nil)
check("demoted whisper clears channelName", s10a and s10a.channelName == nil)

local s10b = policy:SanitizeCommittedSelection({
    chatType = "WHISPER",
    target = "Alice",
    language = "Common",
    channelName = "Trade",
})
check("valid whisper commit keeps target", s10b and s10b.chatType == "WHISPER" and s10b.target == "Alice")
check("valid whisper commit clears channelName", s10b and s10b.channelName == nil)

local s10c = policy:SanitizeCommittedSelection({
    chatType = "CHANNEL",
    target = nil,
    language = nil,
    channelName = "General",
})
check("invalid channel commit demotes to SAY", s10c and s10c.chatType == "SAY" and s10c.target == nil)
print()

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------
print(string.rep("-", 60))
print(string.format("Results: %d/%d passed", TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    print(FAILURES .. " FAILURE(S)")
    os.exit(1)
else
    print("All tests passed!")
end
