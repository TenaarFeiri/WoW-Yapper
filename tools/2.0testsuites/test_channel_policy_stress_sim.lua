#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_channel_policy_stress_sim.lua
-- Run from repo root:
--   lua tools/2.0testsuites/test_channel_policy_stress_sim.lua
-- ---------------------------------------------------------------------------

local PASS, FAIL = "PASS", "FAIL"
local TESTS, FAILURES = 0, 0

local function check(label, condition)
    TESTS = TESTS + 1
    if condition then
        return true
    end

    FAILURES = FAILURES + 1
    print("  [" .. FAIL .. "] " .. label)
    return false
end

local function checkf(scope, label, condition)
    return check(scope .. ": " .. label, condition)
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

local function shallowCopy(t)
    local c = {}
    for k, v in pairs(t) do
        c[k] = v
    end
    return c
end

local function cloneSelection(sel)
    if type(sel) ~= "table" then
        return { chatType = "SAY", target = nil, language = nil, channelName = nil }
    end

    return {
        chatType = sel.chatType,
        target = sel.target,
        language = sel.language,
        channelName = sel.channelName,
    }
end

local function isWhisperType(ct)
    return ct == "WHISPER" or ct == "BN_WHISPER"
end

local function hasValue(v)
    return v ~= nil and tostring(v) ~= ""
end

local function validateSelection(scope, sel)
    local ct = sel.chatType
    if isWhisperType(ct) then
        checkf(scope, "whisper/bn whisper always has target", hasValue(sel.target))
        checkf(scope, "whisper/bn whisper has no channelName", sel.channelName == nil)
        return
    end

    if ct == "CHANNEL" then
        checkf(scope, "channel has target", hasValue(sel.target))
        return
    end

    checkf(scope, "non-target mode clears target", sel.target == nil)
    checkf(scope, "non-target mode clears channelName", sel.channelName == nil)
end

