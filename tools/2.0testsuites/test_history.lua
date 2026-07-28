#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_history.lua  --  History module unit tests (undo/redo, chat history,
--                       draft save/restore)
-- Run from the repo root:  lua tools/2.0testsuites/test_history.lua
-- ---------------------------------------------------------------------------

local PASS, FAIL, TESTS, FAILURES = "PASS", "FAIL", 0, 0

local function check(label, condition)
    TESTS = TESTS + 1
    if condition then
        print("  [" .. PASS .. "] " .. label)
    else
        FAILURES = FAILURES + 1
        print("  [" .. FAIL .. "] " .. label)
    end
end

-- ===========================================================================
-- Minimal WoW environment mock
-- ===========================================================================

_G = _G or {}
_G.GetTime = function() return 0 end
_G.C_Timer = {
    NewTimer = function(sec, fn)
        return { Cancel = function() end }
    end,
}

-- Minimal EditBox mock.
local function MockEditBox(name)
    local self = {
        _name = name or "MockEditBox",
        _text = "",
        _cursor = 0,
    }
    function self:GetName() return self._name end
    function self:GetText() return self._text end
    function self:SetText(t) self._text = t end
    function self:GetCursorPosition() return self._cursor end
    function self:SetCursorPosition(p) self._cursor = p end
    return self
end

local YapperName = "Yapper"
local YapperTable = {
    Config = {
        System = { VERSION = "2.0" },
        Chat = {},
    },
    State = {
        IsMultiline = function() return false end,
    },
    Utils = {
        VerbosePrint = function() end,
    },
}

-- History uses the global YapperLocalHistory.
_G.YapperLocalHistory = nil
_G.YapperDB = nil

-- Load History.lua.
local loader, err = loadfile("Src/History.lua")
if not loader then
    print("FATAL: " .. tostring(err))
    os.exit(1)
end
loader(YapperName, YapperTable)

-- History reads canonical text through Recolour (production dependency).
local rc_loader, rc_err = loadfile("Src/Spellcheck/Recolour.lua")
if not rc_loader then
    print("FATAL: " .. tostring(rc_err))
    os.exit(1)
end
rc_loader(YapperName, YapperTable)

local History = YapperTable.History

-- ===========================================================================
-- Test 1: InitDB creates default structure
-- ===========================================================================
print("\nTest 1: InitDB creates defaults")

_G.YapperLocalHistory = nil
History:InitDB()

