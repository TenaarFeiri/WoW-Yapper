--[[
    Queue.lua
    Event-ack delivery queue.

    All sends advance only after an expected chat event (or a policy-driven
    timeout when no reliable event exists). Policies decide when to prompt
    for hardware input and when to auto-continue until throttled.
]]

local _, YapperTable = ...

local Queue = {}
YapperTable.Queue = Queue

-- Re-localise state machine for internal guards
local State = YapperTable.State

-- Localise Lua globals for performance
local table_insert = table.insert
local table_remove = table.remove
local math_max     = math.max
local math_min     = math.min
local type     = type
local pairs    = pairs
local ipairs   = ipairs
local tostring = tostring
local select   = select
local GetTime  = GetTime

local POLICY_CLASS = {
    OPEN_WORLD_LOCAL = "OPEN_WORLD_LOCAL",
    INSTANCE_LOCAL   = "INSTANCE_LOCAL",
    EMOTE            = "EMOTE",
    WHISPER          = "WHISPER",
    BN_WHISPER       = "BN_WHISPER",
    GLOBAL_CHANNEL   = "GLOBAL_CHANNEL",
    COMMUNITY_CLUB   = "COMMUNITY_CLUB",
    GROUP            = "GROUP",
}

local GROUP_CHAT_TYPES = {
    PARTY = true,
    PARTY_LEADER = true,
    RAID = true,
    RAID_LEADER = true,
    RAID_WARNING = true,
    INSTANCE_CHAT = true,
    INSTANCE_CHAT_LEADER = true,
    GUILD = true,
    OFFICER = true,
}

local SEND_POLICIES = {
    [POLICY_CLASS.OPEN_WORLD_LOCAL] = {
        promptEveryChunk = true,
        autoUntilThrottle = false,
        requiresHardwareEvent = true,
        ackEvent = {
            SAY = "CHAT_MSG_SAY",
            YELL = "CHAT_MSG_YELL",
        },
    },
    [POLICY_CLASS.INSTANCE_LOCAL] = {
        promptEveryChunk = false,
        autoUntilThrottle = true,
        requiresHardwareEvent = false,
        ackEvent = {
            SAY = "CHAT_MSG_SAY",
            YELL = "CHAT_MSG_YELL",
        },
    },
    [POLICY_CLASS.EMOTE] = {
        promptEveryChunk = false,
        autoUntilThrottle = true,
        requiresHardwareEvent = false,
        ackEvent = "CHAT_MSG_EMOTE",
    },
    [POLICY_CLASS.WHISPER] = {
        promptEveryChunk = false,
        autoUntilThrottle = true,
        requiresHardwareEvent = false,
        ackEvent = "CHAT_MSG_WHISPER_INFORM",
    },
    [POLICY_CLASS.BN_WHISPER] = {
        promptEveryChunk = false,
        autoUntilThrottle = true,
        requiresHardwareEvent = false,
        ackEvent = "CHAT_MSG_BN_WHISPER_INFORM",
    },
    [POLICY_CLASS.GLOBAL_CHANNEL] = {
        promptEveryChunk = true,
        autoUntilThrottle = false,
        requiresHardwareEvent = false,
        ackEvent = "CHAT_MSG_CHANNEL",
    },
    [POLICY_CLASS.COMMUNITY_CLUB] = {
        promptEveryChunk = true,
        autoUntilThrottle = false,
        requiresHardwareEvent = false,
        ackEvent = "CHAT_MSG_COMMUNITIES_CHANNEL",
        stallMultiplier = 3,   -- community servers are slow
    },
    [POLICY_CLASS.GROUP] = {
        promptEveryChunk = false,
        autoUntilThrottle = true,
        requiresHardwareEvent = false,
        ackEvent = {
            PARTY = "CHAT_MSG_PARTY",
            PARTY_LEADER = "CHAT_MSG_PARTY_LEADER",
            RAID = "CHAT_MSG_RAID",
            RAID_LEADER = "CHAT_MSG_RAID_LEADER",
            RAID_WARNING = "CHAT_MSG_RAID_WARNING",
            INSTANCE_CHAT = "CHAT_MSG_INSTANCE_CHAT",
            INSTANCE_CHAT_LEADER = "CHAT_MSG_INSTANCE_CHAT_LEADER",
            GUILD = "CHAT_MSG_GUILD",
            OFFICER = "CHAT_MSG_OFFICER",
        },
    },
}