local function choose(rng, items)
    return items[rng(#items)]
end

local function hashSeed(s)
    local h = 0
    for i = 1, #s do
        h = (h * 131 + s:byte(i)) % 2147483647
    end
    if h == 0 then
        h = 1
    end
    return h
end

local nonTargetModes = {
    "SAY", "EMOTE", "YELL", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER",
    "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER",
}

local channels = {
    { target = "1", name = "General" },
    { target = "2", name = "Trade" },
    { target = "3", name = "LocalDefense" },
}

local players = { "Alice", "Bob", "Cara", "Dane", "Eve", "Finn" }
local bnetPlayers = { "Alice#1234", "Bob#8888", "Cara#4567", "Dane#7654" }

local function pickDt(cfg, rng)
    if cfg.fps == "high" then
        return (1 / 240) + (rng(4) - 1) * 0.001
    end

    return (1 / 10) + (rng(7) - 1) * 0.01
end

local function maybeNoisyBlizz(context, cfg, rng)
    if cfg.env ~= "noisy" then
        return
    end

    if rng(100) <= 25 then
        context.blizzHasTarget = true
        local mode = rng(3)
        if mode == 1 then
            context.blizzType = "WHISPER"
            context.blizzTell = choose(rng, players)
        elseif mode == 2 then
            context.blizzType = "BN_WHISPER"
            context.blizzTell = choose(rng, bnetPlayers)
        else
            local ch = choose(rng, channels)
            context.blizzType = "CHANNEL"
            context.blizzChan = ch.target
        end
    end
end

local function runRapidSwitchScenario(policy, cfg)
    local name = "rapid-switch/" .. cfg.env .. "/" .. cfg.fps
    print("Scenario: " .. name)

    local seed = hashSeed(name)
    math.randomseed(seed)
    local rng = math.random

    local context = baseContext()
    local now = 1000
    local iterations = 2500
    local opportunities = 0

    for i = 1, iterations do
        now = now + pickDt(cfg, rng)
        context.now = now

        local modeRoll = rng(100)
        if modeRoll <= 45 then
            local targetlessWhisper = rng(100) <= 65
            context.pendingTabSwitch = {
                chatType = "WHISPER",
                target = targetlessWhisper and nil or choose(rng, players),
            }
            context.frameChatType = "WHISPER"
            context.frameChatTarget = targetlessWhisper and nil or context.pendingTabSwitch.target

            if targetlessWhisper then
                if i % 2 == 0 then
                    context.existingSelection = { chatType = "WHISPER", target = choose(rng, players), language = "Common", channelName = nil }
                else
                    context.existingSelection = { chatType = "SAY", target = nil, language = nil, channelName = nil }
                end

                if context.existingSelection.chatType == "WHISPER" and hasValue(context.existingSelection.target) then
                    opportunities = opportunities + 1
                end
            end
        elseif modeRoll <= 55 then
            context.pendingTabSwitch = {
                chatType = "BN_WHISPER",
                target = (rng(100) <= 40) and nil or choose(rng, bnetPlayers),
            }
            context.frameChatType = "BN_WHISPER"
            context.frameChatTarget = context.pendingTabSwitch.target
        elseif modeRoll <= 75 then
            local ch = choose(rng, channels)
            context.pendingTabSwitch = {
                chatType = "CHANNEL",
                target = ch.target,
                channelName = ch.name,
            }
            context.frameChatType = "CHANNEL"
            context.frameChatTarget = ch.target
            context.frameChannelName = ch.name
        else
            local ct = choose(rng, nonTargetModes)
            context.pendingTabSwitch = { chatType = ct, target = "LEAK", channelName = "LEAK" }
            context.frameChatType = ct
            context.frameChatTarget = nil
            context.frameChannelName = nil
        end

        if cfg.env == "noisy" and rng(100) <= 20 then
            -- Simulate out-of-order affinity events in busy environments.
            context.incomingWhisperAffinity = {
                chatType = (rng(2) == 1) and "WHISPER" or "BN_WHISPER",
                target = (rng(2) == 1) and choose(rng, players) or choose(rng, bnetPlayers),
                t = now - (rng(2) == 1 and 0.2 or 7.0),
            }
        else
            context.incomingWhisperAffinity = nil
        end

        maybeNoisyBlizz(context, cfg, rng)

        local result = policy:ResolveOpenSelection(context)
        validateSelection(name, result)

        if context.pendingTabSwitch
            and context.pendingTabSwitch.chatType == "WHISPER"
            and not hasValue(context.pendingTabSwitch.target)
            and context.frameChatType == "WHISPER"
            and context.existingSelection.chatType == "WHISPER"
            and hasValue(context.existingSelection.target) then
            checkf(name, "targetless whisper switch preserves conversation", result.chatType == "WHISPER" and hasValue(result.target))
        end

        context.lastUsed = {
            chatType = result.chatType,
            target = result.target,
            language = result.language,
        }
        context.existingSelection = cloneSelection(result)
        context.pendingTabSwitch = nil
        context.explicitChannel = nil
        context.blizzHasTarget = false
        context.blizzType = nil
        context.blizzTell = nil
        context.blizzChan = nil
        context.blizzLang = nil
        context.frameChannelName = nil
    end

    checkf(name, "covered targetless whisper opportunities", opportunities > 0)
end

local function runWhisperSpamScenario(policy, cfg)
    local name = "whisper-spam/" .. cfg.env .. "/" .. cfg.fps
    print("Scenario: " .. name)

    local seed = hashSeed(name)
    math.randomseed(seed)
    local rng = math.random

    local context = baseContext()
    local now = 5000
    local iterations = 3000
    local matchingAffinityChecks = 0
    local staleChecks = 0
    local mismatchChecks = 0

    for i = 1, iterations do
        now = now + pickDt(cfg, rng)
        context.now = now

        local whisperKind = (rng(100) <= 70) and "WHISPER" or "BN_WHISPER"
        local targetPool = (whisperKind == "WHISPER") and players or bnetPlayers
        local liveTarget = choose(rng, targetPool)

        context.pendingTabSwitch = { chatType = whisperKind, target = nil }
        context.frameChatType = whisperKind

        local roll = rng(100)
        if roll <= 45 then
            context.frameChatTarget = nil
            context.incomingWhisperAffinity = {
                chatType = whisperKind,
                target = liveTarget,
                t = now - (cfg.fps == "low" and 0.2 or 0.05),
            }
            context.existingSelection = { chatType = whisperKind, target = choose(rng, targetPool), language = "Common", channelName = nil }
            matchingAffinityChecks = matchingAffinityChecks + 1
        elseif roll <= 70 then
            context.frameChatTarget = nil
            context.incomingWhisperAffinity = {
                chatType = whisperKind,
                target = liveTarget,
                t = now - 6.5,
            }
            context.existingSelection = { chatType = whisperKind, target = choose(rng, targetPool), language = "Common", channelName = nil }
            staleChecks = staleChecks + 1
        elseif roll <= 88 then
            context.frameChatTarget = choose(rng, targetPool)
            context.incomingWhisperAffinity = {
                chatType = whisperKind,
                target = liveTarget,
                t = now - 0.1,
            }
            -- Ensure mismatch by retrying once if random target matched.
            if context.frameChatTarget == liveTarget then
                context.frameChatTarget = choose(rng, targetPool)
                if context.frameChatTarget == liveTarget then
                    context.frameChatTarget = nil
                end
            end
            context.existingSelection = { chatType = whisperKind, target = choose(rng, targetPool), language = "Common", channelName = nil }
            mismatchChecks = mismatchChecks + 1
        else
            context.frameChatTarget = liveTarget
            context.incomingWhisperAffinity = nil
            context.existingSelection = { chatType = whisperKind, target = liveTarget, language = "Common", channelName = nil }
        end

        if cfg.env == "noisy" and rng(100) <= 30 then
            maybeNoisyBlizz(context, cfg, rng)
        end

        local result = policy:ResolveOpenSelection(context)
        validateSelection(name, result)

        if context.incomingWhisperAffinity and context.incomingWhisperAffinity.t and (now - context.incomingWhisperAffinity.t) <= 5
            and context.frameChatTarget == nil then
            checkf(name, "fresh matching affinity is used", result.chatType == whisperKind and result.target == context.incomingWhisperAffinity.target)
        end

        if context.incomingWhisperAffinity and context.incomingWhisperAffinity.t and (now - context.incomingWhisperAffinity.t) > 5
            and context.existingSelection.chatType == whisperKind then
            checkf(name, "stale affinity ignored in favor of existing selection", result.target == context.existingSelection.target)
        end

        if context.incomingWhisperAffinity and context.frameChatTarget ~= nil then
            local frame = tostring(context.frameChatTarget):lower()
            local affinity = tostring(context.incomingWhisperAffinity.target):lower()
            if whisperKind == "WHISPER" then
                frame = frame:gsub("%-.*$", "")
                affinity = affinity:gsub("%-.*$", "")
            end

            if frame ~= affinity then
                local baseline = shallowCopy(context)
                baseline.incomingWhisperAffinity = nil
                local expected = policy:ResolveOpenSelection(baseline)
                checkf(
                    name,
                    "mismatched affinity behaves like no-affinity baseline",
                    result.chatType == expected.chatType and result.target == expected.target and result.channelName == expected.channelName
                )
            end
        end

        context.lastUsed = {
            chatType = result.chatType,
            target = result.target,
            language = result.language,
        }
        context.existingSelection = cloneSelection(result)
        context.pendingTabSwitch = nil
        context.explicitChannel = nil
        context.blizzHasTarget = false
        context.blizzType = nil
        context.blizzTell = nil
        context.blizzChan = nil
        context.blizzLang = nil
    end

    checkf(name, "matching affinity checks executed", matchingAffinityChecks > 0)
    checkf(name, "stale affinity checks executed", staleChecks > 0)
    checkf(name, "mismatch checks executed", mismatchChecks > 0)
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

print("ChannelPolicy stress simulation\n")

local matrix = {
    { env = "optimal", fps = "low" },
    { env = "optimal", fps = "high" },
    { env = "noisy", fps = "low" },
    { env = "noisy", fps = "high" },
}

for _, cfg in ipairs(matrix) do
    runRapidSwitchScenario(policy, shallowCopy(cfg))
end

for _, cfg in ipairs(matrix) do
    runWhisperSpamScenario(policy, shallowCopy(cfg))
end

print("\n" .. string.rep("-", 60))
print(string.format("Results: %d/%d passed", TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    print(FAILURES .. " FAILURE(S)")
    os.exit(1)
else
    print("All stress simulations passed!")
end
