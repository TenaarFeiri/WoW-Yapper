--[[
    Chat.lua
    Orchestrator: wires EditBox, Chunking, Queue, and Router together.

    EditBox.OnSend   → Chat:OnSend → Chat:SendPosts
    Multiline:Submit → Chat:SendPosts

    Chat:SendPosts is the single send pipeline:
      history → PRE_SEND → Chunking:Split (fires PRE_CHUNK) → Queue or DirectSend
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
    GUILD_DISCORD        = true,
    CLUB                 = true,
    CHANNEL              = true,
}

-- Split a composition into one post per line, dropping blank lines.
local function SplitPosts(text)
    local posts = {}
    if type(text) ~= "string" or text == "" then return posts end
    for line in string.gmatch(text .. "\n", "(.-)\n") do
        if line:find("%S") then
            posts[#posts + 1] = line
        end
    end
    return posts
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

function Chat:Init()
    if YapperTable.EditBox then
        -- Preserve the veto result for post-send cleanup.
        YapperTable.EditBox:SetOnSend(function(text, chatType, language, target)
            return self:OnSend(text, chatType, language, target)
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

    -- Hard recovery slash commands.
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
-- Send pipeline
-- ---------------------------------------------------------------------------

--- Run the full send pipeline over an ordered list of posts and deliver them
--- as a single queued sequence.
---
--- `Chat:OnSend` and `Multiline:Submit` both use this pipeline. Callers handle
--- their own lockdown recovery; the veto is checked here.
---
--- @param posts    string[]     Ordered posts.  Each may contain "\n", which is
---                              treated as a post boundary.
--- @param chatType string
--- @param language number|nil
--- @param target   string|nil
--- @return boolean success
--- @return string|nil chatType  Resolved routing, post-PRE_SEND.
--- @return number|nil language
--- @return string|nil target
function Chat:SendPosts(posts, chatType, language, target)
    if type(posts) ~= "table" or #posts == 0 then return false end

    if YapperTable.Utils and YapperTable.Utils:IsChatLockdown() then
        return false
    end

    -- Normalize to one post per non-blank line.
    posts = SplitPosts(table.concat(posts, "\n"))
    if #posts == 0 then return false end

    -- Strip display-only escapes (spellcheck recolouring injects colour codes
    -- into the editbox; users may also paste them). Done before anything else
    -- sees the text: history stays clean, PRE_SEND filters match on canonical
    -- text, and chunk byte budgets are not inflated. Hyperlinks are preserved.
    if YapperTable.Utils then
        for i, post in ipairs(posts) do
            posts[i] = YapperTable.Utils:StripDisplayEscapes(post)
        end
    end

    -- Record raw input before filters rewrite it.
    if YapperTable.History then
        for _, post in ipairs(posts) do
            YapperTable.History:AddChatHistory(post, chatType, target)
        end
    end

    -- PRE_SEND can modify or cancel the composed text.
    local API = YapperTable.API
    if API then
        local payload = API:RunFilter("PRE_SEND", {
            text     = table.concat(posts, "\n"),
            chatType = chatType,
            language = language,
            target   = target,
        })
        if payload == false then return false end
        chatType = payload.chatType
        language = payload.language
        target   = payload.target
        posts    = SplitPosts(payload.text)
        if #posts == 0 then return false end
    end

    -- Advance a stalled queue before enqueuing new messages.
    if State and State:IsBusy() then
        local Q = YapperTable.Queue
        if Q and Q.NeedsContinue then
            Q:OnOpenChat()
        end
    end

    local Chunking = YapperTable.Chunking
    if not Chunking then
        YapperTable.Error:PrintError("UNKNOWN", "Chunking module missing")
        return false
    end

    local cfg   = YapperTable.Config and YapperTable.Config.Chat or {}
    local limit = cfg.CHARACTER_LIMIT or 255

    -- Chunk every post into one flat delivery list.  Chunking:Split fires
    -- PRE_CHUNK once per post and is link-aware, so hyperlinks stay atomic.
    local allChunks = {}
    for _, post in ipairs(posts) do
        if #post > limit and not SPLITTABLE[chatType] then
            YapperTable.Error:PrintError("BAD_CHAT_TYPE", tostring(chatType))
            return false
        end

        local chunks = Chunking:Split(post, limit, {
            chatType = chatType,
            language = language,
        })
        if not chunks then return false end   -- a PRE_CHUNK filter cancelled

        for _, chunk in ipairs(chunks) do
            allChunks[#allChunks + 1] = chunk
        end
    end

    if #allChunks == 0 then return false end

    -- Deliver the flat chunk list as a single ordered sequence.
    local ok
    if #allChunks == 1 then
        ok = self:DirectSend(allChunks[1], chatType, language, target)
    else
        local Q = YapperTable.Queue
        if Q then
            Q:Enqueue(allChunks, chatType, language, target)
            Q:Flush(true)
            ok = true
        else
            -- No queue — fire all at once.
            ok = true
            for _, chunk in ipairs(allChunks) do
                if self:DirectSend(chunk, chatType, language, target) == false then
                    ok = false
                    break
                end
            end
        end
    end

    -- Routing is returned so callers can persist the sticky channel using the
    -- values a PRE_SEND filter may have rewritten.
    return ok ~= false, chatType, language, target
end

-- ---------------------------------------------------------------------------
-- Main entry point (called by EditBox)
-- ---------------------------------------------------------------------------

--- Process a message from the single-line overlay.
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

    return self:SendPosts({ text }, chatType, language, target)
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