-- When a player is the group leader their sent messages echo with the
-- "_LEADER" event variant (e.g. CHAT_MSG_PARTY_LEADER instead of
-- CHAT_MSG_PARTY).  Accept either direction so the queue does not stall.
local ACK_SIBLING = {
    CHAT_MSG_PARTY                = "CHAT_MSG_PARTY_LEADER",
    CHAT_MSG_PARTY_LEADER         = "CHAT_MSG_PARTY",
    CHAT_MSG_RAID                 = "CHAT_MSG_RAID_LEADER",
    CHAT_MSG_RAID_LEADER          = "CHAT_MSG_RAID",
    CHAT_MSG_INSTANCE_CHAT        = "CHAT_MSG_INSTANCE_CHAT_LEADER",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "CHAT_MSG_INSTANCE_CHAT",
}

local ALL_CONFIRM_EVENTS = {
    -- Local chat echoes
    CHAT_MSG_SAY = true,
    CHAT_MSG_YELL = true,
    CHAT_MSG_EMOTE = true,

    -- Outgoing whispers
    CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_BN_WHISPER_INFORM = true,

    -- Public channels (numbered) and community/club
    CHAT_MSG_CHANNEL = true,
    CHAT_MSG_COMMUNITIES_CHANNEL = true,

    -- Group and instance chat
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_INSTANCE_CHAT = true,
    CHAT_MSG_INSTANCE_CHAT_LEADER = true,

    -- Guild chat
    CHAT_MSG_GUILD = true,
    CHAT_MSG_OFFICER = true,
}

-- State.
Queue.Entries       = {}
Queue.PlayerGUID    = nil



Queue.NeedsContinue = false
Queue.StallTimer    = nil
Queue.StallTimeout  = 1.5

Queue.PendingEntry          = nil
Queue.PendingAckEntry       = nil
Queue.PendingAckText        = nil
Queue.PendingAckEvent       = nil
Queue.PendingAckPolicyClass = nil
Queue.StrictAckMatching     = false

Queue._lastEscTime  = 0
local DOUBLE_ESC_WINDOW = 0.4

Queue.ContinueFrame = nil

-- ===========================================================================
-- Init / Reset
-- ===========================================================================

function Queue:Init()
    local cfg = YapperTable.Config and YapperTable.Config.Chat or {}
    self.StallTimeout = cfg.STALL_TIMEOUT or 1.5
    self.PlayerGUID   = UnitGUID("player")

    for event in pairs(ALL_CONFIRM_EVENTS) do
        YapperTable.Events:Register("PARENT_FRAME", event, function(...)
            self:OnChatEvent(event, ...)
        end, "Queue_" .. event)
    end

    if ChatFrameUtil and ChatFrameUtil.OpenChat and not self._openChatHooked then
        hooksecurefunc(ChatFrameUtil, "OpenChat", function(...)
            self:OnOpenChat(...)
        end)
        self._openChatHooked = true
    end
end

function Queue:Reset()
    self.Entries       = {}
    self.PendingEntry  = nil
    self:ClearPendingAck()
    self.NeedsContinue = false
    self._lastEscTime  = 0
    self:CancelStallTimer()
    self:HideContinuePrompt()
    self:DisableEscapeCancel()

    if State then
        State:ToIdle()
    end
end

-- ===========================================================================
-- Mode detection
-- ===========================================================================

function Queue:IsOpenWorld()
    if not IsInInstance then
        return true
    end
    local inInstance = IsInInstance()
    return not inInstance
end

function Queue:IsCommunityChannelEntry(entry)
    if not entry or entry.type ~= "CHANNEL" then
        return false
    end

    local Router = YapperTable.Router
    if not Router or not Router.DetectCommunityChannel then
        return false
    end

    local isClub = Router:DetectCommunityChannel(entry.target)
    return isClub == true
