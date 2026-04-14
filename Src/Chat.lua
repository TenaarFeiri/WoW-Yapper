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
    local function IsWIMFocusActive()
        local wim = _G.WIM
        local focus = wim and wim.EditBoxInFocus
        if not focus then
            return false
        end

        local isShown = focus.IsShown and focus:IsShown()
        local isVisible = focus.IsVisible and focus:IsVisible()
        local hasFocus = focus.HasFocus and focus:HasFocus()

        return (isShown == true) or (isVisible == true) or (hasFocus == true)
    end

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

            -- If WIM currently owns the chat focus for whisper handling,
            -- let Blizzard/WIM keep control and do not show Yapper's overlay.
            local ct = blizzEditBox and blizzEditBox.GetAttribute
                and blizzEditBox:GetAttribute("chatType")
            local isWhisper = (ct == "BN_WHISPER" or ct == "WHISPER")
            local wimActive = IsWIMFocusActive()

            -- Temporary diagnostics for takeover conflicts.
            if wimActive and YapperTable.Utils and YapperTable.Utils.DebugPrint then
                YapperTable.Utils:DebugPrint("WIM gate: suppress overlay (chatType=" .. tostring(ct) .. ")")
            end

            -- chatType may still be unset in some open paths; if WIM has focus,
            -- prefer suppressing to avoid fighting over whisper edit ownership.
            if wimActive and (isWhisper or ct == nil or ct == "") then
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
end

-- ---------------------------------------------------------------------------
-- Main entry point (called by EditBox)
-- ---------------------------------------------------------------------------

--- Process a message from the user.
function Chat:OnSend(text, chatType, language, target)
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

    if YapperTable.Router then
        YapperTable.Router:Send(msg, chatType, language, target)
    else
        C_ChatInfo.SendChatMessage(msg, chatType, language, target)
    end
end
