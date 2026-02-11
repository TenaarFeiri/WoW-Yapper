--[[
    History.lua — Yapper 1.0.0
    Persistent chat history (survives reloads), crash-safe draft auto-save
    (ring buffer into SavedVariables), and per-session undo/redo.
]]

local YapperName, YapperTable = ...

local History = {}
YapperTable.History = History

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------
local UNDO_HISTORY_SIZE  = 20   -- Max undo snapshots per editbox
local CHAT_HISTORY_SIZE  = 50   -- Max persistent sent messages
local SNAPSHOT_THRESHOLD = 20   -- Min character delta for auto-snapshot
local DRAFT_SLOTS        = 5    -- Ring buffer size for crash-safe drafts

-- Per-editbox undo buffers (keyed by name string).
local UndoBuffers = {}

-- Last known text per editbox (for change detection).
local LastText = {}

-- ---------------------------------------------------------------------------
-- SavedVariable defaults
-- ---------------------------------------------------------------------------
local DB_DEFAULTS = {
    chatHistory = {},  -- Flat array of sent strings, newest last.
    draft = {
        ring     = {},    -- Ring buffer: up to DRAFT_SLOTS text snapshots.
        pos      = 0,     -- Next write index (1-based, wraps).
        chatType = nil,   -- Chat type when draft was taken.
        target   = nil,   -- Whisper target / channel when draft was taken.
        dirty    = false, -- True if editbox was NOT closed via Enter/send.
    },
}

-- ---------------------------------------------------------------------------
-- Init / save
-- ---------------------------------------------------------------------------

--- Set up DB from SavedVariables (call after ADDON_LOADED).
function History:InitDB()
    if not _G.YapperDB then
        _G.YapperDB = {}
    end
    for key, default in pairs(DB_DEFAULTS) do
        if _G.YapperDB[key] == nil then
            _G.YapperDB[key] = default
        end
    end
    -- Upgrade from older DB versions.
    local d = _G.YapperDB.draft
    if type(d) ~= "table" then
        _G.YapperDB.draft = DB_DEFAULTS.draft
    else
        if d.ring == nil then d.ring = {} end
        if d.pos  == nil then d.pos  = 0  end
    end
end

function History:SaveDB()
    -- Mark dirty if the editbox is still open (user mid-type).
    if YapperTable.EditBox and YapperTable.EditBox.Overlay
       and YapperTable.EditBox.Overlay:IsShown() then
        self:SaveDraft(YapperTable.EditBox.OverlayEdit)
        self:MarkDirty(true)
    end
end

-- ---------------------------------------------------------------------------
-- Persistent chat history (Up / Down arrows)
-- ---------------------------------------------------------------------------

