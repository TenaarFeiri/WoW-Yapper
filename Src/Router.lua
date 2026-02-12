--[[
        Message send routing.

        Resolves which WoW API to use for a given (chatType, target) pair:
            1. C_ChatInfo.SendChatMessage  — SAY, EMOTE, YELL, PARTY, WHISPER, etc.
            2. BNSendWhisper               — Battle.net whispers.
            3. C_Club.SendMessage          — Communities / Guild / Officer chat.

        If Gopher (LibGopher) is present, we bypass its hooks by calling the
        original functions it saved internally, so Yapper controls its own split.
]]

local YapperName, YapperTable = ...

local Router = {}
YapperTable.Router = Router

-- Real send functions (Gopher originals if present, else WoW APIs).
Router.SendChatMessage = nil
Router.BNSendWhisper   = nil
Router.ClubSendMessage = nil

-- ---------------------------------------------------------------------------
-- Initialisation
-- ---------------------------------------------------------------------------

--- Probe for LibGopher and attach bypass hooks if available.
-- Exposed so other addons can override or call it before `Init()`.
-- Returns true if LibGopher hooks were applied.
function Router:DetectGopher()
    local gopherBypass = false
    local ok, gopher = pcall(function()
        if _G.LibStub then
            return _G.LibStub("Gopher", true)
        end
    end)

    if ok and gopher and gopher.hooks then
        if gopher.hooks.SendChatMessage then
            self.SendChatMessage = gopher.hooks.SendChatMessage
            gopherBypass = true
        end
        if gopher.hooks.BNSendWhisper then
            self.BNSendWhisper = gopher.hooks.BNSendWhisper
            gopherBypass = true
        end
        if gopher.hooks.ClubSendMessage then
            self.ClubSendMessage = gopher.hooks.ClubSendMessage
            gopherBypass = true
        end
    end

    return gopherBypass
end

--- Initialise Router. Calls `DetectGopher()` and then falls back to WoW APIs.
function Router:Init()
    local gopherBypass = self:DetectGopher()

    -- Fall back to standard APIs for anything not bypassed.
    self.SendChatMessage = self.SendChatMessage or C_ChatInfo.SendChatMessage
    self.BNSendWhisper   = self.BNSendWhisper   or BNSendWhisper
    self.ClubSendMessage = self.ClubSendMessage or (C_Club and C_Club.SendMessage)

    if gopherBypass then
        YapperTable.Utils:VerbosePrint("Router: Gopher detected — using bypass hooks.")
    else
        YapperTable.Utils:VerbosePrint("Router: using standard WoW send APIs.")
    end
end

-- ---------------------------------------------------------------------------
-- Community channel detection
-- ---------------------------------------------------------------------------

--- Check if a channel is actually a community (Community:<clubId>:<streamId>).
function Router:DetectCommunityChannel(channelTarget)
    if not channelTarget or not GetChannelName then return false end

    local _, name = GetChannelName(channelTarget)
    if not name or type(name) ~= "string" then return false end

    local clubId, streamId = name:match("^Community:(%d+):(%d+)$")
    if clubId and streamId then
        return true, tonumber(clubId), tonumber(streamId)
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Hardware-event awareness
-- ---------------------------------------------------------------------------

--- True if this chat type needs a hardware event (keypress/click) to send.
-- SAY, YELL, CHANNEL, CLUB need one; EMOTE, PARTY, RAID, BNet don't.
function Router:NeedsHardwareEvent(chatType)
    if chatType == "SAY" or chatType == "YELL" then
        -- Play it safe — always assume these need one.
        return true
    end
    if chatType == "CHANNEL" or chatType == "CLUB" then
        return true
    end
    return false
end

--- True if the chat system is in lockdown (encounter-related taint block).
function Router:IsInLockdown()
    if C_ChatInfo.InChatMessagingLockdown then
        return C_ChatInfo.InChatMessagingLockdown()
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Send
-- ---------------------------------------------------------------------------

--- Send a single message through the appropriate API. No splitting or queuing.
function Router:Send(msg, chatType, language, target)
    if not msg or msg == "" then return false end
    chatType = chatType or "SAY"

    -- ── Battle.net whisper ───────────────────────────────────────────
    if chatType == "BN_WHISPER" or chatType == "BNET" then
        local presenceID = tonumber(target)
        if not presenceID then
            YapperTable.Utils:DebugPrint("Router: BNet whisper with no valid presenceID.")
            return false
        end
        if self.BNSendWhisper then
            self.BNSendWhisper(presenceID, msg)
            return true
        end
        return false
    end

    -- ── Community channel (CHANNEL that's actually a club) ───────────
    if chatType == "CHANNEL" then
        local isClub, clubId, streamId = self:DetectCommunityChannel(target)
        if isClub and clubId and streamId then
            if self.ClubSendMessage then
                self.ClubSendMessage(clubId, streamId, msg)
                return true
            end
            return false
        end
        -- Not a community — fall through to SendChatMessage.
    end

    -- ── Explicit CLUB type (clubId / streamId already resolved) ───────
    if chatType == "CLUB" then
        local clubId   = language  -- overloaded: arg3 = clubId
        local streamId = target    -- overloaded: arg4 = streamId
        if self.ClubSendMessage and clubId and streamId then
            self.ClubSendMessage(tonumber(clubId), tonumber(streamId), msg)
            return true
        end
        return false
    end

    -- ── Standard SendChatMessage for everything else ─────────────────
    if self.SendChatMessage then
        self.SendChatMessage(msg, chatType, language, target)
        return true
    end

    return false
end
