-- History module: Undo/Redo and persistent chat history.
-- This gives us Ctrl+Z / Ctrl+Y in editboxes, and preserves sent message
-- history across reloads (the up/down arrow stuff).
local YapperName, YapperTable = ...

local History = {}
YapperTable.History = History

-- Configuration
local UNDO_HISTORY_SIZE = 20       -- How many undo states to keep per editbox
local CHAT_HISTORY_SIZE = 50       -- How many sent messages to remember
local SNAPSHOT_THRESHOLD = 20     -- Minimum character change to trigger snapshot

-- Per-editbox state (keyed by editbox name)
-- Structure: { position = n, entries = {{text, cursor}, ...} }
local UndoBuffers = {}

-- Tracks last known text per editbox to detect changes
local LastText = {}

-------------------------------------------------------------------------------------
-- SAVED VARIABLES --
-- YapperDB is defined in the TOC. It'll be nil until ADDON_LOADED fires,
-- then WoW populates it with saved data (or leaves it nil if first run).

--- Default structure for our saved data.
local DB_DEFAULTS = {
    undo = {},       -- Per-character undo history (keyed by editbox name)
    chatHistory = {} -- Sent message history (the up-arrow stuff)
}

--- Initialise the database. Called after ADDON_LOADED.
function History:InitDB()
    -- If YapperDB doesn't exist or is empty, create defaults.
    if not _G.YapperDB then
        _G.YapperDB = {}
    end
    
    -- Merge defaults for any missing keys.
    for key, default in pairs(DB_DEFAULTS) do
        if _G.YapperDB[key] == nil then
            _G.YapperDB[key] = default
        end
    end
    
    -- Load undo buffers from saved data.
    for name, data in pairs(_G.YapperDB.undo) do
        UndoBuffers[name] = data
    end
    
    YapperTable.Utils:VerbosePrint("History database initialised.")
end

--- Save current state to the database. Called before logout.
function History:SaveDB()
    if not _G.YapperDB then return end
    
    -- Save undo buffers.
    _G.YapperDB.undo = {}
    for name, data in pairs(UndoBuffers) do
        _G.YapperDB.undo[name] = data
    end
    
    YapperTable.Utils:VerbosePrint("History database saved.")
end

-------------------------------------------------------------------------------------
-- UNDO BUFFER MANAGEMENT --

--- Get or create the undo buffer for an editbox.
--- @param editbox table The editbox frame
--- @return table The undo buffer for this editbox
local function GetUndoBuffer(editbox)
    local name = editbox:GetName()
    if not name then return nil end
    
    if not UndoBuffers[name] then
        UndoBuffers[name] = {
            position = 1,
            entries = {
                { text = "", cursor = 0 }  -- Initial empty state
            }
        }
    end
    return UndoBuffers[name]
end

