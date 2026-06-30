#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_editbox_pipeline_breakpoint_sweep.lua
-- Purpose: push environment noise and frame throttling to extremes, and find
-- the first stress profile where invariants break.
-- Run from repo root:
--   lua tools/2.0testsuites/test_editbox_pipeline_breakpoint_sweep.lua
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

local function shallowCopy(t)
    local c = {}
    for k, v in pairs(t) do
        c[k] = v
    end
    return c
end

local function hashSeed(s)
    local h = 0
    for i = 1, #s do
        h = (h * 131 + s:byte(i)) % 2147483647
    end
    if h == 0 then h = 1 end
    return h
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

local function pickDt(cfg, rng)
    local base = 1 / cfg.fps
    local jitterFactor = 0.25 + (cfg.noise / 100) * 1.25
    local jitter = base * jitterFactor
    local sign = (rng(2) == 1) and -1 or 1
    local magnitude = (rng(1000) / 1000) * jitter
    local dt = base + sign * magnitude
    if dt < 0.0005 then dt = 0.0005 end
    return dt
end

local function newSimulator(policy)
    return {
        policy = policy,
        ChatType = "SAY",
        Target = nil,
        Language = nil,
        ChannelName = nil,
        LastUsed = { chatType = "SAY", target = nil, language = nil },
        incomingWhisperAffinity = nil,
        metrics = {
            opens = 0,
            sends = 0,
            receives = 0,
            captures = 0,
            consumes = 0,
            expires = 0,
            whisperPreserves = 0,
            sayFallbacks = 0,
            leaksPrevented = 0,
        },
    }
end

local function captureIncoming(sim, event, sender, activeFrameType, activeFrameTarget, now)
    sim.metrics.receives = sim.metrics.receives + 1
    if not hasValue(sender) then
        return
    end

    local kind = (event == "CHAT_MSG_BN_WHISPER") and "BN_WHISPER" or "WHISPER"
    local frameIsWhisper = activeFrameType == "WHISPER" or activeFrameType == "BN_WHISPER"
    if frameIsWhisper and hasValue(activeFrameTarget)
        and normaliseWhisperTarget(sender, kind) == normaliseWhisperTarget(activeFrameTarget, kind) then
        sim.incomingWhisperAffinity = {
            chatType = kind,
            target = activeFrameTarget,
            t = now,
        }
        sim.metrics.captures = sim.metrics.captures + 1
    end
end

local function openAndResolve(sim, context)
    sim.metrics.opens = sim.metrics.opens + 1

    local affinity = sim.incomingWhisperAffinity
    if affinity and affinity.t and context.now and (context.now - affinity.t) > 5 then
        sim.incomingWhisperAffinity = nil
        affinity = nil
        sim.metrics.expires = sim.metrics.expires + 1
    end

    local resolved = sim.policy:ResolveOpenSelection({
        pendingTabSwitch = context.pendingTabSwitch,
        explicitChannel = context.explicitChannel,
        lockSavedDraft = false,
        blizzHasTarget = context.blizzHasTarget,
        blizzType = context.blizzType,
        blizzTell = context.blizzTell,
        blizzChan = context.blizzChan,
        blizzLang = nil,
        lastUsed = sim.LastUsed,
        frameChatType = context.frameChatType,
        frameChatTarget = context.frameChatTarget,
        frameChannelName = context.frameChannelName,
        incomingWhisperAffinity = affinity,
        now = context.now,
        existingSelection = {
            chatType = sim.ChatType,
            target = sim.Target,
            language = sim.Language,
            channelName = sim.ChannelName,
        },
    })

    if affinity and (resolved.chatType == "WHISPER" or resolved.chatType == "BN_WHISPER")
        and hasValue(affinity.target) and resolved.target == affinity.target then
        sim.incomingWhisperAffinity = nil
        sim.metrics.consumes = sim.metrics.consumes + 1
    end

    if resolved.chatType == "SAY" then
        sim.metrics.sayFallbacks = sim.metrics.sayFallbacks + 1
    end

    if resolved.chatType ~= "CHANNEL" and not isWhisperType(resolved.chatType)
        and resolved.target == nil and resolved.channelName == nil then
        sim.metrics.leaksPrevented = sim.metrics.leaksPrevented + 1
    end

    if resolved.chatType == "WHISPER"
        and context.pendingTabSwitch and context.pendingTabSwitch.chatType == "WHISPER"
        and not hasValue(context.pendingTabSwitch.target)
        and context.frameChatType == "WHISPER"
        and hasValue(sim.Target) then
        sim.metrics.whisperPreserves = sim.metrics.whisperPreserves + 1
    end

    sim.ChatType = resolved.chatType
    sim.Target = resolved.target
    sim.Language = resolved.language
    sim.ChannelName = resolved.channelName

    return resolved
end

local function send(sim)
    sim.metrics.sends = sim.metrics.sends + 1
    sim.LastUsed = {
        chatType = sim.ChatType,
        target = sim.Target,
        language = sim.Language,
    }
end

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
            return false, "non-target-leaked-target"
        end
        if sel.channelName ~= nil then
            return false, "non-target-leaked-channel"
        end
    end

    return true
