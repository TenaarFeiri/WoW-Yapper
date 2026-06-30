#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_editbox_pipeline_adversarial_fault_injection.lua
-- Purpose: inject impossible/out-of-order state faults and classify both
-- immediate failure types and downstream consequences.
-- Run from repo root:
--   lua tools/2.0testsuites/test_editbox_pipeline_adversarial_fault_injection.lua
-- ---------------------------------------------------------------------------

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

local players = { "Alice", "Bob", "Cara", "Dane", "Eve", "Finn", "Gina", "Hank" }
local playersRealm = { "Alice-Realm", "Bob-Realm", "Cara-Realm", "Dane-Realm", "Eve-Realm" }
local bnetPlayers = { "Alice#1234", "Bob#8888", "Cara#4567", "Dane#7654", "Eve#1000" }
local channels = {
    { target = "1", channelName = "General" },
    { target = "2", channelName = "Trade" },
    { target = "3", channelName = "LocalDefense" },
}
local nonTargetModes = {
    "SAY", "EMOTE", "YELL", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER",
    "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER",
}

local function validateSelection(sel)
    if isWhisperType(sel.chatType) then
        if not hasValue(sel.target) then
            return false, "whisper-without-target"
        end
        if sel.channelName ~= nil then
            return false, "whisper-with-channelName"
        end
    elseif sel.chatType == "CHANNEL" then
        if not hasValue(sel.target) then
            return false, "channel-without-target"
        end
    else
        if sel.target ~= nil then
            return false, "non-target-with-target"
        end
        if sel.channelName ~= nil then
            return false, "non-target-with-channelName"
        end
    end
    return true
end

local function sameSelection(a, b)
    return a.chatType == b.chatType
        and a.target == b.target
        and a.channelName == b.channelName
end

local function newSim(policy)
    local sim = {
        policy = policy,
        ChatType = "SAY",
        Target = nil,
        Language = nil,
        ChannelName = nil,
        LastUsed = { chatType = "SAY", target = nil, language = nil },
        incomingWhisperAffinity = nil,
    }

    function sim:captureIncoming(event, sender, activeFrameType, activeFrameTarget, now)
        if not hasValue(sender) then
            return
        end

        local kind = (event == "CHAT_MSG_BN_WHISPER") and "BN_WHISPER" or "WHISPER"
        local frameIsWhisper = activeFrameType == "WHISPER" or activeFrameType == "BN_WHISPER"

        if frameIsWhisper and hasValue(activeFrameTarget)
            and normaliseWhisperTarget(sender, kind) == normaliseWhisperTarget(activeFrameTarget, kind) then
            self.incomingWhisperAffinity = {
                chatType = kind,
                target = activeFrameTarget,
                t = now,
            }
        end
    end

    function sim:open(context)
        local affinity = self.incomingWhisperAffinity
        if affinity and affinity.t and context.now and (context.now - affinity.t) > 5 then
            self.incomingWhisperAffinity = nil
            affinity = nil
        end

        local resolved = self.policy:ResolveOpenSelection({
            pendingTabSwitch = context.pendingTabSwitch,
            explicitChannel = nil,
            lockSavedDraft = false,
            blizzHasTarget = context.blizzHasTarget,
            blizzType = context.blizzType,
            blizzTell = context.blizzTell,
            blizzChan = context.blizzChan,
            blizzLang = nil,
            lastUsed = self.LastUsed,
            frameChatType = context.frameChatType,
            frameChatTarget = context.frameChatTarget,
            frameChannelName = context.frameChannelName,
            incomingWhisperAffinity = affinity,
            now = context.now,
            existingSelection = {
                chatType = self.ChatType,
                target = self.Target,
                language = self.Language,
                channelName = self.ChannelName,
            },
        })

        if affinity and (resolved.chatType == "WHISPER" or resolved.chatType == "BN_WHISPER")
            and hasValue(affinity.target) and resolved.target == affinity.target then
            self.incomingWhisperAffinity = nil
        end

        self.ChatType = resolved.chatType
        self.Target = resolved.target
        self.Language = resolved.language
        self.ChannelName = resolved.channelName

        return resolved
    end

    function sim:send()
        self.LastUsed = {
            chatType = self.ChatType,
            target = self.Target,
            language = self.Language,
        }
    end

    return sim
end

