--[[
    Chat.lua
    Orchestrator: wires EditBox, Chunking, Queue, and Router together.

    EditBox.OnSend → Chat:OnSend
      Short message        → Router:Send
      Whisper / BNet       → Truncate + Router:Send
      Long message          → Chunking:Split → Queue:Enqueue + Flush
]]

local YapperName, YapperTable = ...

local Chat = {}
YapperTable.Chat = Chat
local State = YapperTable.State

-- Types we split for.
local SPLITTABLE = {
    SAY                  = true,
    EMOTE                = true,
    YELL                 = true,
    WHISPER              = true,
    BN_WHISPER           = true,
    PARTY                = true,
    PARTY_LEADER         = true,
    RAID                 = true,
    RAID_LEADER          = true,
    RAID_WARNING         = true,
    INSTANCE_CHAT        = true,
    INSTANCE_CHAT_LEADER = true,
    GUILD                = true,
    OFFICER              = true,
    CLUB                 = true,
    CHANNEL              = true,
}

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

function Chat:Init()
    if YapperTable.EditBox then
        YapperTable.EditBox:SetOnSend(function(text, chatType, language, target)
            self:OnSend(text, chatType, language, target)
        end)
    end

    -- Let Queue suppress the overlay to grab the hardware event for continuation.
    if YapperTable.EditBox then
        YapperTable.EditBox:SetPreShowCheck(function(blizzEditBox)
            if YapperTable.Queue and YapperTable.Queue:TryContinue() then
                return true
            end
            return false
        end)
    end

    if YapperTable.Router then YapperTable.Router:Init() end
    if YapperTable.Queue then YapperTable.Queue:Init() end

    -- Initialise bridges
    if YapperTable.TypingTrackerBridge then
        YapperTable.TypingTrackerBridge:UpdateState(nil)
    end
    if YapperTable.RPPrefixBridge then
        YapperTable.RPPrefixBridge:Init()
    end
    if YapperTable.WIMBridge then
        YapperTable.WIMBridge:Init()
    end
    if YapperTable.CEBEBridge then
        YapperTable.CEBEBridge:Init()
    end

    -- Hard Recovery Slash Commands
    -- If you can't focus Yapper this is useless, BUT
    -- you'd put these commands in a macro if you're having the issue
    -- to see if it corrects your problem.
    _G.SLASH_YAPPERFIX1 = "/yapperfix"
    _G.SLASH_YAPPERFIX2 = "/yapperrefocus"
    _G.SLASH_YAPPERFIX3 = "/yfix"
    SlashCmdList["YAPPERFIX"] = function()
        if YapperTable.EditBox and YapperTable.EditBox.HardRefocus then
            YapperTable.EditBox:HardRefocus()
            YapperTable.Utils:Print("Hard focus reclaim initiated.")
        end
    end
end

-- ---------------------------------------------------------------------------
-- Main entry point (called by EditBox)
-- ---------------------------------------------------------------------------

