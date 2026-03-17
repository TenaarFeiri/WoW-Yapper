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

local _, YapperTable = ...

local Router = {}
YapperTable.Router = Router

-- Raw Blizzard send functions (set during Init).
Router.SendChatMessage = nil
Router.BNSendWhisper   = nil
Router.ClubSendMessage = nil

local function NormalizeBnetTarget(value)
    if not value then return nil end
    local text = tostring(value)
    text = text:match("^%s*(.-)%s*$")
    if text == "" then return nil end
    return text
end

local function MatchesBnetNeedle(needle, accountName, battleTag, toonName, characterName)
    if not needle then return false end
    local lowerNeedle = string.lower(needle)
    local function eq(value)
        return value and string.lower(value) == lowerNeedle
    end

    if eq(accountName) or eq(battleTag) or eq(toonName) or eq(characterName) then
        return true
    end

    if battleTag then
        local base = battleTag:match("^([^#]+)")
        if base and string.lower(base) == lowerNeedle then
            return true
        end
    end

    return false
end

function Router:ResolveBnetTarget(target)
    local needle = NormalizeBnetTarget(target)
    if not needle then return nil, nil end

    if C_BattleNet and C_BattleNet.GetFriendAccountInfo and BNGetNumFriends then
        local count = BNGetNumFriends()
        for i = 1, count do
            local info = C_BattleNet.GetFriendAccountInfo(i)
            if info then
                local accountName = info.accountName
                local battleTag = info.battleTag
                local bnetAccountID = info.bnetAccountID
                local characterName = info.gameAccountInfo and info.gameAccountInfo.characterName
                if MatchesBnetNeedle(needle, accountName, battleTag, nil, characterName) then
                    return nil, bnetAccountID
                end
            end
        end
    end

    if BNGetNumFriends and BNGetFriendInfo then
        local count = BNGetNumFriends()
        for i = 1, count do
            local presenceID, accountName, battleTag, _, toonName, _, _, _, _, _, _, _, _, bnetAccountID = BNGetFriendInfo(i)
            if presenceID then
                if MatchesBnetNeedle(needle, accountName, battleTag, toonName, nil) then
                    return presenceID, bnetAccountID
                end
            end
        end
    end

    return nil, nil
end

function Router:ResolveBnetDisplay(target)
    local needle = NormalizeBnetTarget(target)
    if not needle then return nil end

    local function pickName(accountName, battleTag, characterName, toonName)
        local base = battleTag and battleTag:match("^([^#]+)")
        return base or accountName or characterName or toonName
    end

    local numeric = tonumber(needle)
    if numeric and C_BattleNet and C_BattleNet.GetFriendAccountInfo and BNGetNumFriends then
        local count = BNGetNumFriends()
        for i = 1, count do
            local info = C_BattleNet.GetFriendAccountInfo(i)
            if info and info.bnetAccountID == numeric then
                local characterName = info.gameAccountInfo and info.gameAccountInfo.characterName
                return pickName(info.accountName, info.battleTag, characterName, nil)
            end
        end
    end

    if BNGetNumFriends and BNGetFriendInfo then
        local count = BNGetNumFriends()
        for i = 1, count do
            local presenceID, accountName, battleTag, _, toonName, _, _, _, _, _, _, _, _, bnetAccountID = BNGetFriendInfo(i)
            if numeric then
                if presenceID == numeric or bnetAccountID == numeric then
                    return pickName(accountName, battleTag, nil, toonName)
                end
            else
                if MatchesBnetNeedle(needle, accountName, battleTag, toonName, nil) then
                    return pickName(accountName, battleTag, nil, toonName)
                end
            end
        end
    end

    if not numeric and C_BattleNet and C_BattleNet.GetFriendAccountInfo and BNGetNumFriends then
        local count = BNGetNumFriends()
        for i = 1, count do
            local info = C_BattleNet.GetFriendAccountInfo(i)
            if info then
                local characterName = info.gameAccountInfo and info.gameAccountInfo.characterName
                if MatchesBnetNeedle(needle, info.accountName, info.battleTag, nil, characterName) then
                    return pickName(info.accountName, info.battleTag, characterName, nil)
                end
            end
        end
    end

    return nil
end

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
-- Send
-- ---------------------------------------------------------------------------

--- Send a single message.  Prefers GopherBridge when active; otherwise
--- routes directly to the appropriate Blizzard API.
function Router:Send(msg, chatType, language, target)
    if not msg or msg == "" then return false end
    chatType = chatType or "SAY"

    -- ── GopherBridge path ────────────────────────────────────────────
    local bridge = YapperTable.GopherBridge
    if bridge and bridge:IsActive() then
        return bridge:Send(msg, chatType, language, target)
    end

    -- ── Direct path (no Gopher) ──────────────────────────────────────

    -- Battle.net whisper
    if chatType == "BN_WHISPER" or chatType == "BNET" then
        local presenceID = tonumber(target)
        local bnetAccountID = nil
        if not presenceID then
            presenceID, bnetAccountID = self:ResolveBnetTarget(target)
        end
        if C_BattleNet and C_BattleNet.SendWhisper and bnetAccountID then
            C_BattleNet.SendWhisper(bnetAccountID, msg)
            return true
        end
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