local function buildEvent(rng, now)
    local modeRoll = rng(100)
    local event = {
        now = now,
        pendingTabSwitch = nil,
        frameChatType = nil,
        frameChatTarget = nil,
        frameChannelName = nil,
        blizzHasTarget = false,
        blizzType = nil,
        blizzTell = nil,
        blizzChan = nil,
        incoming = nil,
        doSend = false,
        expectWhisperContinuation = false,
    }

    if modeRoll <= 38 then
        local targetless = (rng(100) <= 65)
        event.pendingTabSwitch = {
            chatType = "WHISPER",
            target = targetless and nil or choose(rng, players),
        }
        event.frameChatType = "WHISPER"
        event.frameChatTarget = event.pendingTabSwitch.target
        event.expectWhisperContinuation = targetless
    elseif modeRoll <= 54 then
        event.pendingTabSwitch = {
            chatType = "BN_WHISPER",
            target = (rng(100) <= 35) and nil or choose(rng, bnetPlayers),
        }
        event.frameChatType = "BN_WHISPER"
        event.frameChatTarget = event.pendingTabSwitch.target
    elseif modeRoll <= 74 then
        local ch = choose(rng, channels)
        event.pendingTabSwitch = {
            chatType = "CHANNEL",
            target = ch.target,
            channelName = ch.channelName,
        }
        event.frameChatType = "CHANNEL"
        event.frameChatTarget = ch.target
        event.frameChannelName = ch.channelName
    else
        local ct = choose(rng, nonTargetModes)
        event.pendingTabSwitch = {
            chatType = ct,
            target = "LEAK_TARGET",
            channelName = "LEAK_CHANNEL",
        }
        event.frameChatType = ct
    end

    if rng(100) <= 55 then
        event.doSend = true
    end

    if rng(100) <= 45 then
        local kind = (rng(100) <= 70) and "WHISPER" or "BN_WHISPER"
        local sender = (kind == "WHISPER") and choose(rng, playersRealm) or choose(rng, bnetPlayers)
        local age = (rng(100) <= 55) and 0.08 or 6.4
        event.incoming = {
            event = (kind == "WHISPER") and "CHAT_MSG_WHISPER" or "CHAT_MSG_BN_WHISPER",
            sender = sender,
            age = age,
            kind = kind,
        }
    end

    if rng(100) <= 22 then
        event.blizzHasTarget = true
        local r = rng(3)
        if r == 1 then
            event.blizzType = "WHISPER"
            event.blizzTell = choose(rng, playersRealm)
        elseif r == 2 then
            event.blizzType = "BN_WHISPER"
            event.blizzTell = choose(rng, bnetPlayers)
        else
            local ch = choose(rng, channels)
            event.blizzType = "CHANNEL"
            event.blizzChan = ch.target
        end
    end

    return event
end

local function applyFault(sim, event, faultRng, intensity)
    local tags = {}
    local p = faultRng(100)
    if p > intensity then
        return tags
    end

    local faultType = faultRng(8)
    if faultType == 1 then
        -- Poison LastUsed with impossible targeted payload.
        sim.LastUsed = { chatType = "WHISPER", target = nil, language = nil }
        table.insert(tags, "lastused-poison-whisper-nil")
    elseif faultType == 2 then
        -- Cross-wire pending switch and frame context.
        if event.pendingTabSwitch then
            event.pendingTabSwitch.chatType = "WHISPER"
            event.pendingTabSwitch.target = nil
            event.frameChatType = "BN_WHISPER"
            event.frameChatTarget = choose(faultRng, bnetPlayers)
            table.insert(tags, "pending-frame-crosswire")
        end
    elseif faultType == 3 then
        -- Claim Blizzard has target but blank target fields.
        event.blizzHasTarget = true
        event.blizzType = "WHISPER"
        event.blizzTell = nil
        event.blizzChan = nil
        table.insert(tags, "blizz-target-blank")
    elseif faultType == 4 then
        -- Feed malformed affinity kind/target pair.
        sim.incomingWhisperAffinity = {
            chatType = "WHISPER",
            target = "",
            t = event.now + 2,
        }
        table.insert(tags, "malformed-affinity-empty-target")
    elseif faultType == 5 then
        -- Create stale-but-present affinity with wrong type.
        sim.incomingWhisperAffinity = {
            chatType = "BN_WHISPER",
            target = choose(faultRng, bnetPlayers),
            t = event.now - 30,
        }
        table.insert(tags, "stale-affinity-wrong-type")
    elseif faultType == 6 then
        -- Force frame whisper target dropout under whisper tab switch.
        if event.pendingTabSwitch and event.pendingTabSwitch.chatType == "WHISPER" then
            event.frameChatType = "WHISPER"
            event.frameChatTarget = nil
            table.insert(tags, "forced-frame-target-dropout")
        end
    elseif faultType == 7 then
        -- Corrupt prior UI state before resolve.
        sim.ChatType = "CHANNEL"
        sim.Target = "2"
        sim.ChannelName = "Trade"
        table.insert(tags, "pre-open-ui-state-corruption")
    else
        -- Convert a non-target pending mode into stale target carrier.
        if event.pendingTabSwitch then
            event.pendingTabSwitch.chatType = choose(faultRng, nonTargetModes)
            event.pendingTabSwitch.target = "STALE_TARGET"
            event.pendingTabSwitch.channelName = "STALE_CHANNEL"
            table.insert(tags, "stale-target-injection")
        end
    end

    return tags