--- Add a sent message to persistent history.
function History:AddChatHistory(text)
    if not _G.YapperDB then return end
    if not text or text == "" then return end

    local h = _G.YapperDB.chatHistory
    -- Skip duplicates of the most recent entry.
    if h[#h] == text then return end

    h[#h + 1] = text
    while #h > CHAT_HISTORY_SIZE do
        table.remove(h, 1)
    end
end

--- Return the persistent chat history array.
function History:GetChatHistory()
    if _G.YapperDB and _G.YapperDB.chatHistory then
        return _G.YapperDB.chatHistory
    end
    return {}
end

-- ---------------------------------------------------------------------------
-- Draft auto-save (crash-safe)
-- ---------------------------------------------------------------------------

--- Save current editbox text into the draft ring buffer.
function History:SaveDraft(editbox)
    if not _G.YapperDB then return end
    if not editbox then return end

    local raw = editbox.GetText and editbox:GetText() or ""
    local text = raw:match("^%s*(.-)%s*$") or ""
    if text == "" then return end  -- don't waste a slot on empty/whitespace-only

    local d = _G.YapperDB.draft
    -- Advance ring position (wraps at DRAFT_SLOTS).
    d.pos = (d.pos % DRAFT_SLOTS) + 1
    d.ring[d.pos] = text

    -- Save channel context so recovery re-opens in the right mode.
    local eb = YapperTable.EditBox
    if eb then
        d.chatType = eb.ChatType
        d.target   = eb.Target
    end

    d.dirty = true  -- Assume dirty until proven clean.
end

--- Retrieve the most recent draft text, or nil.
function History:GetDraft()
    if not _G.YapperDB then return nil end
    local d = _G.YapperDB.draft
    if not d or not d.dirty then return nil end
    if not d.ring or d.pos == 0 then return nil end

    -- Walk backwards through the ring for the most recent non-empty entry.
    local count = math.min(#d.ring, DRAFT_SLOTS)
    for i = 0, count - 1 do
        local idx = ((d.pos - 1 - i) % DRAFT_SLOTS) + 1
        local text = d.ring[idx]
        if text and type(text) == "string" then
            local trimmed = text:match("^%s*(.-)%s*$") or ""
            if trimmed ~= "" then
                return text, d.chatType, d.target
            end
        end
    end
    return nil
end

--- Mark the draft as clean (send) or dirty (everything else).
function History:MarkDirty(dirty)
    if not _G.YapperDB or not _G.YapperDB.draft then return end
    _G.YapperDB.draft.dirty = dirty
end

--- Clear the draft ring entirely (after successful send).
function History:ClearDraft()
    if not _G.YapperDB then return end
    _G.YapperDB.draft = {
        ring     = {},
        pos      = 0,
        chatType = nil,
        target   = nil,
        dirty    = false,
    }
end

-- ---------------------------------------------------------------------------
-- Undo / Redo internals
-- ---------------------------------------------------------------------------

--- Get or create the undo buffer for an editbox.
local function GetUndoBuffer(editbox)
    local name = editbox.GetName and editbox:GetName()
    if not name then return nil end
    if not UndoBuffers[name] then
        UndoBuffers[name] = {
            position = 1,
            entries  = { { text = "", cursor = 0 } },
        }
    end
    return UndoBuffers[name]
end

-- ---------------------------------------------------------------------------
-- Public undo/redo API
-- ---------------------------------------------------------------------------

--- Snapshot the current editbox state into the undo buffer.
function History:AddSnapshot(editbox, force)
    local buf = GetUndoBuffer(editbox)
    if not buf then return end

    local text   = editbox:GetText() or ""
    local cursor = editbox:GetCursorPosition() or 0
    local cur    = buf.entries[buf.position]

    -- Skip if text unchanged.
    if cur and text == cur.text then return end

    -- Skip if delta is too small (unless forced).
    if not force and cur then
        if math.abs(#text - #cur.text) < SNAPSHOT_THRESHOLD and text ~= "" then
            return
        end
    end

    -- Discard redo states past current position.
    for i = #buf.entries, buf.position + 1, -1 do
        table.remove(buf.entries, i)
    end

    buf.position = buf.position + 1
    buf.entries[buf.position] = { text = text, cursor = cursor }

    -- Trim old entries.
    while #buf.entries > UNDO_HISTORY_SIZE do
        table.remove(buf.entries, 1)
        buf.position = buf.position - 1
    end
end

function History:Undo(editbox)
    local buf = GetUndoBuffer(editbox)
    if not buf then return end

    self:AddSnapshot(editbox, true)
    if buf.position <= 1 then return end

    buf.position = buf.position - 1
    local entry = buf.entries[buf.position]
    editbox:SetText(entry.text)
    editbox:SetCursorPosition(entry.cursor)

    local name = editbox.GetName and editbox:GetName()
    if name then LastText[name] = entry.text end
end

function History:Redo(editbox)
    local buf = GetUndoBuffer(editbox)
    if not buf then return end

    self:AddSnapshot(editbox, true)
    if buf.position >= #buf.entries then return end

    buf.position = buf.position + 1
    local entry = buf.entries[buf.position]
    editbox:SetText(entry.text)
    editbox:SetCursorPosition(entry.cursor)

    local name = editbox.GetName and editbox:GetName()
    if name then LastText[name] = entry.text end
end

function History:ClearUndoBuffer(editbox)
    local name = editbox.GetName and editbox:GetName()
    if not name then return end
    UndoBuffers[name] = {
        position = 1,
        entries  = { { text = "", cursor = 0 } },
    }
    LastText[name] = ""
end

-- ---------------------------------------------------------------------------
-- Overlay EditBox hooks
-- ---------------------------------------------------------------------------

--- Hook the overlay EditBox for undo/redo and draft saving.
function History:HookOverlayEditBox()
    local editBox = YapperTable.EditBox
    if not editBox then
        YapperTable.Utils:VerbosePrint("History: EditBox module not loaded, skipping hooks.")
        return
    end

    -- Ensure overlay exists (created lazily).
    editBox:CreateOverlay()

    local eb = editBox.OverlayEdit
    if not eb then
        YapperTable.Utils:VerbosePrint("History: overlay EditBox not ready, skipping hooks.")
        return
    end

    -- Text-change tracking for undo snapshots and draft saving.
    eb:HookScript("OnTextChanged", function(box, userInput)
        if YapperTable.YAPPER_DISABLED then return end
        if not userInput then return end

        local name = box.GetName and box:GetName() or "YapperOverlayEdit"
        local text = box:GetText() or ""
        local last = LastText[name] or ""

        -- Undo snapshot on large deltas.
        if math.abs(#text - #last) >= SNAPSHOT_THRESHOLD then
            self:AddSnapshot(box, false)
            LastText[name] = text
        end

        -- Draft save on whitespace (Space, Tab, Enter — natural pause points).
        if #text > 0 then
            local lastChar = text:byte(#text)
            if lastChar == 32 or lastChar == 9 or lastChar == 10 or lastChar == 13 then
                self:SaveDraft(box)
            end
        end
    end)

    -- Ctrl+Z / Ctrl+Y.
    eb:HookScript("OnKeyDown", function(box, key)
        if YapperTable.YAPPER_DISABLED then return end
        if IsControlKeyDown() then
            if key == "Z" then
                self:Undo(box)
            elseif key == "Y" then
                self:Redo(box)
            end
        end
    end)

    -- Snapshot on focus lost.
    eb:HookScript("OnEditFocusLost", function(box)
        if YapperTable.YAPPER_DISABLED then return end
        self:AddSnapshot(box, true)
    end)
end