end

local function noisyBlizzContext(cfg, rng)
    local ctx = {
        blizzHasTarget = false,
        blizzType = nil,
        blizzTell = nil,
        blizzChan = nil,
    }

    local injectChance = math.floor(cfg.noise * 0.8)
    if rng(100) <= injectChance then
        ctx.blizzHasTarget = true
        local r = rng(3)
        if r == 1 then
            ctx.blizzType = "WHISPER"
            ctx.blizzTell = choose(rng, playersRealm)
        elseif r == 2 then
            ctx.blizzType = "BN_WHISPER"
            ctx.blizzTell = choose(rng, bnetPlayers)
        else
            local ch = choose(rng, channels)
            ctx.blizzType = "CHANNEL"
            ctx.blizzChan = ch.target
        end
    end

    return ctx
end

local function runRapid(sim, cfg, rng)
    local now = 1000
    local iterations = cfg.iterRapid

    for _ = 1, iterations do
        now = now + pickDt(cfg, rng)

        local modeRoll = rng(100)
        local pendingTabSwitch
        local frameChatType
        local frameChatTarget
        local frameChannelName

        if modeRoll <= (30 + math.floor(cfg.noise * 0.35)) then
            local targetlessChance = 50 + math.floor(cfg.noise * 0.35)
            local targetless = rng(100) <= targetlessChance
            pendingTabSwitch = {
                chatType = "WHISPER",
                target = targetless and nil or choose(rng, players),
            }
            frameChatType = "WHISPER"
            frameChatTarget = targetless and ((rng(100) <= cfg.noise) and nil or pendingTabSwitch.target) or pendingTabSwitch.target
            if targetless and rng(100) <= (20 + cfg.noise) then
                sim.ChatType = "WHISPER"
                sim.Target = choose(rng, players)
            end
        elseif modeRoll <= 50 then
            local bnTargetless = rng(100) <= (20 + math.floor(cfg.noise * 0.4))
            pendingTabSwitch = {
                chatType = "BN_WHISPER",
                target = bnTargetless and nil or choose(rng, bnetPlayers),
            }
            frameChatType = "BN_WHISPER"
            frameChatTarget = pendingTabSwitch.target
        elseif modeRoll <= 75 then
            local ch = choose(rng, channels)
            pendingTabSwitch = {
                chatType = "CHANNEL",
                target = (rng(100) <= math.floor(cfg.noise * 0.12)) and nil or ch.target,
                channelName = ch.channelName,
            }
            frameChatType = "CHANNEL"
            frameChatTarget = pendingTabSwitch.target
            frameChannelName = ch.channelName
        else
            pendingTabSwitch = {
                chatType = choose(rng, nonTargetModes),
                target = "LEAK_TARGET",
                channelName = "LEAK_CHANNEL",
            }
            frameChatType = pendingTabSwitch.chatType
        end

        local incomingChance = 10 + math.floor(cfg.noise * 0.7)
        if rng(100) <= incomingChance then
            local kind = (rng(100) <= 70) and "WHISPER" or "BN_WHISPER"
            local sender = (kind == "WHISPER") and choose(rng, playersRealm) or choose(rng, bnetPlayers)
            local ageBias = rng(100)
            local t
            if ageBias <= (50 - math.floor(cfg.noise * 0.2)) then
                t = now - 0.05
            else
                -- Low FPS and high noise force more stale timing windows.
                t = now - (5.5 + (cfg.noise / 100) * 3.0 + (1 / cfg.fps) * 4.0)
            end

            captureIncoming(
                sim,
                (kind == "WHISPER") and "CHAT_MSG_WHISPER" or "CHAT_MSG_BN_WHISPER",
                sender,
                frameChatType,
                frameChatTarget,
                t
            )
        end

        local blizz = noisyBlizzContext(cfg, rng)
        local resolved = openAndResolve(sim, {
            pendingTabSwitch = pendingTabSwitch,
            explicitChannel = nil,
            blizzHasTarget = blizz.blizzHasTarget,
            blizzType = blizz.blizzType,
            blizzTell = blizz.blizzTell,
            blizzChan = blizz.blizzChan,
            frameChatType = frameChatType,
            frameChatTarget = frameChatTarget,
            frameChannelName = frameChannelName,
            now = now,
        })

        local ok, reason = validateSelection(resolved)
        if not ok then
            return false, "rapid:" .. reason
        end

        local sendChance = 70 - math.floor(cfg.noise * 0.2)
        if sendChance < 35 then sendChance = 35 end
        if rng(100) <= sendChance then
            send(sim)
        end
    end

    return true
end