end

local function postResolveFault(sim, faultRng, intensity)
    local tags = {}
    if faultRng(100) > math.floor(intensity * 0.35) then
        return tags
    end

    local mode = faultRng(3)
    if mode == 1 and not isWhisperType(sim.ChatType) and sim.ChatType ~= "CHANNEL" then
        sim.Target = "CORRUPTED_POST_WRITE"
        table.insert(tags, "post-resolve-target-flip")
    elseif mode == 2 and sim.ChatType == "WHISPER" then
        sim.ChatType = "SAY"
        sim.Target = nil
        table.insert(tags, "post-resolve-whisper-collapse")
    elseif mode == 3 and sim.ChatType == "CHANNEL" then
        sim.Target = nil
        table.insert(tags, "post-resolve-channel-target-drop")
    end

    return tags
end

local function runCampaign(policy, config)
    local baseSeed = hashSeed(config.name)
    local eventRngSeed = baseSeed + 11
    local faultRngSeed = baseSeed + 97

    math.randomseed(eventRngSeed)
    local eventRng = math.random
    math.randomseed(faultRngSeed)
    local faultRng = math.random

    local control = newSim(policy)
    local faulted = newSim(policy)

    local stats = {
        name = config.name,
        iterations = config.iterations,
        faultsInjected = 0,
        faultTags = {},
        hardFailures = {},
        divergenceCount = 0,
        divergenceByType = {
            chatType = 0,
            target = 0,
            channelName = 0,
        },
        maxRecoverySteps = 0,
        activeDivergenceSpan = 0,
        unrecoveredAtEnd = false,
        whisperCollapseVsControl = 0,
        stickyDriftEvents = 0,
    }

    local inDivergence = false
    local divergenceStart = nil
    local now = 1000

    for i = 1, config.iterations do
        local dt = (1 / config.fps) + (eventRng(1000) / 1000) * ((1 / config.fps) * (config.jitterMultiplier or 0.6))
        now = now + dt
        local event = buildEvent(eventRng, now)

        if event.incoming then
            local sender = event.incoming.sender
            local incomingAt = now - event.incoming.age
            control:captureIncoming(event.incoming.event, sender, event.frameChatType, event.frameChatTarget, incomingAt)
            faulted:captureIncoming(event.incoming.event, sender, event.frameChatType, event.frameChatTarget, incomingAt)
        end

        local injected = applyFault(faulted, event, faultRng, config.faultIntensity)
        if #injected > 0 then
            stats.faultsInjected = stats.faultsInjected + #injected
            for _, tag in ipairs(injected) do
                stats.faultTags[tag] = (stats.faultTags[tag] or 0) + 1
            end
        end

        local controlResult = control:open(event)
        local faultResult = faulted:open(event)

        local postFaults = postResolveFault(faulted, faultRng, config.faultIntensity)
        if #postFaults > 0 then
            stats.faultsInjected = stats.faultsInjected + #postFaults
            for _, tag in ipairs(postFaults) do
                stats.faultTags[tag] = (stats.faultTags[tag] or 0) + 1
            end
            -- Re-read faulted state as effective output after corruption.
            faultResult = {
                chatType = faulted.ChatType,
                target = faulted.Target,
                channelName = faulted.ChannelName,
            }
        end

        local controlOk, controlWhy = validateSelection(controlResult)
        local faultOk, faultWhy = validateSelection(faultResult)

        if not controlOk then
            stats.hardFailures["control:" .. controlWhy] = (stats.hardFailures["control:" .. controlWhy] or 0) + 1
        end
        if not faultOk then
            stats.hardFailures["faulted:" .. faultWhy] = (stats.hardFailures["faulted:" .. faultWhy] or 0) + 1
        end

        if not sameSelection(controlResult, faultResult) then
            stats.divergenceCount = stats.divergenceCount + 1
            if controlResult.chatType ~= faultResult.chatType then
                stats.divergenceByType.chatType = stats.divergenceByType.chatType + 1
            end
            if controlResult.target ~= faultResult.target then
                stats.divergenceByType.target = stats.divergenceByType.target + 1
            end
            if controlResult.channelName ~= faultResult.channelName then
                stats.divergenceByType.channelName = stats.divergenceByType.channelName + 1
            end

            if not inDivergence then
                inDivergence = true
                divergenceStart = i
            end
        elseif inDivergence then
            local span = i - divergenceStart
            if span > stats.maxRecoverySteps then
                stats.maxRecoverySteps = span
            end
            inDivergence = false
            divergenceStart = nil
        end

        if controlResult.chatType == "WHISPER" and faultResult.chatType == "SAY" then
            stats.whisperCollapseVsControl = stats.whisperCollapseVsControl + 1
        end

        if control.LastUsed.chatType ~= faulted.LastUsed.chatType
            or control.LastUsed.target ~= faulted.LastUsed.target then
            stats.stickyDriftEvents = stats.stickyDriftEvents + 1
        end

        if event.doSend then
            control:send()
            faulted:send()
        end
    end

    if inDivergence and divergenceStart then
        stats.unrecoveredAtEnd = true
        stats.activeDivergenceSpan = config.iterations - divergenceStart + 1
        if stats.activeDivergenceSpan > stats.maxRecoverySteps then
            stats.maxRecoverySteps = stats.activeDivergenceSpan
        end
    end

    return stats