end

function Queue:ClassifyEntry(entry)
    local chatType = entry and entry.type or "SAY"

    if chatType == "EMOTE" then
        return POLICY_CLASS.EMOTE
    end

    if chatType == "SAY" or chatType == "YELL" then
        if self:IsOpenWorld() then
            return POLICY_CLASS.OPEN_WORLD_LOCAL
        end
        return POLICY_CLASS.INSTANCE_LOCAL
    end

    if chatType == "WHISPER" then
        return POLICY_CLASS.WHISPER
    end

    if chatType == "BN_WHISPER" or chatType == "BNET" then
        return POLICY_CLASS.BN_WHISPER
    end

    if chatType == "CHANNEL" then
        if self:IsCommunityChannelEntry(entry) then
            return POLICY_CLASS.COMMUNITY_CLUB
        end
        return POLICY_CLASS.GLOBAL_CHANNEL
    end

    if chatType == "CLUB" then
        return POLICY_CLASS.COMMUNITY_CLUB
    end

    if GROUP_CHAT_TYPES[chatType] then
        return POLICY_CLASS.GROUP
    end

    if YapperTable.Error and YapperTable.Error.PrintError then
        YapperTable.Error:PrintError("BAD_CHAT_TYPE", tostring(chatType))
    end
    return nil
end

function Queue:GetPolicy(entry)
    local policyClass = self:ClassifyEntry(entry)
    if not policyClass then
        return nil, nil
    end
    local policy = SEND_POLICIES[policyClass]
    if not policy then
        if YapperTable.Error and YapperTable.Error.PrintError then
            YapperTable.Error:PrintError("UNKNOWN", "Queue: missing policy for class", tostring(policyClass))
        end
        return nil, nil
    end
    return policy, policyClass
end

function Queue:GetConfirmEventForEntry(entry)
    local policy = self:GetPolicy(entry)
    local ack = policy and policy.ackEvent or nil
    if type(ack) == "function" then
        return ack(entry)
    end
    if type(ack) == "table" then
        return ack[entry and entry.type or nil]
    end
    if type(ack) == "string" then
        return ack
    end
    return nil
end

function Queue:TrackPendingAck(entry)
    local _, policyClass = self:GetPolicy(entry)
    self.PendingAckEntry = entry
    self.PendingAckText = entry and entry.text or nil
    self.PendingAckEvent = self:GetConfirmEventForEntry(entry)
    self.PendingAckPolicyClass = policyClass
end

function Queue:GetActivePolicySnapshot()
    local head = self.PendingEntry or self.Entries[1]
    local policy, policyClass = self:GetPolicy(head)
    return {
        active   = State:IsSending(),
        stalled  = self.NeedsContinue == true,
        chatType = head and head.type or nil,
        policyClass = policyClass,
        expectedAckEvent = policy and policy.ackEvent or nil,
        pending  = #self.Entries,
        inFlight = (self.PendingEntry and 1 or 0),
    }
end

function Queue:ClearPendingAck()
    self.PendingAckEntry = nil
    self.PendingAckText = nil
    self.PendingAckEvent = nil
    self.PendingAckPolicyClass = nil
end

-- ===========================================================================
-- Enqueue / Flush
-- ===========================================================================

function Queue:Enqueue(chunks, chatType, language, target)
    for _, text in ipairs(chunks) do
        self.Entries[#self.Entries + 1] = {
            text   = text,
            type   = chatType,
            lang   = language,
            target = target,
        }
    end
end

--- Start sending.  Requires hardware input only when policy mandates it.
function Queue:Flush(inHardwareEvent)
    if #self.Entries == 0 then return end
    if State:IsSending() then return end
    -- Transition to SENDING state.
    State:ToSending()

    local policy = self:GetPolicy(self.Entries[1])
    if not policy then
        self:Reset()
        return
    end

    self:EnableEscapeCancel()

    if State then
        State:ToSending()
    end

    self:SendNext(inHardwareEvent == true)