--- Process a message from the user.
function Chat:OnSend(text, chatType, language, target)
    -- Final pre-dispatch guard: if chat lockdown activated between key handling
    -- and this send call, handoff and keep the message as a draft.
    if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
        local eb = YapperTable.EditBox
        if eb and eb.HandoffToBlizzard and eb.Overlay and eb.Overlay:IsShown() then
            eb:HandoffToBlizzard(false, true)
        end
        return false
    end

    -- PRE_SEND filter: external addons can modify or cancel the send.
    local API = YapperTable.API
    if API then
        local payload = API:RunFilter("PRE_SEND", {
            text     = text,
            chatType = chatType,
            language = language,
            target   = target,
        })
        if payload == false then return false end
        text     = payload.text
        chatType = payload.chatType
        language = payload.language
        target   = payload.target
    end

    local cfg    = YapperTable.Config and YapperTable.Config.Chat or {}
    local limit  = cfg.CHARACTER_LIMIT or 255

    if YapperTable.History then
        YapperTable.History:AddChatHistory(text, chatType, target)
    end

    -- If a multi-chunk queue is stalled waiting for hardware Enter, advance
    -- it now (the keybind already routed here via OnSend).  The new message
    -- will be enqueued below and will follow the current sequence.
    if State and State:IsBusy() then
        local Q = YapperTable.Queue
        if Q and Q.NeedsContinue then
            Q:OnOpenChat()
        end
    end

    -- Short — send directly, UNLESS it contains newlines (which Blizzard truncates).
    if #text <= limit and not text:find("\n", 1, true) then
        return self:DirectSend(text, chatType, language, target)
    end

    -- If message is long but the chat type is not splittable, handle
    -- according to type: whispers are truncated, unknown types are an error.
    if not SPLITTABLE[chatType] then
        if chatType == "WHISPER" or chatType == "BN_WHISPER" then
            -- Truncate whisper to limit and send.
            return self:DirectSend(text:sub(1, limit), chatType, language, target)
        end
        YapperTable.Error:PrintError("BAD_CHAT_TYPE", tostring(chatType))
        return false
    end

    -- Long message — split and queue.
    local Chunking = YapperTable.Chunking
    if not Chunking then
        YapperTable.Error:PrintError("UNKNOWN", "Chunking module missing")
        return self:DirectSend(text:sub(1, limit), chatType, language, target)
    end

    -- PRE_CHUNK filter: external addons can modify text before splitting.
    local continuationPrefix = nil
    if API then
        local chunkPayload = API:RunFilter("PRE_CHUNK", {
            text     = text,
            limit    = limit,
            chatType = chatType,
        })
        if chunkPayload == false then return false end
        text  = chunkPayload.text
        limit = chunkPayload.limit
        continuationPrefix = chunkPayload.continuationPrefix
    end

    local chunks = Chunking:Split(text, limit, true, nil, nil, nil, continuationPrefix)



    -- Relax link-splitting restriction.
    -- Chunking:Split is link-aware and keeps hyperlinks atomic, so splitting is safe.

    -- Edge case: single chunk after split.
    if #chunks <= 1 then
        return self:DirectSend(chunks[1] or text, chatType, language, target)
    end

    -- Feed to Queue for ordered delivery.
    local Q = YapperTable.Queue

    if not Q then
        -- No queue — fire all at once.
        for _, chunk in ipairs(chunks) do
            if self:DirectSend(chunk, chatType, language, target) == false then
                return false
            end
        end
        return true
    end

    Q:Enqueue(chunks, chatType, language, target)
    Q:Flush(true)
    return true
end

--- Send a single message through Router (or raw fallback).
function Chat:DirectSend(msg, chatType, language, target)
    -- Last-chance guard: lockdown might flip after OnSend's initial check.
    if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
        local eb = YapperTable.EditBox
        if eb and eb.HandoffToBlizzard and eb.Overlay and eb.Overlay:IsShown() then
            eb:HandoffToBlizzard(false, true)
        end
        return false
    end

    -- Record outgoing message for adaptive learning
    if YapperTable.Spellcheck and YapperTable.Spellcheck.YAS then
        local sc = YapperTable.Spellcheck
        local YAS = sc.YAS
        local locale = sc:GetLocale()
        YAS:RecordUsage(msg, locale)

        -- Check for "ignored" misspellings in the outgoing message
        local dict = sc:GetDictionary()
        if dict then
            local typos = sc:CollectMisspellings(msg, dict)
            if typos then
                for _, item in ipairs(typos) do
                    local word = msg:sub(item.startPos, item.endPos)
                    YAS:RecordIgnored(word, locale)
                end
            end

            -- Also record correctly affixed words so YAS can auto-learn them
            -- into the user's personal dictionary over time.
            local affixMatches = sc:CollectAffixMatches(msg, dict)
            if affixMatches then
                for _, item in ipairs(affixMatches) do
                    YAS:RecordIgnored(item.word, locale)
                end
            end
        end
    end

    -- PRE_DELIVER filter: external addons can claim the message.
    local API = YapperTable.API
    if API then
        local deliverPayload = API:RunFilter("PRE_DELIVER", {
            text     = msg,
            chatType = chatType,
            language = language,
            target   = target,
        })
        if deliverPayload == false then
            -- An addon claimed this message via delegation.
            local owner = API._lastCancelOwner
            if API._createClaim then
                local handle = API:_createClaim(msg, chatType, language, target, owner)
                API:Fire("POST_CLAIMED", handle, msg, chatType, language, target)
            end
            return false
        end
        -- Allow the filter to modify fields.
        msg      = deliverPayload.text or msg
        chatType = deliverPayload.chatType or chatType
        language = deliverPayload.language or language
        target   = deliverPayload.target or target
    end

    if YapperTable.Router then
        if YapperTable.Router:Send(msg, chatType, language, target) == false then
            return false
        end
    else
        if C_ChatInfo and C_ChatInfo.SendChatMessage then
            C_ChatInfo.SendChatMessage(msg, chatType, language, target)
        else
            return false
        end
    end

    -- POST_SEND callback: notify external addons.
    if API then
        API:Fire("POST_SEND", msg, chatType, language, target)
    end

    return true
end