local function runSpam(sim, cfg, rng)
    local now = 5000
    local iterations = cfg.iterSpam

    for _ = 1, iterations do
        now = now + pickDt(cfg, rng)

        local kind = (rng(100) <= (55 + math.floor(cfg.noise * 0.25))) and "WHISPER" or "BN_WHISPER"
        local pool = (kind == "WHISPER") and playersRealm or bnetPlayers
        local sender = choose(rng, pool)

        local pendingTabSwitch = { chatType = kind, target = nil }
        local frameChatType = kind
        local frameChatTarget

        local patternRoll = rng(100)
        if patternRoll <= (35 + math.floor(cfg.noise * 0.2)) then
            frameChatTarget = sender
            captureIncoming(
                sim,
                (kind == "WHISPER") and "CHAT_MSG_WHISPER" or "CHAT_MSG_BN_WHISPER",
                sender,
                frameChatType,
                frameChatTarget,
                now
            )
        elseif patternRoll <= (70 + math.floor(cfg.noise * 0.15)) then
            frameChatTarget = sender
            captureIncoming(
                sim,
                (kind == "WHISPER") and "CHAT_MSG_WHISPER" or "CHAT_MSG_BN_WHISPER",
                sender,
                frameChatType,
                frameChatTarget,
                now - (5.8 + (cfg.noise / 100) * 3.5 + (1 / cfg.fps) * 4.5)
            )
        else
            frameChatTarget = choose(rng, pool)
            captureIncoming(
                sim,
                (kind == "WHISPER") and "CHAT_MSG_WHISPER" or "CHAT_MSG_BN_WHISPER",
                sender,
                frameChatType,
                frameChatTarget,
                now
            )
        end

        local aggressiveSendChance = 65 + math.floor(cfg.noise * 0.25)
        if aggressiveSendChance > 95 then aggressiveSendChance = 95 end
        if rng(100) <= aggressiveSendChance then
            sim.ChatType = kind
            sim.Target = (kind == "WHISPER") and choose(rng, players) or choose(rng, bnetPlayers)
            sim.ChannelName = nil
            send(sim)
        end

        local blizz = noisyBlizzContext(cfg, rng)
        local resolved = openAndResolve(sim, {
            pendingTabSwitch = pendingTabSwitch,
            explicitChannel = nil,
            blizzHasTarget = blizz.blizzHasTarget,
            blizzType = blizz.blizzType,
            blizzTell = blizz.blizzTell,
            blizzChan = blizz.blizzChan,
            frameChatType = frameChatType,
            frameChatTarget = frameChatTarget,
            frameChannelName = nil,
            now = now,
        })

        local ok, reason = validateSelection(resolved)
        if not ok then
            return false, "spam:" .. reason
        end
    end

    return true
end

local function formatMetrics(m)
    return string.format(
        "opens=%d sends=%d receives=%d captures=%d consumes=%d expires=%d whisperPreserves=%d sayFallbacks=%d leaksPrevented=%d",
        m.opens,
        m.sends,
        m.receives,
        m.captures,
        m.consumes,
        m.expires,
        m.whisperPreserves,
        m.sayFallbacks,
        m.leaksPrevented
    )
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

local noiseLevels = { 0, 20, 40, 60, 75, 85, 92, 97, 100 }
local fpsLevels = { 240, 120, 60, 30, 15, 8, 4, 2, 1 }

local profiles = {}
for _, noise in ipairs(noiseLevels) do
    for _, fps in ipairs(fpsLevels) do
        table.insert(profiles, {
            noise = noise,
            fps = fps,
            iterRapid = 3200,
            iterSpam = 3600,
        })
    end
end

print("EditBox pipeline breakpoint sweep\n")
print("Profiles: " .. tostring(#profiles) .. " (noise x fps)")
print("Stops at first invariant failure.\n")

local firstFailure = nil
local passed = 0

for _, profile in ipairs(profiles) do
    local profileName = string.format("noise=%d fps=%d", profile.noise, profile.fps)
    local seed = hashSeed(profileName)
    math.randomseed(seed)
    local rng = math.random

    local simRapid = newSimulator(policy)
    local okRapid, rapidReason = runRapid(simRapid, shallowCopy(profile), rng)

    local simSpam = newSimulator(policy)
    local okSpam, spamReason = runSpam(simSpam, shallowCopy(profile), rng)

    if not okRapid or not okSpam then
        firstFailure = {
            profile = profile,
            reason = rapidReason or spamReason,
            rapidMetrics = simRapid.metrics,
            spamMetrics = simSpam.metrics,
        }
        print("FAIL @ " .. profileName .. " reason=" .. tostring(firstFailure.reason))
        break
    end

    passed = passed + 1
    print(string.format(
        "PASS @ %s | rapid{%s} spam{%s}",
        profileName,
        formatMetrics(simRapid.metrics),
        formatMetrics(simSpam.metrics)
    ))
end

print("\n" .. string.rep("-", 72))
if firstFailure then
    print("First failing profile found:")
    print(string.format("  noise=%d fps=%d reason=%s", firstFailure.profile.noise, firstFailure.profile.fps, tostring(firstFailure.reason)))
    print("  rapid metrics: " .. formatMetrics(firstFailure.rapidMetrics))
    print("  spam  metrics: " .. formatMetrics(firstFailure.spamMetrics))
    os.exit(1)
else
    print(string.format("No invariant break found across %d/%d profiles.", passed, #profiles))
    print("Current policy remains stable under tested extreme noise/FPS sweep.")
end
