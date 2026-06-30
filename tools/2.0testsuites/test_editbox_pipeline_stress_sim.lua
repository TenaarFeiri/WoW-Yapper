#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_editbox_pipeline_stress_sim.lua
-- First-pass, intentionally unoptimized simulation of end-to-end pipeline:
--   incoming event capture -> open/show resolve -> affinity consume/clear
-- Run from repo root:
--   lua tools/2.0testsuites/test_editbox_pipeline_stress_sim.lua
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

local function hasValue(v)
    return v ~= nil and tostring(v) ~= ""
end

local function isWhisperType(ct)
    return ct == "WHISPER" or ct == "BN_WHISPER"
end

local function normaliseWhisperTarget(v, whisperKind)
    if v == nil then return nil end
    local s = tostring(v)
    if s == "" then return nil end
    s = s:lower()
    if whisperKind == "WHISPER" then
        s = s:gsub("%-.*$", "")
    end
    return s
end

local function shallowCopy(t)
    local c = {}
    for k, v in pairs(t) do
        c[k] = v
    end
    return c
end

local function cloneSelection(sel)
    return {
        chatType = sel and sel.chatType or "SAY",
        target = sel and sel.target or nil,
        language = sel and sel.language or nil,
        channelName = sel and sel.channelName or nil,
    }
end