end

local function printTableMap(prefix, m)
    local keys = {}
    for k in pairs(m) do
        table.insert(keys, k)
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        print(string.format("  %s%s=%d", prefix, k, m[k]))
    end
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

local campaigns = {
    {
        name = "adversarial-extreme-1fps",
        iterations = 12000,
        fps = 1,
        faultIntensity = 78,
        jitterMultiplier = 1.2,
    },
    {
        name = "adversarial-extreme-2fps",
        iterations = 12000,
        fps = 2,
        faultIntensity = 82,
        jitterMultiplier = 1.0,
    },
    {
        name = "adversarial-extreme-4fps",
        iterations = 12000,
        fps = 4,
        faultIntensity = 86,
        jitterMultiplier = 0.9,
    },
}

print("Adversarial fault-injection campaign")
print("Control and faulted simulations run on same event stream.\n")

for _, c in ipairs(campaigns) do
    print("Campaign: " .. c.name)
    local stats = runCampaign(policy, c)
    print(string.format("  iterations=%d faultsInjected=%d divergenceCount=%d", stats.iterations, stats.faultsInjected, stats.divergenceCount))
    print(string.format("  divergenceByType: chatType=%d target=%d channelName=%d", stats.divergenceByType.chatType, stats.divergenceByType.target, stats.divergenceByType.channelName))
    print(string.format("  maxRecoverySteps=%d unrecoveredAtEnd=%s activeDivergenceSpan=%d", stats.maxRecoverySteps, tostring(stats.unrecoveredAtEnd), stats.activeDivergenceSpan))
    print(string.format("  whisperCollapseVsControl=%d stickyDriftEvents=%d", stats.whisperCollapseVsControl, stats.stickyDriftEvents))

    local hardFailureTotal = 0
    for _, n in pairs(stats.hardFailures) do
        hardFailureTotal = hardFailureTotal + n
    end
    print("  hardFailureTotal=" .. hardFailureTotal)
    if hardFailureTotal > 0 then
        print("  hardFailureTypes:")
        printTableMap("", stats.hardFailures)
    end

    print("  faultTagHistogram:")
    printTableMap("", stats.faultTags)
    print()
end

print(string.rep("-", 72))
print("Adversarial campaign complete.")
print("Use divergence, recovery span, and hard failure types to prioritize mitigations.")
