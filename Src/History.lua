--[[
    Persistent chat history (survives reloads), crash-safe draft auto-save
    (ring buffer into SavedVariables), and per-session undo/redo.
]]

local YapperName, YapperTable = ...

local History                 = {}
YapperTable.History           = History

-- Localise Lua globals for performance
local table_remove  = table.remove
local math_abs      = math.abs
local type     = type
local pairs    = pairs
local ipairs   = ipairs
local tostring = tostring
local tonumber = tonumber
local GetTime  = GetTime

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------
local UNDO_HISTORY_SIZE       = 20 -- Max undo snapshots per editbox
local CHAT_HISTORY_SIZE       = 50 -- Max persistent sent messages
local SNAPSHOT_THRESHOLD      = 20 -- Min character delta for auto-snapshot

local CURRENT_VERSION         = tonumber((YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.VERSION)) or
1.0

-- Per-editbox undo buffers (keyed by name string).
local UndoBuffers             = {}

-- Last known text per editbox (for change detection).
local LastText                = {}

local function DeepCopy(src)
    if type(src) ~= "table" then
        return src
    end

    local out = {}
    for k, v in pairs(src) do
        out[k] = DeepCopy(v)
    end
    return out
end

-- ---------------------------------------------------------------------------
-- SavedVariable defaults
-- ---------------------------------------------------------------------------
local HISTORY_DEFAULTS = {
    VERSION = CURRENT_VERSION,
    chatHistory = {},     -- Flat array of sent strings, newest last.
    draft = {
        text     = nil,   -- The raw draft text
        chatType = nil,   -- Chat type when draft was taken.
        target   = nil,   -- Whisper target / channel when draft was taken.
        dirty    = false, -- True if editbox was NOT closed via Enter/send.
    },
}

-- ---------------------------------------------------------------------------
-- Init / save
-- ---------------------------------------------------------------------------

