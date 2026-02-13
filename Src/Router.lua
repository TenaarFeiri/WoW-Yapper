--[[
        Message send routing.

        Resolves which WoW API to use for a given (chatType, target) pair:
            1. C_ChatInfo.SendChatMessage  — SAY, EMOTE, YELL, PARTY, WHISPER, etc.
            2. BNSendWhisper               — Battle.net whispers.
            3. C_Club.SendMessage          — Communities / Guild / Officer chat.

        If Gopher (LibGopher) is present we destructively unhook it — Yapper
        replaces all of Gopher's functionality.
]]

local YapperName, YapperTable = ...

local Router = {}
YapperTable.Router = Router

-- Live send functions — always point at the real Blizzard APIs.
Router.SendChatMessage = nil
Router.BNSendWhisper   = nil
Router.ClubSendMessage = nil

-- ---------------------------------------------------------------------------
-- Gopher neutralisation
-- ---------------------------------------------------------------------------
-- Gopher hooks three globals at file scope (before PLAYER_LOGIN):
--   C_ChatInfo.SendChatMessage  →  Me.SendChatMessageHook
--   BNSendWhisper               →  Me.BNSendWhisperHook
--   C_Club.SendMessage          →  Me.ClubSendMessageHook
-- It stores the originals in LibGopher.Internal.hooks.*.
-- Strategy: restore globals, gut the internals, make it idempotent.

Router._gopherNeutralized = false

--- Find LibGopher.Internal via every known path. Returns the Internal table
--- or nil.
local function FindGopherInternal()
    -- Path 1: global LibGopher table (most common — Gopher sets _G.LibGopher)
    if _G.LibGopher and type(_G.LibGopher.Internal) == "table" then
        return _G.LibGopher.Internal
    end
    -- Path 2: LibStub (some builds register through it)
    if _G.LibStub then
        local ok, lib = pcall(_G.LibStub, _G.LibStub, "Gopher", true)
        if ok and lib and type(lib.Internal) == "table" then
            return lib.Internal
        end
    end
    return nil
end

--- Destroy Gopher idempotently.
--- Can be called at any point — Init, EditBox:Show, EditBox:Hide, before
--- every send, executes only once.
function Router:NeutralizeGopher()
    if self._gopherNeutralized then return false end

    local me = FindGopherInternal()
    if not me then return false end
    local hooks = me.hooks
    if type(hooks) ~= "table" then return false end

    -- Restore Gopher's saved APIs.
    if hooks.SendChatMessage then
        C_ChatInfo.SendChatMessage = hooks.SendChatMessage
    end
    if hooks.BNSendWhisper then
        _G.BNSendWhisper = hooks.BNSendWhisper
    end
    if hooks.ClubSendMessage and _G.C_Club then
        _G.C_Club.SendMessage = hooks.ClubSendMessage
    end

    -- Replace Gopher's hook functions with thin pass-throughs so any
    -- stale reference that still calls them is passed to Blizz.
    if hooks.SendChatMessage then
        local orig = hooks.SendChatMessage
        me.SendChatMessageHook = function(msg, chatType, lang, channel)
            return orig(msg, chatType, lang, channel)
        end
    end
    if hooks.BNSendWhisper then
        local orig = hooks.BNSendWhisper
        me.BNSendWhisperHook = function(presenceID, text)
            return orig(presenceID, text)
        end
    end
    if hooks.ClubSendMessage then
        local orig = hooks.ClubSendMessage
        me.ClubSendMessageHook = function(clubId, streamId, message)
            return orig(clubId, streamId, message)
        end
    end

    -- Now we kill the event and listener system.
    me.event_hooks = {}
    me.FireEvent   = function() end
    me.FireEventEx = function() end
    me.Listen      = function() return false end
    me.StopListening = function() return false end

    -- Kill AddChat so that Gopher cannot add to its queue.
    me.AddChat     = function() end
    me.QueueChat   = function() end

    -- Don't re-hook.
    me.load = false

    -- If there's any active queue or throttler state, kill that too.
    if type(me.chat_queue) == "table" then
        _G.wipe(me.chat_queue)
    end
    if type(me.out_chat_buffer) == "table" then
        _G.wipe(me.out_chat_buffer)
    end
    me.sending_active    = false
    me.send_queue_started = false

    -- Detach Gopher's event frames.
    if me.frame and me.frame.UnregisterAllEvents then
        me.frame:UnregisterAllEvents()
        me.frame:SetScript("OnEvent", nil)
    end

    self._gopherNeutralized = true -- RIP, you gave me more trouble than I wanted
    return true
end

-- ---------------------------------------------------------------------------
-- Initialisation
-- ---------------------------------------------------------------------------

--- Initialise Router.  Tries to neutralise Gopher, then sets send-function
--- references to the global Blizzard APIs.
function Router:Init()
    local killed = self:NeutralizeGopher()

    -- After neutralisation the globals are the real Blizzard functions.
    self.SendChatMessage = C_ChatInfo.SendChatMessage
    self.BNSendWhisper   = _G.BNSendWhisper
    self.ClubSendMessage = _G.C_Club and _G.C_Club.SendMessage or nil

    if killed then
        YapperTable.Utils:VerbosePrint("Router: Gopher detected and neutralised.")
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

--- Send a single message through the appropriate API.  No splitting or
--- queuing.  Calls NeutralizeGopher() as a safety net before every send.
function Router:Send(msg, chatType, language, target)
    if not msg or msg == "" then return false end
    chatType = chatType or "SAY"

    -- Defensive: ensure Gopher is dead even if it loaded late.
    self:NeutralizeGopher()

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
