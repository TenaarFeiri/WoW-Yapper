--[[
    Queue.lua
    Three-mode delivery queue.

    BATCH   (SAY, YELL, CHANNEL) — need a hardware event per batch.
    CONFIRM (EMOTE) — auto-chains via CHAT_MSG_EMOTE confirmations.
    BURST   (PARTY, RAID, GUILD, etc.) — fire-and-forget with tiny delays.
]]

local YapperName, YapperTable = ...

local Queue = {}
YapperTable.Queue = Queue

local MODE_BATCH   = "BATCH"
local MODE_CONFIRM = "CONFIRM"
local MODE_BURST   = "BURST"

-- Which mode each chat type uses (default = BURST).
local SEND_MODES = {
    SAY     = MODE_BATCH,
    YELL    = MODE_BATCH,
    CHANNEL = MODE_BATCH,
    EMOTE   = MODE_CONFIRM,
}

-- Confirmation events (BATCH + CONFIRM only).
local CONFIRM_EVENTS = {
    SAY     = "CHAT_MSG_SAY",
    YELL    = "CHAT_MSG_YELL",
    EMOTE   = "CHAT_MSG_EMOTE",
    -- CHANNEL: no reliable echo; we use the stall timer instead.
}

local BURST_DELAY = 0.05

-- State.
Queue.Entries       = {}
Queue.Active        = false
Queue.Sent          = 0
Queue.Total         = 0
Queue.ChatType      = nil
Queue.PlayerGUID    = nil

Queue.Mode          = nil

Queue.BatchPending  = {}
Queue.BatchSize     = 3

Queue.Current       = nil

Queue.BurstTimer    = nil

Queue.NeedsContinue = false
Queue.StallTimer    = nil
Queue.StallTimeout  = 1.5

Queue._lastEscTime  = 0
local DOUBLE_ESC_WINDOW = 0.4

Queue.ContinueFrame = nil

-- ===========================================================================
-- Init / Reset
-- ===========================================================================

function Queue:Init()
    local cfg = YapperTable.Config and YapperTable.Config.Chat or {}
    self.BatchSize    = cfg.BATCH_SIZE    or 3
    self.StallTimeout = cfg.STALL_TIMEOUT or 1.5
    self.PlayerGUID   = UnitGUID("player")

    for chatType, event in pairs(CONFIRM_EVENTS) do
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
    self.Active        = false
    self.Sent          = 0
    self.Total         = 0
    self.ChatType      = nil
    self.Mode          = nil
    self.BatchPending  = {}
    self.Current       = nil
    self.NeedsContinue = false
    self._lastEscTime  = 0
    self:CancelBurstTimer()
    self:CancelStallTimer()
    self:HideContinuePrompt()
    self:DisableEscapeCancel()
end

-- ===========================================================================
-- Mode detection
-- ===========================================================================

function Queue:GetMode(chatType)
    return SEND_MODES[chatType] or MODE_BURST
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

--- Start sending.  BATCH mode must be called from a hardware event.
function Queue:Flush()
    if #self.Entries == 0 then return end
    if self.Active then return end

    self.Active   = true
    self.Sent     = 0
    self.Total    = #self.Entries
    self.ChatType = self.Entries[1].type
    self.Mode     = self:GetMode(self.ChatType)

    self:EnableEscapeCancel()

    if self.Mode == MODE_BATCH then
        self:BatchSend()
    elseif self.Mode == MODE_CONFIRM then
        self:ConfirmSend()
    else
        self:BurstSend()
    end
end

-- ===========================================================================
-- BATCH mode (SAY, YELL, CHANNEL)
-- ===========================================================================