--- Set up per-character history from SavedVariables (call after ADDON_LOADED).
function History:InitDB()
    if not _G.YapperLocalHistory then
        _G.YapperLocalHistory = {}
    end

    -- History is now per-character only.
    -- Ensure any legacy account-wide history payload stays removed.
    if type(_G.YapperDB) == "table" then
        _G.YapperDB.chatHistory = nil
        _G.YapperDB.draft = nil
    end

    -- Apply defaults for any missing keys.
    for key, default in pairs(HISTORY_DEFAULTS) do
        if _G.YapperLocalHistory[key] == nil then
            if type(default) == "table" then
                _G.YapperLocalHistory[key] = DeepCopy(default)
            else
                _G.YapperLocalHistory[key] = default
            end
        end
    end

    -- Upgrade from older DB versions.
    local d = _G.YapperLocalHistory.draft
    if type(d) ~= "table" then
        _G.YapperLocalHistory.draft = DeepCopy(HISTORY_DEFAULTS.draft)
    else
        -- Migrate from old ring buffer to direct string storage
        if d.ring ~= nil then
            if type(d.pos) == "number" and d.pos > 0 and d.ring[d.pos] then
                d.text = d.ring[d.pos]
            end
            d.ring = nil
            d.pos = nil
        end
    end

    _G.YapperLocalHistory.VERSION = tonumber(_G.YapperLocalHistory.VERSION) or CURRENT_VERSION
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
--- @param text string The message text
--- @param chatType string|nil Optional: The chat channel (SAY, PARTY, CHANNEL, etc)
--- @param target string|nil Optional: The target (channel number or whisper name)
function History:AddChatHistory(text, chatType, target)
    if not _G.YapperLocalHistory then return end
    if not text or text == "" then return end

    local h = _G.YapperLocalHistory.chatHistory

    -- Check duplication against the most recent entry.
    -- We only skip if the text AND channelcontext (type/target) match.
    -- This allows identical text on say SAY vs WHISPER to be preserved.
    local last = h[#h]
    if type(last) == "table" then
        if last.text == text and last.chatType == chatType and last.target == target then
            return
        end
    elseif last == text then
        -- Legacy string entry check.
        return
    end

    -- Store as table for uniform storage.
    h[#h + 1] = {
        text = text,
        chatType = chatType,
        target = target
    }

    while #h > CHAT_HISTORY_SIZE do
        table_remove(h, 1)
    end
end

--- Return the persistent chat history array.
function History:GetChatHistory()
    if _G.YapperLocalHistory and _G.YapperLocalHistory.chatHistory then
        return _G.YapperLocalHistory.chatHistory
    end
    return {}
end

-- ---------------------------------------------------------------------------
-- Draft auto-save (crash-safe)
-- ---------------------------------------------------------------------------

function History:GetDraftStore()
    if not _G.YapperLocalHistory then
        _G.YapperLocalHistory = {}
    end
    if not _G.YapperLocalHistory.draft then
        _G.YapperLocalHistory.draft = DeepCopy(HISTORY_DEFAULTS.draft)
    end
    return _G.YapperLocalHistory.draft
end

function History:SaveDraft(editBox)
    if not editBox then return end
    local text = editBox:GetText() or ""
    
    -- Bail if empty or just whitespace. We don't want a "zombie" spacebar 
    -- click to overwrite a previously saved multi-sentence draft.
    local trimmed = text:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then return end

    local draft = self:GetDraftStore()
    draft.text = text
    draft.chatType = YapperTable.EditBox and YapperTable.EditBox.ChatType
    draft.target = YapperTable.EditBox and YapperTable.EditBox.Target
    draft.dirty = true
end

function History:GetDraft()
    local draft = self:GetDraftStore()
    if not draft.dirty or not draft.text or draft.text == "" then
        return nil, nil, nil
    end
    return draft.text, draft.chatType, draft.target
end

--- Mark the draft as clean (send) or dirty (everything else).
function History:MarkDirty(dirty)
    local draft = self:GetDraftStore()
    draft.dirty = dirty
end

function History:ClearDraft(editBox)
    local draft = self:GetDraftStore()
    draft.text = nil
    draft.chatType = nil
    draft.target = nil
    draft.dirty = false

    -- Cleanup any pending snapshot timers if the box is provided.
    if editBox then
        self:CancelPauseTimer(editBox)
        
        -- Reset the "LastText" comparison so the next message's first 
        -- character isn't compared against the end of the previous message.
        local name = editBox.GetName and editBox:GetName()
        if name then LastText[name] = "" end
    end
end

--- Cancel the debounced pause-timer for a given editbox.
function History:CancelPauseTimer(editBox)
    if not editBox then return end
    if editBox._yapperPauseTimer then
        editBox._yapperPauseTimer:Cancel()
        editBox._yapperPauseTimer = nil
    end
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
function History:AddSnapshot(editbox, force, textOverride, cursorOverride)
    local buf = GetUndoBuffer(editbox)
    if not buf then return end

    local text
    if textOverride ~= nil then
        text = textOverride
    else
        text = editbox:GetText() or ""
    end

    local cursor
    if cursorOverride ~= nil then
        cursor = cursorOverride
    else
        cursor = editbox:GetCursorPosition() or 0
    end
    local cur = buf.entries[buf.position]

    -- Skip if text unchanged.
    if cur and text == cur.text then return end

    -- Skip if delta is too small (unless forced).
    if not force and cur then
        if math_abs(#text - #cur.text) < SNAPSHOT_THRESHOLD and text ~= "" then
            return
        end
    end

    -- Discard redo states past current position.
    for i = #buf.entries, buf.position + 1, -1 do
        table_remove(buf.entries, i)
    end

    buf.position = buf.position + 1
    buf.entries[buf.position] = { text = text, cursor = cursor }

    -- Trim old entries.
    while #buf.entries > UNDO_HISTORY_SIZE do
        table_remove(buf.entries, 1)
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

    local currentText = editbox:GetText() or ""
    local currentEntry = buf.entries[buf.position]

    -- If user edited after undo, redo chain is invalid.
    if currentEntry and currentText ~= (currentEntry.text or "") then
        return
    end

    if buf.position >= #buf.entries then return end

    buf.position = buf.position + 1
    local entry = buf.entries[buf.position]
    editbox:SetText(entry.text)
    editbox:SetCursorPosition(entry.cursor)

    local name = editbox.GetName and editbox:GetName()
    if name then LastText[name] = entry.text end
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

        local function IsWordBoundaryByte(b)
            -- Whitespace (Space, Tab, Enter) or Punctuation (. , ! ? : ;)
            return b == 32 or b == 9 or b == 10 or b == 13 
                or b == 46 or b == 44 or b == 33 or b == 63 or b == 58 or b == 59
        end

        local textLast            = (#text > 0) and text:byte(#text) or nil
        local lastLast            = (#last > 0) and last:byte(#last) or nil
        local insertedBoundary    = (#text > #last) and IsWordBoundaryByte(textLast)
        local removedBoundary     = (#text < #last) and IsWordBoundaryByte(lastLast)

        -- Undo snapshot on word boundaries using PRE-change text,
        -- otherwise snapshot on large deltas.
        if insertedBoundary or removedBoundary then
            self:AddSnapshot(box, true, last, #last)
            self:SaveDraft(box)
        elseif math_abs(#text - #last) >= SNAPSHOT_THRESHOLD then
            self:AddSnapshot(box, false)
        end

        LastText[name] = text

        -- Debounced "Pause" trigger: snapshot and save draft after 0.5s of inactivity.
        if box._yapperPauseTimer then box._yapperPauseTimer:Cancel() end
        if #text > 0 then
            box._yapperPauseTimer = C_Timer.NewTimer(0.5, function()
                if box:GetText() == text then -- verify still matches
                    self:AddSnapshot(box, true)
                    self:SaveDraft(box)
                end
            end)
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