end

-- ===========================================================================
-- Per-entry send pipeline (event-ack driven)
-- ===========================================================================

function Queue:RequiresHardwareEvent(entry)
    local policy = self:GetPolicy(entry)
    return policy and policy.requiresHardwareEvent == true
end

function Queue:SendNext(inHardwareEvent)
    if self.PendingEntry then return end
    if #self.Entries == 0 then
        self:Complete()
        return
    end

    local entry = self.Entries[1]
    local policy = self:GetPolicy(entry)
    if not policy then
        self:Reset()
        return
    end

    if policy and policy.promptEveryChunk and not inHardwareEvent then
        self:ShowContinuePrompt()
        return
    end

    if self:RequiresHardwareEvent(entry) and not inHardwareEvent then
        self:ShowContinuePrompt()
        return
    end

    entry = table_remove(self.Entries, 1)
    self:BeginEntry(entry)
end

function Queue:BeginEntry(entry)
    self.PendingEntry = entry
    self:TrackPendingAck(entry)
    self:RawSend(entry)

    local expectedEvent = self.PendingAckEvent
    if expectedEvent then
        self:ResetStallTimer(entry)
    else
        local policy = self:GetPolicy(entry)
        if not policy then
            self:Reset()
            return
        end
        if policy and policy.autoUntilThrottle then
            C_Timer.After(self.StallTimeout, function()
                if State:IsSending() and self.PendingEntry == entry then
                    self:AssumeAck()
                end
            end)
        else
            self:ShowContinuePrompt()
        end
    end
end

function Queue:HandleAck()
    self.PendingEntry = nil
    self:ClearPendingAck()
    self:CancelStallTimer()
    self:HideContinuePrompt()
    self:SendNext(false)
end

function Queue:AssumeAck()
    self.PendingEntry = nil
    self:ClearPendingAck()
    self:SendNext(false)
end

-- ===========================================================================
-- Shared helpers
-- ===========================================================================

function Queue:RawSend(entry)

    local Router = YapperTable.Router
    local ok = true
    if Router then
        ok = Router:Send(entry.text, entry.type, entry.lang, entry.target)
    else
        C_ChatInfo.SendChatMessage(entry.text, entry.type, entry.lang, entry.target)
        ok = true
    end


    if not ok then
        -- Treat a declined/failed send as a stall. Re-queue the entry and
        -- prompt rather than tight-loop retrying.
        if self.PendingEntry then
            table_insert(self.Entries, 1, self.PendingEntry)
            self.PendingEntry = nil
            self:ClearPendingAck()
        end
        self:ShowContinuePrompt()
    end
end

function Queue:Complete()
    self:Reset()
    if State then
        State:ToIdle()
    end
    if YapperTable.API then
        YapperTable.API:Fire("QUEUE_COMPLETE")
    end
end

-- ===========================================================================
-- Confirmation event handler
-- ===========================================================================

