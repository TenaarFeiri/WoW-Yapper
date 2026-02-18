--[[
        Message send routing.

        Resolves which WoW API to use for a given (chatType, target) pair:
            1. C_ChatInfo.SendChatMessage  — SAY, EMOTE, YELL, PARTY, WHISPER, etc.
            2. BNSendWhisper               — Battle.net whispers.
            3. C_Club.SendMessage          — Communities / Guild / Officer chat.

        When LibGopher is present (via GopherBridge), all sends are delegated
        to Gopher's hooked globals so its queue, throttler, and event system
        remain active for addons like CrossRP.
]]

local YapperName, YapperTable = ...

local Router = {}
YapperTable.Router = Router

-- Raw Blizzard send functions (set during Init).
Router.SendChatMessage = nil
Router.BNSendWhisper   = nil
Router.ClubSendMessage = nil

-- ---------------------------------------------------------------------------
-- Initialisation
-- ---------------------------------------------------------------------------

function Router:Init()
    -- Try to activate the Gopher bridge first.
    local bridge = YapperTable.GopherBridge
    if bridge then
        bridge:Init()
    end

    -- Cache the current globals.  When GopherBridge is active these are
    -- Gopher's hooked wrappers; when not, they're the raw Blizzard APIs.
    -- Either way Router:Send() usually goes through GopherBridge when
    -- available, but we keep these as a fallback.
    self.SendChatMessage = C_ChatInfo.SendChatMessage
    self.BNSendWhisper   = _G.BNSendWhisper
    self.ClubSendMessage = _G.C_Club and _G.C_Club.SendMessage or nil

    if bridge and bridge:IsActive() then
        YapperTable.Utils:VerbosePrint("Router: sending via GopherBridge.")
    else
        YapperTable.Utils:VerbosePrint("Router: using standard WoW send APIs.")
    end
end

--- Return true if the requested chat target is currently available.
function Router:CanSendTo(chatType, language, target)
    chatType = chatType or "SAY"
    if chatType == "PARTY" or chatType == "PARTY_LEADER" then
        return IsInGroup() and not IsInRaid()
    end
    if chatType == "RAID" or chatType == "RAID_LEADER" or chatType == "RAID_WARNING" then
        return IsInRaid()
    end
    if chatType == "INSTANCE_CHAT" then
        return IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    end
    if chatType == "GUILD" or chatType == "OFFICER" then
        -- Guild membership check.
        return IsInGuild()
    end
    if chatType == "CHANNEL" then
        -- Channel target may be a number or name; attempt basic validation.
        if not target or tostring(target) == "" then return false end
        -- If GetChannelName returns 0 or nil, it's not present.
        if GetChannelName then
            local id = tonumber(target)
            if id then
                local cid = select(1, GetChannelName(id))
                return cid and cid ~= 0
            end
        end
        return true
    end
    return true
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
function Router:NeedsHardwareEvent(chatType)
    if chatType == "SAY" or chatType == "YELL" then
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

--- Send a single message.  Prefers GopherBridge when active; otherwise
--- routes directly to the appropriate Blizzard API.
function Router:Send(msg, chatType, language, target)
    if not msg or msg == "" then return false end
    chatType = chatType or "SAY"
    -- Don't attempt sends to unavailable channels (prevents Blizzard spam).
    if not self:CanSendTo(chatType, language, target) then
        if YapperTable and YapperTable.Utils and YapperTable.Utils.Print then
            local friendly = "Not in required group/channel for chat type: " .. tostring(chatType)
            YapperTable.Utils:Print("warn", friendly)
        end
        return false
    end

    -- ── GopherBridge path ────────────────────────────────────────────
    local bridge = YapperTable.GopherBridge
    if bridge and bridge:IsActive() then
        return bridge:Send(msg, chatType, language, target)
    end

    -- ── Direct path (no Gopher) ──────────────────────────────────────

    -- Battle.net whisper
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

    -- Community channel (CHANNEL that's actually a club)
    if chatType == "CHANNEL" then
        local isClub, clubId, streamId = self:DetectCommunityChannel(target)
        if isClub and clubId and streamId then
            if self.ClubSendMessage then
                self.ClubSendMessage(clubId, streamId, msg)
                return true
            end
            return false
        end
    end

    -- Explicit CLUB type
    if chatType == "CLUB" then
        local clubId   = language
        local streamId = target
        if self.ClubSendMessage and clubId and streamId then
            self.ClubSendMessage(tonumber(clubId), tonumber(streamId), msg)
            return true
        end
        return false
    end

    -- Standard SendChatMessage for everything else
    if self.SendChatMessage then
        self.SendChatMessage(msg, chatType, language, target)
        return true
    end

    return false
end
