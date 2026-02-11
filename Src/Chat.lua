--[[
    Chat.lua — Yapper 1.0.0
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
    SAY            = true,
    EMOTE          = true,
    YELL           = true,
    PARTY          = true,
    RAID           = true,
    RAID_WARNING   = true,
    INSTANCE_CHAT  = true,
    GUILD          = true,
    OFFICER        = true,
    CHANNEL        = true,
}

-- Types that get truncated, not split (long whispers confuse recipients).
local TRUNCATE_ONLY = {
    WHISPER    = true,
    BN_WHISPER = true,
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
            return false
        end)
    end

    if YapperTable.Router then YapperTable.Router:Init() end
    if YapperTable.Queue  then YapperTable.Queue:Init()  end
end

-- ---------------------------------------------------------------------------
-- Main entry point (called by EditBox)
-- ---------------------------------------------------------------------------

--- Process a message from the user.
function Chat:OnSend(text, chatType, language, target)
    local cfg   = YapperTable.Config and YapperTable.Config.Chat or {}
    local limit = cfg.CHARACTER_LIMIT or 255

    -- Don't interleave with an active queue.
    if YapperTable.Queue and YapperTable.Queue.Active then
        YapperTable.Utils:Print("Please wait — still sending previous message.")
        return
    end

    if YapperTable.History then
        YapperTable.History:AddChatHistory(text)
    end

    -- Whispers: truncate, don't split.
    if TRUNCATE_ONLY[chatType] then
        if #text > limit then
            text = text:sub(1, limit)
            YapperTable.Error:PrintError("CHAT_WHISPER_TRUNCATED", limit)
        end
        self:DirectSend(text, chatType, language, target)
        return
    end

    -- Short — send directly.
    if #text <= limit then
        self:DirectSend(text, chatType, language, target)
        return
    end

    -- Unsupported type — truncate with warning.
    if not SPLITTABLE[chatType] then
        YapperTable.Error:PrintError("BAD_STRING",
            "Unsupported chat type for splitting: " .. tostring(chatType))
        self:DirectSend(text:sub(1, limit), chatType, language, target)
        return
    end

    -- Long message — split and queue.
    local Chunking = YapperTable.Chunking
    if not Chunking then
        YapperTable.Error:PrintError("UNKNOWN", "Chunking module missing")
        self:DirectSend(text:sub(1, limit), chatType, language, target)
        return
    end

    local chunks = Chunking:Split(text, limit)

    -- If a linked message needs chunking, abort — links can't safely
    -- survive the split (WoW limits links per message).
    if #chunks > 1 and text:find("|H") then
        YapperTable.Utils:Print(
            "|cFFFF4444Message with links exceeds the chat limit "
            .. "and can't be split. Shorten your message or remove a link. "
            .. "(Recover via chat history: Alt+Up)|r")
        return
    end

    -- Edge case: single chunk after split.
    if #chunks <= 1 then
        self:DirectSend(chunks[1] or text, chatType, language, target)
        return
    end

    -- Feed to Queue for ordered delivery.
    local Q = YapperTable.Queue
    if not Q then
        -- No queue — fire all at once.
        for _, chunk in ipairs(chunks) do
            self:DirectSend(chunk, chatType, language, target)
        end
        return
    end

    Q:Enqueue(chunks, chatType, language, target)
    Q:Flush()
end

--- Send a single message through Router (or raw fallback).
function Chat:DirectSend(msg, chatType, language, target)
    if YapperTable.Router then
        YapperTable.Router:Send(msg, chatType, language, target)
    else
        C_ChatInfo.SendChatMessage(msg, chatType, language, target)
    end
end