function Queue:OnChatEvent(event, ...)
    if not State:IsSending() then return end
    if YapperTable.Utils and YapperTable.Utils.IsChatLockdown
        and YapperTable.Utils:IsChatLockdown() then
        return
    end


    -- First match the echoed text and expected event. Some chat events
    -- (notably whispers) may not provide a sender GUID in the usual arg
    -- position, so treat GUID as optional: only reject if present and
    -- it doesn't match the player GUID.
    local msgText = select(1, ...)
    if self.StrictAckMatching and self.PendingAckText
        and msgText ~= self.PendingAckText then
        if YapperTable.Utils and YapperTable.Utils.DebugPrint then
            YapperTable.Utils:DebugPrint("  REJECTED: StrictAckMatching",
                "#sent=" .. #(self.PendingAckText or ""),
                "#echo=" .. #(msgText or ""))
        end
        return
    end

    if not self.PendingEntry then return end
    if event ~= self.PendingAckEvent
        and ACK_SIBLING[self.PendingAckEvent] ~= event then
        return
    end

    -- arg12 = sender GUID when available.
    local guid = select(12, ...)
    if guid and guid ~= self.PlayerGUID then
        if YapperTable.Utils and YapperTable.Utils.DebugPrint then
            YapperTable.Utils:DebugPrint("  REJECTED: GUID mismatch",
                tostring(guid), "vs", tostring(self.PlayerGUID))
        end
        return
    end

    self:HandleAck()
end

-- ===========================================================================
-- Hardware event capture (OpenChat hook)
-- ===========================================================================

--- Captures Enter / chat key when waiting for a continue.
function Queue:OnOpenChat(...)
    if not self.NeedsContinue then return end
    self.NeedsContinue = false

    if State then
        State:ToSending()
    end

    self:SendNext(true)
end

--- Returns true if the queue is consuming input (suppresses overlay).
function Queue:TryContinue()
    if self.NeedsContinue then
        return true
    end
    -- Also suppress while a chunk is in-flight awaiting ACK.
    -- Without this there's a race window between OnOpenChat dispatching
    -- the next chunk (NeedsContinue=false) and the stall timer firing
    -- 1.5s later, during which the overlay can sneak open.
    if State:IsSending() and self.PendingEntry then
        return true
    end
    return false
end

-- ===========================================================================
-- Stall timer
-- ===========================================================================

function Queue:ResetStallTimer(entry)
    self:CancelStallTimer()
    if not State:IsSending() then return end

    -- Community channels have higher latency; use policy multiplier.
    local timeout = self.StallTimeout
    if entry then
        local policy = self:GetPolicy(entry)
        if policy and policy.stallMultiplier then
            timeout = timeout * policy.stallMultiplier
        end
    end

    self.StallTimer = C_Timer.NewTimer(timeout, function()
        self:OnStallTimeout()
    end)
end

function Queue:CancelStallTimer()
    if self.StallTimer then
        self.StallTimer:Cancel()
        self.StallTimer = nil
    end
end

function Queue:OnStallTimeout()
    if not State:IsSending() then return end

    if not self.PendingEntry then return end
    local entry        = self.PendingEntry
    local policyClass  = self.PendingAckPolicyClass  -- capture before ClearPendingAck
    table_insert(self.Entries, 1, entry)
    self.PendingEntry = nil
    self:ClearPendingAck()
    self:ShowContinuePrompt()

    if State then
        State:ToStalled()
    end

    if YapperTable.API then
        YapperTable.API:Fire("QUEUE_STALL", entry.type, policyClass, #self.Entries)
    end
end

-- ===========================================================================
-- Continue prompt UI
-- ===========================================================================

function Queue:CreateContinueFrame()
    if self.ContinueFrame then return end

    local chatParent = YapperTable.Utils and YapperTable.Utils:GetChatParent() or UIParent
    local f = CreateFrame("Frame", "YapperContinueFrame", chatParent,
                          "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:Hide()

    -- On each Show, anchor to the Yapper overlay (or Blizzard editbox
    -- fallback) so the prompt sits in the input-box slot.
    f:SetScript("OnShow", function(self)
        local parent = YapperTable.Utils and YapperTable.Utils:GetChatParent() or UIParent
        if self:GetParent() ~= parent then
            if FrameUtil and FrameUtil.SetParentMaintainRenderLayering then
                FrameUtil.SetParentMaintainRenderLayering(self, parent)
            else
                self:SetParent(parent)
            end
        end
        self:ClearAllPoints()
        local overlay = YapperTable.EditBox.Overlay
        if overlay and overlay.GetNumPoints and overlay:GetNumPoints() > 0 then
            self:SetPoint("TOPLEFT",     overlay, "TOPLEFT",     0, 0)
            self:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
        elseif ChatFrame1EditBox then
            self:SetPoint("TOPLEFT",     ChatFrame1EditBox, "TOPLEFT",     0, 0)
            self:SetPoint("BOTTOMRIGHT", ChatFrame1EditBox, "BOTTOMRIGHT", 0, 0)
        else
            self:SetPoint("BOTTOM", parent, "BOTTOM", 0, 55)
            self:SetSize(380, 36)
        end
    end)

    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        f:SetBackdropBorderColor(1, 0.8, 0, 1)
    end

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text:SetPoint("LEFT",  f, "LEFT",  12, 0)
    f.text:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.text:SetJustifyH("CENTER")
    f.text:SetTextColor(1, 0.82, 0)
    f.text:SetWordWrap(false)

    self.ContinueFrame = f

    -- follow fullscreen-parent so the prompt isn’t hidden by the housing editor
    if YapperTable.Utils then
        YapperTable.Utils:MakeFullscreenAware(f)
    end
end

function Queue:ShowContinuePrompt()
    self:CreateContinueFrame()

    -- Reparent before Show so the frame is on a visible parent.
    -- When UIParent is hidden (housing editor) OnShow won't fire if the
    -- frame is still parented to UIParent, so we must do this up-front.
    local parent = YapperTable.Utils and YapperTable.Utils:GetChatParent() or UIParent
    local f = self.ContinueFrame
    if f:GetParent() ~= parent then
        if FrameUtil and FrameUtil.SetParentMaintainRenderLayering then
            FrameUtil.SetParentMaintainRenderLayering(f, parent)
        else
            f:SetParent(parent)
        end
    end

    -- Total remaining = queued + in-flight (batch pending or current).
    local remaining = #self.Entries + (self.PendingEntry and 1 or 0)

    -- Apply the user's EditBox font config so the prompt matches the overlay.
    local cfg = YapperTable.Config and YapperTable.Config.EditBox or {}
    if cfg.FontFace or (cfg.FontSize and cfg.FontSize > 0) then
        local baseFace, baseSize, baseFlags = ChatFontNormal:GetFont()
        local face  = cfg.FontFace or baseFace
        local size  = (cfg.FontSize and cfg.FontSize > 0) and cfg.FontSize or baseSize
        local flags = (cfg.FontFlags and cfg.FontFlags ~= "") and cfg.FontFlags or (baseFlags or "")
        size = math_max(10, math_min(size, 24))
        f.text:SetFont(face, size, flags)
    end

    f.text:SetText(
        ("Press [Enter] to continue (%d remaining) / double [Esc] to cancel")
            :format(remaining))
    f:Show()
    self.NeedsContinue = true
end

function Queue:HideContinuePrompt()
    if self.ContinueFrame then
        self.ContinueFrame:Hide()
    end
    self.NeedsContinue = false
end

-- ===========================================================================
-- Escape to cancel
-- ===========================================================================

function Queue:EnableEscapeCancel()
    if self._escapeFrame then
        self._escapeFrame:Show()
        return
    end

    local f = CreateFrame("Frame", "YapperEscapeHandler", UIParent)
    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)

    f:SetScript("OnKeyDown", function(frame, key)
        if key == "ESCAPE" then
            local now = GetTime()
            if (now - self._lastEscTime) <= DOUBLE_ESC_WINDOW then
                -- Double-tap: cancel.  Block propagation first, then cancel
                -- on the next frame so DisableEscapeCancel's re-enable of
                -- propagation doesn't undo our block before this handler
                -- returns (WoW evaluates SetPropagateKeyboardInput on return).
                frame:SetPropagateKeyboardInput(false)
                C_Timer.After(0, function() self:Cancel() end)
            else
                -- First tap: record and consume.
                self._lastEscTime = now
                frame:SetPropagateKeyboardInput(false)
            end
        else
            frame:SetPropagateKeyboardInput(true)
        end
    end)

    self._escapeFrame = f
end

function Queue:DisableEscapeCancel()
    if self._escapeFrame then
        self._escapeFrame:Hide()
        self._escapeFrame:SetPropagateKeyboardInput(true)
    end
end

function Queue:Cancel()
    local discarded = #self.Entries + (self.PendingEntry and 1 or 0)
    self:Reset()

    if State then
        State:ToIdle()
    end

    if discarded > 0 then
        YapperTable.Utils:Print(
            ("Posting cancelled. %d chunk(s) discarded."):format(discarded))
    end

    if YapperTable.API then
        YapperTable.API:Fire("QUEUE_COMPLETE")
    end
end
