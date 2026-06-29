--[[
    Policies/ChannelPolicy.lua
    Central policy helpers for channel selection and sticky persistence.
    Passive module: declares policy methods only; performs no startup work.

    Phase 1 goal: provide a single hub for policy decisions while preserving
    current behavior at existing call sites.
]]

local _, YapperTable = ...

local ChannelPolicy = {}
YapperTable.ChannelPolicy = ChannelPolicy

local type = type

local function IsWhisperType(ct)
    return ct == "WHISPER" or ct == "BN_WHISPER"
end

local function IsTargetedType(ct)
    return IsWhisperType(ct) or ct == "CHANNEL"
end

local function BuildSelection(chatType, language, target, channelName)
    if not chatType or chatType == "" then
        chatType = "SAY"
    end

    if IsWhisperType(chatType) then
        if not target or target == "" then
            chatType = "SAY"
            target = nil
            channelName = nil
        end
    elseif chatType == "CHANNEL" then
        if not target or target == "" then
            chatType = "SAY"
            target = nil
            channelName = nil
        end
    else
        -- Non-target chat types must never carry stale whisper/channel targets.
        target = nil
        channelName = nil
    end

    return {
        chatType = chatType,
        language = language,
        target = target,
        channelName = channelName,
    }
end

local function BuildStickyFallbackLanguage(currentLanguage, previousLastUsed)
    if currentLanguage ~= nil then
        return currentLanguage
    end
    return previousLastUsed and previousLastUsed.language or nil
end

--- Decide the persisted LastUsed payload for the current selection.
--- Keeps behavior parity with existing sticky settings logic.
---@param current table  { chatType, target, language }
---@param previous table|nil Previous LastUsed table.
---@param cfg table|nil EditBox config table.
---@param groupChatTypes table|nil GROUP_CHAT_TYPES map.
---@return table|nil
function ChannelPolicy:BuildPersistedLastUsed(current, previous, cfg, groupChatTypes)
    if type(current) ~= "table" then
        return nil
    end

    local ct = current.chatType
    if not ct or ct == "" then
        return nil
    end

    local editCfg = cfg or {}
    local stickyAll = (editCfg.StickyChannel ~= false)
    local stickyGroup = (editCfg.StickyGroupChannel ~= false)

    local keepSticky = stickyAll
        or (stickyGroup and type(groupChatTypes) == "table" and groupChatTypes[ct])

    if keepSticky then
        local persistedTarget = IsTargetedType(ct) and current.target or nil
        return {
            chatType = ct,
            target = persistedTarget,
            language = current.language,
        }
    end

    return {
        chatType = "SAY",
        target = nil,
        language = BuildStickyFallbackLanguage(current.language, previous),
    }
end

--- Resolve the open channel selection from current context.
--- Preserves existing Show() priority order.
---@param context table
---@return table  { chatType, language, target, channelName }
function ChannelPolicy:ResolveOpenSelection(context)
    local pendingTabSwitch = context.pendingTabSwitch
    local explicitChannel = context.explicitChannel
    local lockSavedDraft = context.lockSavedDraft
    local blizzHasTarget = context.blizzHasTarget
    local blizzType = context.blizzType
    local blizzTell = context.blizzTell
    local blizzChan = context.blizzChan
    local blizzLang = context.blizzLang
    local lastUsed = context.lastUsed
    local frameChatType = context.frameChatType
    local frameChatTarget = context.frameChatTarget
    local frameChannelName = context.frameChannelName

    if pendingTabSwitch and pendingTabSwitch.chatType then
        return BuildSelection(
            pendingTabSwitch.chatType,
            pendingTabSwitch.language or blizzLang or (lastUsed and lastUsed.language) or nil,
            pendingTabSwitch.target,
            pendingTabSwitch.channelName
        )
    end

    if explicitChannel and not lockSavedDraft then
        return BuildSelection(
            explicitChannel.chatType,
            blizzLang or (lastUsed and lastUsed.language) or nil,
            explicitChannel.target,
            explicitChannel.channelName
        )
    end

    if blizzHasTarget and not lockSavedDraft then
        return BuildSelection(
            blizzType,
            blizzLang or (lastUsed and lastUsed.language) or nil,
            blizzTell or blizzChan or nil,
            nil
        )
    end

    local lastUsedType = lastUsed and lastUsed.chatType or nil
    local lastUsedIsTargeted = (lastUsedType == "WHISPER"
        or lastUsedType == "BN_WHISPER"
        or lastUsedType == "CHANNEL")

    -- Frame context should only preempt LastUsed when LastUsed is a target-style
    -- channel (whisper/channel) that may be stale. Keep non-target sticky modes
    -- (e.g. EMOTE) intact.
    if frameChatType and not lockSavedDraft and lastUsedIsTargeted then
        local target = nil
        local channelName = nil
        if frameChatType == "WHISPER" or frameChatType == "BN_WHISPER" then
            target = frameChatTarget
            if not target or target == "" then
                -- A whisper type with no target is invalid; fall through.
                frameChatType = nil
            end
        elseif frameChatType == "CHANNEL" then
            target = frameChatTarget
            channelName = frameChannelName
            if not target or target == "" then
                frameChatType = nil
            end
        end

        if frameChatType then
            return BuildSelection(
                frameChatType,
                blizzLang or (lastUsed and lastUsed.language) or nil,
                target,
                channelName
            )
        end
    end

    if (lastUsed and lastUsed.chatType) and not lockSavedDraft then
        return BuildSelection(
            lastUsed.chatType,
            blizzLang or (lastUsed and lastUsed.language) or nil,
            lastUsed.target or blizzTell or blizzChan or nil,
            nil
        )
    end

    return BuildSelection(
        (lastUsed and lastUsed.chatType) or blizzType or "SAY",
        blizzLang or (lastUsed and lastUsed.language) or nil,
        (lastUsed and lastUsed.target) or blizzTell or blizzChan or nil,
        nil
    )
end