local function choose(rng, arr)
    return arr[rng(#arr)]
end

local function hashSeed(s)
    local h = 0
    for i = 1, #s do
        h = (h * 131 + s:byte(i)) % 2147483647
    end
    if h == 0 then h = 1 end
    return h
end

local function pickDt(cfg, rng)
    if cfg.fps == "high" then
        return (1 / 300) + (rng(5) - 1) * 0.0007
    end
    return (1 / 8) + (rng(6) - 1) * 0.012
end

local channels = {
    { target = "1", channelName = "General" },
    { target = "2", channelName = "Trade" },
    { target = "3", channelName = "LocalDefense" },
}

local players = { "Alice", "Bob", "Cara", "Dane", "Eve", "Finn", "Gina", "Hank" }
local playersRealm = { "Alice-Realm", "Bob-Realm", "Cara-Realm", "Dane-Realm", "Eve-Realm" }
local bnetPlayers = { "Alice#1234", "Bob#8888", "Cara#4567", "Dane#7654", "Eve#1000" }

local nonTargetModes = {
    "SAY", "EMOTE", "YELL", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER",
    "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER",
}

local function newSimulator(policy)
    local sim = {
        policy = policy,
        ChatType = "SAY",
        Target = nil,
        Language = nil,
        ChannelName = nil,
        LastUsed = { chatType = "SAY", target = nil, language = nil },
        _incomingWhisperAffinity = nil,
        metrics = {
            affinityCaptured = 0,
            affinityConsumed = 0,
            affinityExpired = 0,
            whisperFallbackPreserved = 0,
            sayFallbacks = 0,
            nonTargetLeaksPrevented = 0,
            opens = 0,
            sends = 0,
            receives = 0,
        },
    }

    function sim:captureIncomingWhisper(event, sender, activeFrameType, activeFrameTarget, now)
        self.metrics.receives = self.metrics.receives + 1
        if not sender or sender == "" then
            return
        end

        local kind = (event == "CHAT_MSG_BN_WHISPER") and "BN_WHISPER" or "WHISPER"
        local frameIsWhisper = (activeFrameType == "WHISPER" or activeFrameType == "BN_WHISPER")

        if frameIsWhisper and hasValue(activeFrameTarget)
            and normaliseWhisperTarget(sender, kind) == normaliseWhisperTarget(activeFrameTarget, kind) then
            self._incomingWhisperAffinity = {
                chatType = kind,
                target = activeFrameTarget,
                t = now,
            }
            self.metrics.affinityCaptured = self.metrics.affinityCaptured + 1
        end
    end

    function sim:open(context)
        self.metrics.opens = self.metrics.opens + 1

        local incomingWhisperAffinity = self._incomingWhisperAffinity
        if incomingWhisperAffinity and incomingWhisperAffinity.t and context.now then
            if (context.now - incomingWhisperAffinity.t) > 5 then
                incomingWhisperAffinity = nil
                self._incomingWhisperAffinity = nil
                self.metrics.affinityExpired = self.metrics.affinityExpired + 1
            end
        end

        local resolved = self.policy:ResolveOpenSelection({
            pendingTabSwitch = context.pendingTabSwitch,
            explicitChannel = context.explicitChannel,
            lockSavedDraft = context.lockSavedDraft,
            blizzHasTarget = context.blizzHasTarget,
            blizzType = context.blizzType,
            blizzTell = context.blizzTell,
            blizzChan = context.blizzChan,
            blizzLang = context.blizzLang,
            lastUsed = self.LastUsed,
            frameChatType = context.frameChatType,
            frameChatTarget = context.frameChatTarget,
            frameChannelName = context.frameChannelName,
            incomingWhisperAffinity = incomingWhisperAffinity,
            now = context.now,
            existingSelection = {
                chatType = self.ChatType,
                target = self.Target,
                language = self.Language,
                channelName = self.ChannelName,
            },
        })

        if incomingWhisperAffinity and resolved then
            local affinityTarget = incomingWhisperAffinity.target
            local isResolvedWhisper = (resolved.chatType == "WHISPER" or resolved.chatType == "BN_WHISPER")
            if isResolvedWhisper and affinityTarget and resolved.target == affinityTarget then
                self._incomingWhisperAffinity = nil
                self.metrics.affinityConsumed = self.metrics.affinityConsumed + 1
            end
        end

        if resolved.chatType == "WHISPER"
            and context.pendingTabSwitch
            and context.pendingTabSwitch.chatType == "WHISPER"
            and not hasValue(context.pendingTabSwitch.target)
            and context.frameChatType == "WHISPER"
            and hasValue(self.Target) then
            self.metrics.whisperFallbackPreserved = self.metrics.whisperFallbackPreserved + 1
        end

        if resolved.chatType == "SAY" then
            self.metrics.sayFallbacks = self.metrics.sayFallbacks + 1
        end

        if resolved.chatType ~= "CHANNEL" and not isWhisperType(resolved.chatType) then
            if resolved.target == nil and resolved.channelName == nil then
                self.metrics.nonTargetLeaksPrevented = self.metrics.nonTargetLeaksPrevented + 1
            end
        end

        self.ChatType = resolved.chatType
        self.Target = resolved.target
        self.Language = resolved.language
        self.ChannelName = resolved.channelName

        return resolved
    end

    function sim:send()
        self.metrics.sends = self.metrics.sends + 1
        self.LastUsed = {
            chatType = self.ChatType,
            target = self.Target,
            language = self.Language,
        }
    end

    return sim
end

local function validateSelection(label, sel)
    if isWhisperType(sel.chatType) then
        check(label .. " whisper target present", hasValue(sel.target))
        check(label .. " whisper channelName nil", sel.channelName == nil)
    elseif sel.chatType == "CHANNEL" then
        check(label .. " channel target present", hasValue(sel.target))
    else
        check(label .. " non-target clears target", sel.target == nil)
        check(label .. " non-target clears channelName", sel.channelName == nil)
    end
end

local function buildNoisyBlizzContext(cfg, rng)
    local context = {
        blizzHasTarget = false,
        blizzType = nil,
        blizzTell = nil,
        blizzChan = nil,
        blizzLang = nil,
    }

    if cfg.env ~= "noisy" then
        return context
    end

    if rng(100) <= 18 then
        context.blizzHasTarget = true
        local r = rng(3)
        if r == 1 then
            context.blizzType = "WHISPER"
            context.blizzTell = choose(rng, playersRealm)
        elseif r == 2 then
            context.blizzType = "BN_WHISPER"
            context.blizzTell = choose(rng, bnetPlayers)
        else
            local ch = choose(rng, channels)
            context.blizzType = "CHANNEL"
            context.blizzChan = ch.target
        end
    end

    return context
end

local function scenarioRapidSwitch(sim, cfg)
    local scenarioName = "pipeline-rapid-switch/" .. cfg.env .. "/" .. cfg.fps
    print("Scenario: " .. scenarioName)

    math.randomseed(hashSeed(scenarioName))
    local rng = math.random
    local now = 1000
    local iterations = 3500

    for _ = 1, iterations do
        now = now + pickDt(cfg, rng)

        local modeRoll = rng(100)
        local pendingTabSwitch
        local frameChatType
        local frameChatTarget
        local frameChannelName

        if modeRoll <= 40 then
            local targetless = (rng(100) <= 70)
            pendingTabSwitch = {
                chatType = "WHISPER",
                target = targetless and nil or choose(rng, players),
            }
            frameChatType = "WHISPER"
            frameChatTarget = pendingTabSwitch.target

            if targetless and rng(100) <= 55 then
                sim.ChatType = "WHISPER"
                sim.Target = choose(rng, players)
                sim.ChannelName = nil
            end
        elseif modeRoll <= 54 then
            pendingTabSwitch = {
                chatType = "BN_WHISPER",
                target = (rng(100) <= 35) and nil or choose(rng, bnetPlayers),
            }
            frameChatType = "BN_WHISPER"
            frameChatTarget = pendingTabSwitch.target
        elseif modeRoll <= 74 then
            local ch = choose(rng, channels)
            pendingTabSwitch = {
                chatType = "CHANNEL",
                target = ch.target,
                channelName = ch.channelName,
            }
            frameChatType = "CHANNEL"
            frameChatTarget = ch.target
            frameChannelName = ch.channelName
        else
            local ct = choose(rng, nonTargetModes)
            pendingTabSwitch = {
                chatType = ct,
                target = "LEAKY_TARGET",
                channelName = "LEAKY_CHANNEL",
            }
            frameChatType = ct
            frameChatTarget = nil
        end

        if cfg.env == "noisy" and rng(100) <= 30 then
            local kind = (rng(2) == 1) and "WHISPER" or "BN_WHISPER"
            local sender = (kind == "WHISPER") and choose(rng, playersRealm) or choose(rng, bnetPlayers)
            sim:captureIncomingWhisper(
                (kind == "WHISPER") and "CHAT_MSG_WHISPER" or "CHAT_MSG_BN_WHISPER",
                sender,
                frameChatType,
                frameChatTarget,
                now - ((rng(2) == 1) and 0.1 or 7.1)
            )
        end

        local noisyBlizz = buildNoisyBlizzContext(cfg, rng)

        local result = sim:open({
            pendingTabSwitch = pendingTabSwitch,
            explicitChannel = nil,
            lockSavedDraft = false,
            blizzHasTarget = noisyBlizz.blizzHasTarget,
            blizzType = noisyBlizz.blizzType,
            blizzTell = noisyBlizz.blizzTell,
            blizzChan = noisyBlizz.blizzChan,
            blizzLang = noisyBlizz.blizzLang,
            frameChatType = frameChatType,
            frameChatTarget = frameChatTarget,
            frameChannelName = frameChannelName,
            now = now,
        })

        validateSelection(scenarioName, result)

        if rng(100) <= 55 then
            sim:send()
        end
    end

    check(scenarioName .. " opens occurred", sim.metrics.opens > 0)
    check(scenarioName .. " sends occurred", sim.metrics.sends > 0)
end

local function scenarioWhisperSpamMixed(sim, cfg)
    local scenarioName = "pipeline-whisper-spam/" .. cfg.env .. "/" .. cfg.fps
    print("Scenario: " .. scenarioName)

    math.randomseed(hashSeed(scenarioName))
    local rng = math.random
    local now = 9000
    local iterations = 4200
    local matchedIncoming = 0
    local staleIncoming = 0
    local mismatchedIncoming = 0

    for _ = 1, iterations do
        now = now + pickDt(cfg, rng)

        local kind = (rng(100) <= 65) and "WHISPER" or "BN_WHISPER"
        local senderPool = (kind == "WHISPER") and playersRealm or bnetPlayers
        local sender = choose(rng, senderPool)

        local pendingTabSwitch = { chatType = kind, target = nil }
        local frameChatType = kind
        local frameChatTarget

        local patternRoll = rng(100)
        if patternRoll <= 45 then
            frameChatTarget = sender
            sim:captureIncomingWhisper(
                (kind == "WHISPER") and "CHAT_MSG_WHISPER" or "CHAT_MSG_BN_WHISPER",
                sender,
                frameChatType,
                frameChatTarget,
                now
            )
            matchedIncoming = matchedIncoming + 1
        elseif patternRoll <= 72 then
            frameChatTarget = sender
            sim:captureIncomingWhisper(
                (kind == "WHISPER") and "CHAT_MSG_WHISPER" or "CHAT_MSG_BN_WHISPER",
                sender,
                frameChatType,
                frameChatTarget,
                now - 6.3
            )
            staleIncoming = staleIncoming + 1
        else
            frameChatTarget = choose(rng, senderPool)
            sim:captureIncomingWhisper(
                (kind == "WHISPER") and "CHAT_MSG_WHISPER" or "CHAT_MSG_BN_WHISPER",
                sender,
                frameChatType,
                frameChatTarget,
                now
            )
            if normaliseWhisperTarget(frameChatTarget, kind) ~= normaliseWhisperTarget(sender, kind) then
                mismatchedIncoming = mismatchedIncoming + 1
            end
        end

        -- Simulate aggressive outgoing whisper spam mixed with receives.
        if rng(100) <= 60 then
            sim.ChatType = kind
            sim.Target = (kind == "WHISPER") and choose(rng, players) or choose(rng, bnetPlayers)
            sim.ChannelName = nil
            sim:send()
        end

        local noisyBlizz = buildNoisyBlizzContext(cfg, rng)
        local result = sim:open({
            pendingTabSwitch = pendingTabSwitch,
            explicitChannel = nil,
            lockSavedDraft = false,
            blizzHasTarget = noisyBlizz.blizzHasTarget,
            blizzType = noisyBlizz.blizzType,
            blizzTell = noisyBlizz.blizzTell,
            blizzChan = noisyBlizz.blizzChan,
            blizzLang = noisyBlizz.blizzLang,
            frameChatType = frameChatType,
            frameChatTarget = frameChatTarget,
            frameChannelName = nil,
            now = now,
        })

        validateSelection(scenarioName, result)
    end

    check(scenarioName .. " matched incoming occurred", matchedIncoming > 0)
    check(scenarioName .. " stale incoming occurred", staleIncoming > 0)
    check(scenarioName .. " mismatched incoming occurred", mismatchedIncoming > 0)
    check(scenarioName .. " affinity captures occurred", sim.metrics.affinityCaptured > 0)
    check(scenarioName .. " affinity consumes occurred", sim.metrics.affinityConsumed > 0)
end

local function printMetrics(label, metrics)
    print(string.format(
        "  metrics[%s]: opens=%d sends=%d receives=%d captures=%d consumes=%d expired=%d whisperFallbackPreserved=%d sayFallbacks=%d leakPreventions=%d",
        label,
        metrics.opens,
        metrics.sends,
        metrics.receives,
        metrics.affinityCaptured,
        metrics.affinityConsumed,
        metrics.affinityExpired,
        metrics.whisperFallbackPreserved,
        metrics.sayFallbacks,
        metrics.nonTargetLeaksPrevented
    ))
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

print("EditBox pipeline stress simulation (first-pass baseline)\n")

local matrix = {
    { env = "optimal", fps = "low" },
    { env = "optimal", fps = "high" },
    { env = "noisy", fps = "low" },
    { env = "noisy", fps = "high" },
}

for _, cfg in ipairs(matrix) do
    local sim = newSimulator(policy)
    scenarioRapidSwitch(sim, shallowCopy(cfg))
    printMetrics("rapid-" .. cfg.env .. "-" .. cfg.fps, sim.metrics)
end

for _, cfg in ipairs(matrix) do
    local sim = newSimulator(policy)
    scenarioWhisperSpamMixed(sim, shallowCopy(cfg))
    printMetrics("spam-" .. cfg.env .. "-" .. cfg.fps, sim.metrics)
end

print("\n" .. string.rep("-", 60))
print(string.format("Results: %d/%d passed", TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    print(FAILURES .. " FAILURE(S)")
    os.exit(1)
else
    print("All pipeline stress simulations passed!")
end