check("YapperLocalHistory created", _G.YapperLocalHistory ~= nil)
check("chatHistory array exists", type(_G.YapperLocalHistory.chatHistory) == "table")
check("chatHistory is empty", #_G.YapperLocalHistory.chatHistory == 0)
check("draft table exists", type(_G.YapperLocalHistory.draft) == "table")
check("draft.dirty is false", _G.YapperLocalHistory.draft.dirty == false)
check("VERSION set", _G.YapperLocalHistory.VERSION ~= nil)

-- ===========================================================================
-- Test 2: InitDB preserves existing data
-- ===========================================================================
print("\nTest 2: InitDB preserves existing data")

_G.YapperLocalHistory = {
    chatHistory = { { text = "old message", chatType = "SAY" } },
    draft = { text = "draft text", dirty = true },
}
History:InitDB()

check("existing chatHistory preserved", #_G.YapperLocalHistory.chatHistory == 1)
check("existing chat text preserved", _G.YapperLocalHistory.chatHistory[1].text == "old message")
check("existing draft preserved", _G.YapperLocalHistory.draft.text == "draft text")

-- ===========================================================================
-- Test 3: InitDB ring-buffer migration
-- ===========================================================================
print("\nTest 3: Ring-buffer draft migration")

_G.YapperLocalHistory = {
    chatHistory = {},
    draft = {
        ring = { "entry1", "entry2", "entry3" },
        pos = 2,
        dirty = true,
    },
}
History:InitDB()

check("ring buffer migrated to text", _G.YapperLocalHistory.draft.text == "entry2")
check("ring removed", _G.YapperLocalHistory.draft.ring == nil)
check("pos removed", _G.YapperLocalHistory.draft.pos == nil)

-- ===========================================================================
-- Test 4: AddChatHistory / GetChatHistory
-- ===========================================================================
print("\nTest 4: Chat history add/get")

_G.YapperLocalHistory = nil
History:InitDB()

History:AddChatHistory("Hello world", "SAY", nil)
local h = History:GetChatHistory()
check("one entry after add", #h == 1)
check("entry text correct", h[1].text == "Hello world")
check("entry chatType correct", h[1].chatType == "SAY")

History:AddChatHistory("Whisper test", "WHISPER", "PlayerName")
h = History:GetChatHistory()
check("two entries after second add", #h == 2)
check("second entry text", h[2].text == "Whisper test")
check("second entry target", h[2].target == "PlayerName")

-- ===========================================================================
-- Test 5: AddChatHistory deduplication
-- ===========================================================================
print("\nTest 5: Chat history deduplication")

_G.YapperLocalHistory = nil
History:InitDB()

History:AddChatHistory("Repeat me", "SAY", nil)
History:AddChatHistory("Repeat me", "SAY", nil)
h = History:GetChatHistory()
check("duplicate text+channel not added", #h == 1)

-- Same text, different channel should be added.
History:AddChatHistory("Repeat me", "WHISPER", "SomePlayer")
h = History:GetChatHistory()
check("same text on different channel added", #h == 2)

-- ===========================================================================
-- Test 6: AddChatHistory rejects empty/nil
-- ===========================================================================
print("\nTest 6: Chat history rejects empty/nil")

_G.YapperLocalHistory = nil
History:InitDB()

History:AddChatHistory(nil, "SAY", nil)
History:AddChatHistory("", "SAY", nil)
h = History:GetChatHistory()
check("nil text not added", #h == 0)

-- ===========================================================================
-- Test 7: Chat history cap
-- ===========================================================================
print("\nTest 7: Chat history cap")

_G.YapperLocalHistory = nil
History:InitDB()

-- Default cap is 50. Add 60 entries.
for i = 1, 60 do
    History:AddChatHistory("Message " .. i, "SAY", nil)
end
h = History:GetChatHistory()
check("history capped at 50", #h == 50)
check("oldest entries trimmed (first is #11)", h[1].text == "Message 11")
check("newest entry is last", h[50].text == "Message 60")

-- ===========================================================================
-- Test 8: Draft save/get/clear
-- ===========================================================================
print("\nTest 8: Draft save/get/clear")

_G.YapperLocalHistory = nil
History:InitDB()

local eb = MockEditBox("TestDraftBox")
eb:SetText("My draft text")

-- Stub EditBox module for single-line draft.
YapperTable.EditBox = {
    ChatType = "SAY",
    Target = nil,
    _externalWhisperTarget = nil,
}

History:SaveDraft(eb, false)
local text, chatType, target, multiline = History:GetDraft()
check("draft text saved", text == "My draft text")
check("draft chatType saved", chatType == "SAY")
check("draft target nil for SAY", target == nil)
check("draft not multiline", multiline == false)

History:ClearDraft(eb)
text, chatType, target, multiline = History:GetDraft()
check("cleared draft returns nil text", text == nil)
check("cleared draft returns nil chatType", chatType == nil)

-- ===========================================================================
-- Test 9: Draft ignores whitespace-only text
-- ===========================================================================
print("\nTest 9: Draft ignores whitespace")

_G.YapperLocalHistory = nil
History:InitDB()

local eb2 = MockEditBox("WhitespaceBox")
eb2:SetText("   ")
History:SaveDraft(eb2, false)
local text2 = History:GetDraft()
check("whitespace-only draft not saved", text2 == nil)

-- ===========================================================================
-- Test 10: MarkDirty
-- ===========================================================================
print("\nTest 10: MarkDirty")

_G.YapperLocalHistory = nil
History:InitDB()

History:MarkDirty(true)
local store = History:GetDraftStore()
check("dirty set to true", store.dirty == true)

History:MarkDirty(false)
check("dirty set to false", store.dirty == false)

-- ===========================================================================
-- Test 11: Undo / Redo basic flow
-- ===========================================================================
print("\nTest 11: Undo / Redo")

local eb3 = MockEditBox("UndoTestBox")
eb3:SetText("")
eb3:SetCursorPosition(0)

-- Add initial snapshot (empty).
History:AddSnapshot(eb3, true)

-- Type "Hello".
eb3:SetText("Hello")
eb3:SetCursorPosition(5)
History:AddSnapshot(eb3, true)

-- Type " World".
eb3:SetText("Hello World")
eb3:SetCursorPosition(11)
History:AddSnapshot(eb3, true)

-- Undo once: should go back to "Hello".
History:Undo(eb3)
check("undo restores previous text", eb3:GetText() == "Hello")
check("undo restores cursor", eb3:GetCursorPosition() == 5)

-- Undo again: should go back to "".
History:Undo(eb3)
check("second undo restores empty", eb3:GetText() == "")

-- Redo: should go forward to "Hello".
History:Redo(eb3)
check("redo restores 'Hello'", eb3:GetText() == "Hello")

-- Redo again: should go to "Hello World".
History:Redo(eb3)
check("second redo restores 'Hello World'", eb3:GetText() == "Hello World")

-- Redo at end: should be no-op.
History:Redo(eb3)
check("redo at end is no-op", eb3:GetText() == "Hello World")

-- ===========================================================================
-- Test 12: Undo at beginning is no-op
-- ===========================================================================
print("\nTest 12: Undo at beginning")

-- GetUndoBuffer initializes with an empty-string entry at position 1.
-- After AddSnapshot, buffer is: ["", "Only state"]. Undo goes to "".
-- Second Undo should be no-op at position 1.
local eb4 = MockEditBox("UndoBeginBox")
eb4:SetText("Only state")
eb4:SetCursorPosition(10)
History:AddSnapshot(eb4, true)

History:Undo(eb4)
check("first undo goes to initial empty state", eb4:GetText() == "")

History:Undo(eb4)
check("second undo at beginning is no-op", eb4:GetText() == "")

-- ===========================================================================
-- Test 13: Editing after undo invalidates redo chain
-- ===========================================================================
print("\nTest 13: Edit after undo invalidates redo")

local eb5 = MockEditBox("RedoInvalidBox")
eb5:SetText("A")
eb5:SetCursorPosition(1)
History:AddSnapshot(eb5, true)

eb5:SetText("AB")
eb5:SetCursorPosition(2)
History:AddSnapshot(eb5, true)

eb5:SetText("ABC")
eb5:SetCursorPosition(3)
History:AddSnapshot(eb5, true)

-- Undo to "AB".
History:Undo(eb5)
check("undo to AB", eb5:GetText() == "AB")

-- Edit to "AX" (diverge from redo chain).
eb5:SetText("AX")
eb5:SetCursorPosition(2)
History:AddSnapshot(eb5, true)

-- Redo should be no-op since we diverged.
History:Redo(eb5)
check("redo after edit is no-op", eb5:GetText() == "AX")

-- ===========================================================================
-- Test 14: AddSnapshot skips duplicate text
-- ===========================================================================
print("\nTest 14: AddSnapshot dedup")

local eb6 = MockEditBox("DedupBox")
eb6:SetText("Same text")
eb6:SetCursorPosition(9)
History:AddSnapshot(eb6, true)
History:AddSnapshot(eb6, true)
History:AddSnapshot(eb6, true)

-- Buffer is: ["", "Same text"]. Three identical calls only add one entry.
-- Undo goes back to the initial empty state, not to duplicate entries.
History:Undo(eb6)
check("undo goes to initial state (duplicates not stacked)", eb6:GetText() == "")

-- One more undo is a no-op.
History:Undo(eb6)
check("second undo is no-op at beginning", eb6:GetText() == "")

-- ===========================================================================
-- Test 15: SaveDraft with nil editbox doesn't crash
-- ===========================================================================
print("\nTest 15: SaveDraft nil editbox safety")

History:SaveDraft(nil, false)
check("nil editbox doesn't crash", true)

-- ===========================================================================
-- Results
-- ===========================================================================
print("\n" .. string.rep("-", 50))
print(string.format("Results: %d/%d passed", TESTS - FAILURES, TESTS))
if FAILURES > 0 then
    print(FAILURES .. " FAILURE(S)")
    os.exit(1)
else
    print("All tests passed.")
end