--- Add a snapshot to the undo history.
--- @param editbox table The editbox frame
--- @param force boolean If true, snapshot regardless of change size
function History:AddSnapshot(editbox, force)
    local buffer = GetUndoBuffer(editbox)
    if not buffer then return end
    
    local text = editbox:GetText() or ""
    local cursor = editbox:GetCursorPosition() or 0
    local currentEntry = buffer.entries[buffer.position]
    
    -- Skip if text hasn't changed.
    if currentEntry and text == currentEntry.text then
        return
    end
    
    -- Skip if change is too small (unless forced).
    if not force and currentEntry then
        local delta = math.abs(#text - #currentEntry.text)
        if delta < SNAPSHOT_THRESHOLD and text ~= "" then
            return
        end
    end
    
    -- If we're not at the end, we're rewriting history (heh).
    -- Discard any redo states.
    if buffer.position < #buffer.entries then
        for i = #buffer.entries, buffer.position + 1, -1 do
            table.remove(buffer.entries, i)
        end
    end
    
    -- Add new entry.
    buffer.position = buffer.position + 1
    buffer.entries[buffer.position] = {
        text = text,
        cursor = cursor
    }
    
    -- Trim old entries if we're over the limit.
    while #buffer.entries > UNDO_HISTORY_SIZE do
        table.remove(buffer.entries, 1)
        buffer.position = buffer.position - 1
    end
    
    YapperTable.Utils:VerbosePrint("Snapshot added, position: " .. buffer.position .. "/" .. #buffer.entries)
end

--- Undo: Go back one step in history.
--- @param editbox table The editbox frame
function History:Undo(editbox)
    local buffer = GetUndoBuffer(editbox)
    if not buffer then return end
    
    -- Snapshot current state first (in case user made changes).
    self:AddSnapshot(editbox, true)
    
    -- Can't undo if we're at the beginning.
    if buffer.position <= 1 then
        YapperTable.Utils:VerbosePrint("Nothing to undo.")
        return
    end
    
    buffer.position = buffer.position - 1
    local entry = buffer.entries[buffer.position]
    
    -- Restore text and cursor.
    editbox:SetText(entry.text)
    editbox:SetCursorPosition(entry.cursor)
    
    -- Update tracking so we don't re-snapshot this.
    LastText[editbox:GetName()] = entry.text
    
    YapperTable.Utils:VerbosePrint("Undo to position: " .. buffer.position)
end

--- Redo: Go forward one step in history.
--- @param editbox table The editbox frame
function History:Redo(editbox)
    local buffer = GetUndoBuffer(editbox)
    if not buffer then return end
    
    -- Snapshot current state first (might have changed since last undo).
    self:AddSnapshot(editbox, true)
    
    -- Can't redo if we're at the end.
    if buffer.position >= #buffer.entries then
        YapperTable.Utils:VerbosePrint("Nothing to redo.")
        return
    end
    
    buffer.position = buffer.position + 1
    local entry = buffer.entries[buffer.position]
    
    -- Restore text and cursor.
    editbox:SetText(entry.text)
    editbox:SetCursorPosition(entry.cursor)
    
    -- Update tracking.
    LastText[editbox:GetName()] = entry.text
    
    YapperTable.Utils:VerbosePrint("Redo to position: " .. buffer.position)
end

-------------------------------------------------------------------------------------
-- CHAT HISTORY (UP/DOWN ARROW) --

--- Add a sent message to persistent chat history.
--- @param text string The message that was sent
function History:AddChatHistory(text)
    if not _G.YapperDB then return end
    if not text or text == "" then return end
    
    local history = _G.YapperDB.chatHistory
    
    -- Don't add duplicates of the last entry.
    if history[#history] == text then
        return
    end
    
    table.insert(history, text)
    
    -- Trim if over limit.
    while #history > CHAT_HISTORY_SIZE do
        table.remove(history, 1)
    end
end

--- Load persistent chat history into an editbox.
--- Call this after the editbox is set up.
--- @param editbox table The editbox frame
function History:LoadChatHistoryIntoEditbox(editbox)
    if not _G.YapperDB or not _G.YapperDB.chatHistory then return end
    
    -- WoW's editbox has AddHistoryLine which we can populate.
    -- We add from oldest to newest so the order is correct.
    for _, text in ipairs(_G.YapperDB.chatHistory) do
        editbox:AddHistoryLine(text)
    end
    
    YapperTable.Utils:VerbosePrint("Loaded " .. #_G.YapperDB.chatHistory .. " history lines into " .. (editbox:GetName() or "editbox"))
end

-------------------------------------------------------------------------------------
-- EDITBOX HOOKS --

--- OnTextChanged handler: detect significant changes for snapshots.
--- @param editbox table The editbox frame
local function OnTextChanged(editbox)
    if YapperTable.YAPPER_DISABLED then return end
    
    local name = editbox:GetName()
    if not name then return end
    
    local text = editbox:GetText() or ""
    local last = LastText[name] or ""
    
    -- Check if change is significant enough.
    local delta = math.abs(#text - #last)
    if delta >= SNAPSHOT_THRESHOLD then
        History:AddSnapshot(editbox, false)
        LastText[name] = text
    end
end

--- OnKeyDown handler: catch Ctrl+Z and Ctrl+Y.
--- @param editbox table The editbox frame
--- @param key string The key that was pressed
local function OnKeyDown(editbox, key)
    if YapperTable.YAPPER_DISABLED then return end
    
    -- Only handle Ctrl+Z and Ctrl+Y for undo/redo.
    -- Don't touch SetPropagateKeyboardInput at all - editboxes capture keys by default.
    if IsControlKeyDown() then
        if key == "Z" then
            History:Undo(editbox)
        elseif key == "Y" then
            History:Redo(editbox)
        end
    end
end

--- OnEditFocusLost handler: snapshot when leaving the editbox.
--- @param editbox table The editbox frame
local function OnEditFocusLost(editbox)
    if YapperTable.YAPPER_DISABLED then return end
    History:AddSnapshot(editbox, true)
end

--- Hook an editbox for history functionality.
--- @param editbox table The editbox frame
function History:HookEditbox(editbox)
    if not editbox then return end
    
    local name = editbox:GetName()
    if not name then return end
    
    -- Initialise tracking.
    LastText[name] = editbox:GetText() or ""
    
    -- Hook for text changes (snapshot detection).
    editbox:HookScript("OnTextChanged", OnTextChanged)
    
    -- Hook for keyboard input (Ctrl+Z / Ctrl+Y).
    editbox:HookScript("OnKeyDown", OnKeyDown)
    
    -- Hook for focus lost (final snapshot).
    editbox:HookScript("OnEditFocusLost", OnEditFocusLost)
    
    -- Load any saved chat history into this editbox.
    self:LoadChatHistoryIntoEditbox(editbox)
    
    YapperTable.Utils:VerbosePrint("History hooks added to: " .. name)
end

--- Clear undo history for an editbox (e.g., after successful send).
--- @param editbox table The editbox frame
function History:ClearUndoBuffer(editbox)
    local name = editbox:GetName()
    if not name then return end
    
    UndoBuffers[name] = {
        position = 1,
        entries = {
            { text = "", cursor = 0 }
        }
    }
    LastText[name] = ""
end
