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

-- Types we split for.
local SPLITTABLE = {
    SAY           = true,
    EMOTE         = true,
    YELL          = true,
    WHISPER       = true,
    BN_WHISPER    = true,
    PARTY         = true,
    PARTY_LEADER  = true,
    RAID          = true,
    RAID_LEADER   = true,
    RAID_WARNING  = true,
    INSTANCE_CHAT = true,
    INSTANCE_CHAT_LEADER = true,
    GUILD         = true,
    OFFICER       = true,
    CLUB          = true,
    CHANNEL       = true,
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

    -- Let Queue suppress the overlay to grab the hardware event.
    if YapperTable.EditBox then
        YapperTable.EditBox:SetPreShowCheck(function(blizzEditBox)
            if YapperTable.Queue and YapperTable.Queue:TryContinue() then
                return true
            end

            -- When Gopher is handling delivery, suppress the overlay until
            -- its queue has drained so we don't interleave new input.
            local bridge = YapperTable.GopherBridge
            if bridge and bridge:IsActive() and bridge:IsBusy() then
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
end

-- ---------------------------------------------------------------------------
-- Main entry point (called by EditBox)
-- ---------------------------------------------------------------------------

--- Process a message from the user.
function Chat:OnSend(text, chatType, language, target)
    -- PRE_SEND filter: external addons can modify or cancel the send.
    local API = YapperTable.API
    if API then
        local payload = API:RunFilter("PRE_SEND", {
            text     = text,
            chatType = chatType,
            language = language,
            target   = target,
        })
        if payload == false then return end
        text     = payload.text
        chatType = payload.chatType
        language = payload.language
        target   = payload.target
    end

    local cfg    = YapperTable.Config and YapperTable.Config.Chat or {}
    local limit  = cfg.CHARACTER_LIMIT or 255

    -- Non-splittable types (e.g. WHISPER/BN_WHISPER) are allowed; for long
    -- whispers we truncate to the character limit rather than queueing.

    -- Don't interleave with an active Yapper queue (not relevant when
    -- GopherBridge is active — Gopher manages its own queue).
    local bridge = YapperTable.GopherBridge
    if not (bridge and bridge:IsActive()) then
        if YapperTable.Queue and YapperTable.Queue.Active then
            YapperTable.Utils:Print("Please wait — still sending previous message.")
            return
        end
    end

    if YapperTable.History then
        YapperTable.History:AddChatHistory(text, chatType, target)
    end

    -- Short — send directly.
    if #text <= limit then
        self:DirectSend(text, chatType, language, target)
        return
    end

    -- If message is long but the chat type is not splittable, handle
    -- according to type: whispers are truncated, unknown types are an error.
    if not SPLITTABLE[chatType] then
        if chatType == "WHISPER" or chatType == "BN_WHISPER" then
            -- Truncate whisper to limit and send.
            self:DirectSend(text:sub(1, limit), chatType, language, target)
            return
        end
        YapperTable.Error:PrintError("BAD_CHAT_TYPE", tostring(chatType))
        return
    end

    -- Long message — split and queue.
    local Chunking = YapperTable.Chunking
    if not Chunking then
        YapperTable.Error:PrintError("UNKNOWN", "Chunking module missing")
        self:DirectSend(text:sub(1, limit), chatType, language, target)
        return
    end

    -- PRE_CHUNK filter: external addons can modify text before splitting.
    if API then
        local chunkPayload = API:RunFilter("PRE_CHUNK", {
            text  = text,
            limit = limit,
        })
        if chunkPayload == false then return end
        text  = chunkPayload.text
        limit = chunkPayload.limit
    end

    local chunks = Chunking:Split(text, limit)



    -- Relax link-splitting restriction.
    -- Chunking:Split is link-aware and keeps hyperlinks atomic, so splitting is safe.

    -- Edge case: single chunk after split.
    if #chunks <= 1 then
        self:DirectSend(chunks[1] or text, chatType, language, target)
        return
    end

    -- Feed to Queue for ordered delivery.
    local Q = YapperTable.Queue

    -- When GopherBridge is active, Gopher has its own queue / throttle /
    -- confirmation system.  Send each chunk directly through Router →
    -- GopherBridge; Gopher will serialise them for us.
    local bridge = YapperTable.GopherBridge
    if bridge and bridge:IsActive() then
        for _, chunk in ipairs(chunks) do
            self:DirectSend(chunk, chatType, language, target)
        end
        return
    end

    if not Q then
        -- No queue and no Gopher — fire all at once.
        for _, chunk in ipairs(chunks) do
            self:DirectSend(chunk, chatType, language, target)
        end
        return
    end

    Q:Enqueue(chunks, chatType, language, target)
    Q:Flush(true)
end

--- Send a single message through Router (or raw fallback).
function Chat:DirectSend(msg, chatType, language, target)
    -- Record outgoing message for adaptive learning
    if YapperTable.Spellcheck and YapperTable.Spellcheck.YALLM then
        local YALLM = YapperTable.Spellcheck.YALLM
        YALLM:RecordUsage(msg)
        
        -- Check for "ignored" misspellings in the outgoing message
        local sc = YapperTable.Spellcheck
        local dict = sc:GetDictionary()
        if dict then
            local typos = sc:CollectMisspellings(msg, dict)
            if typos then
                for _, item in ipairs(typos) do
                    local word = msg:sub(item.startPos, item.endPos)
                    YALLM:RecordIgnored(word)
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
            return
        end
        -- Allow the filter to modify fields.
        msg      = deliverPayload.text     or msg
        chatType = deliverPayload.chatType or chatType
        language = deliverPayload.language or language
        target   = deliverPayload.target   or target
    end

    if YapperTable.Router then
        YapperTable.Router:Send(msg, chatType, language, target)
    else
        C_ChatInfo.SendChatMessage(msg, chatType, language, target)
    end

    -- POST_SEND callback: notify external addons.
    if API then
        API:Fire("POST_SEND", msg, chatType, language, target)
    end
end