--- Fire up to BatchSize chunks synchronously (must be in hardware-event context).
function Queue:BatchSend()
    local count = math.min(self.BatchSize, #self.Entries)
    self.BatchPending = {}

    for i = 1, count do
        local entry = table.remove(self.Entries, 1)
        self.BatchPending[#self.BatchPending + 1] = entry
        self.Sent = self.Sent + 1
        self:RawSend(entry)
    end

    -- CHANNEL has no confirmation event; treat as delivered after a delay.
    if not CONFIRM_EVENTS[self.ChatType] then
        C_Timer.After(self.StallTimeout, function()
            if self.Active and self.Mode == MODE_BATCH
               and #self.BatchPending > 0 then
                -- Assume they went through.
                self.BatchPending = {}
                if #self.Entries > 0 then
                    self:ShowContinuePrompt()
                else
                    self:Complete()
                end
            end
        end)
    else
        self:ResetStallTimer()
    end
end

--- Called when a BATCH confirmation arrives.
function Queue:OnBatchConfirm()
    if #self.BatchPending == 0 then return end

    -- Confirmations arrive in the order we sent them.
    table.remove(self.BatchPending, 1)

    if #self.BatchPending > 0 then
        self:ResetStallTimer()
        return
    end

    -- Entire batch confirmed.
    self:CancelStallTimer()
    self:HideContinuePrompt()

    if #self.Entries == 0 then
        self:Complete()
    else
        -- More chunks remain — need another hardware event.
        self:ShowContinuePrompt()
    end
end

--- Batch confirmation stalled — return unconfirmed chunks to the front.
function Queue:OnBatchStall()
    for i = #self.BatchPending, 1, -1 do
        table.insert(self.Entries, 1, self.BatchPending[i])
        self.Sent = self.Sent - 1
    end
    self.BatchPending = {}

    self:ShowContinuePrompt()
end

function Queue:OnBatchResume()
    self:HideContinuePrompt()
    self:BatchSend()
end

-- ===========================================================================
-- CONFIRM mode (EMOTE)
-- ===========================================================================

function Queue:ConfirmSend()
    if #self.Entries == 0 then
        self:Complete()
        return
    end

    local entry = table.remove(self.Entries, 1)
    self.Current = entry
    self.Sent    = self.Sent + 1
    self:RawSend(entry)
    self:ResetStallTimer()
end

function Queue:OnConfirmConfirm()
    self.Current = nil
    self:CancelStallTimer()
    self:HideContinuePrompt()

    -- Auto-chain next chunk (EMOTE doesn't need hardware events).
    self:ConfirmSend()
end

--- Emote confirmation stalled (throttled).
function Queue:OnConfirmStall()
    self:ShowContinuePrompt()
end

function Queue:OnConfirmResume()
    self:HideContinuePrompt()

    if self.Current then
        -- Re-send the stalled chunk.
        self:RawSend(self.Current)
        self:ResetStallTimer()
    else
        self:ConfirmSend()
    end
end

-- ===========================================================================
-- BURST mode — PARTY, RAID, GUILD, OFFICER, INSTANCE_CHAT, etc.
-- ===========================================================================

--- Fire all remaining chunks with tiny inter-chunk delays.
--- No confirmation, no stall detection.
function Queue:BurstSend()
    if #self.Entries == 0 then
        self:Complete()
        return
    end

    local entry = table.remove(self.Entries, 1)
    self.Sent = self.Sent + 1
    self:RawSend(entry)

    if #self.Entries > 0 then
        self.BurstTimer = C_Timer.NewTimer(BURST_DELAY, function()
            self.BurstTimer = nil
            self:BurstSend()
        end)
    else
        self:Complete()
    end
end

function Queue:CancelBurstTimer()
    if self.BurstTimer then
        self.BurstTimer:Cancel()
        self.BurstTimer = nil
    end
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
        -- Treat a declined/failed send as a stall depending on mode to avoid
        -- tight retry loops that trigger Blizzard "not in party" messages.
        if self.Mode == MODE_BATCH then
            self:OnBatchStall()
        elseif self.Mode == MODE_CONFIRM then
            self:OnConfirmStall()
        else
            -- For BURST, stop the burst and finish to avoid spamming.
            self:CancelBurstTimer()
            self:Complete()
        end
    end
end

function Queue:Complete()
    self:Reset()
end

-- ===========================================================================
-- Confirmation event handler
-- ===========================================================================

function Queue:OnChatEvent(event, ...)
    if not self.Active then return end

    -- arg12 = sender GUID.
    local guid = select(12, ...)
    if guid ~= self.PlayerGUID then return end

    -- ── BATCH mode ───────────────────────────────────────────────────
    if self.Mode == MODE_BATCH then
        if #self.BatchPending == 0 then return end
        local expected = CONFIRM_EVENTS[self.BatchPending[1].type]
        if event ~= expected then return end
        self:OnBatchConfirm()
        return
    end

    -- ── CONFIRM mode ─────────────────────────────────────────────────
    if self.Mode == MODE_CONFIRM then
        if not self.Current then return end
        local expected = CONFIRM_EVENTS[self.Current.type]
        if event ~= expected then return end
        self:OnConfirmConfirm()
        return
    end

    -- BURST mode ignores chat events.
end

-- ===========================================================================
-- Hardware event capture (OpenChat hook)
-- ===========================================================================

--- Captures Enter / chat key when waiting for a continue.
function Queue:OnOpenChat(...)
    if not self.NeedsContinue then return end
    self.NeedsContinue = false

    if self.Mode == MODE_BATCH then
        self:OnBatchResume()
    elseif self.Mode == MODE_CONFIRM then
        self:OnConfirmResume()
    end
end

--- Returns true if the queue is consuming input (suppresses overlay).
function Queue:TryContinue()
    if self.NeedsContinue then
        return true
    end
    return false
end

-- ===========================================================================
-- Stall timer
-- ===========================================================================

function Queue:ResetStallTimer()
    self:CancelStallTimer()
    if not self.Active then return end

    self.StallTimer = C_Timer.NewTimer(self.StallTimeout, function()
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
    if not self.Active then return end

    if self.Mode == MODE_BATCH then
        self:OnBatchStall()
    elseif self.Mode == MODE_CONFIRM then
        self:OnConfirmStall()
    end
end

-- ===========================================================================
-- Continue prompt UI
-- ===========================================================================

function Queue:CreateContinueFrame()
    if self.ContinueFrame then return end

    local f = CreateFrame("Frame", "YapperContinueFrame", UIParent,
                          "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetSize(380, 36)
    f:Hide()

    -- Position above the chat edit box.
    f:SetScript("OnShow", function(self)
        self:ClearAllPoints()
        local chatFrame = ChatFrame1
        if chatFrame then
            self:SetPoint("BOTTOMLEFT",  chatFrame, "BOTTOMLEFT",  0, -5)
            self:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", 0, -5)
        else
            self:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 55)
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
end

function Queue:ShowContinuePrompt()
    self:CreateContinueFrame()

    -- Total remaining = queued + in-flight (batch pending or current).
    local remaining = #self.Entries + #self.BatchPending
                      + (self.Current and 1 or 0)

    self.ContinueFrame.text:SetText(
        ("Press [Enter] to continue (%d remaining) / double [Esc] to cancel")
            :format(remaining))
    self.ContinueFrame:Show()
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
                -- Double-tap: cancel.
                frame:SetPropagateKeyboardInput(false)
                self:Cancel()
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
    local discarded = #self.Entries + #self.BatchPending
                      + (self.Current and 1 or 0)
    self:Reset()

    if discarded > 0 then
        YapperTable.Utils:Print(
            ("Posting cancelled. %d chunk(s) discarded."):format(discarded))
    end
end

-- ===========================================================================
-- Status
-- ===========================================================================

--- Current queue state snapshot.
function Queue:GetStatus()
    return {
        active    = self.Active,
        mode      = self.Mode,
        sent      = self.Sent,
        total     = self.Total,
        queued    = #self.Entries,
        pending   = #self.BatchPending,
        waiting   = self.NeedsContinue,
        chatType  = self.ChatType,
    }
end
