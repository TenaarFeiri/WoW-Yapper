#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_autocorrect.lua  --  Autocorrect module unit tests
-- Run from the repo root:  lua tools/2.0testsuites/test_autocorrect.lua
--
-- Covers: core ClassifyBoundary defaults + engine override/purge contract,
-- boundary-commit application (AUTO tier only), mid-word / slash / ignored
-- guards, the stateless backspace-revert, Ctrl+Z detection, toast undo
-- validation, and the session suppression loop guard.
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
_G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
_G.GetTime = function() return 100 end
_G.time = os.time -- WoW global; standard Lua only ships os.time
_G.C_Timer = {
    NewTimer = function(_, fn) return { Cancel = function() end, _fn = fn } end,
    After    = function(_, fn) fn() end,
}

local function MockEditBox(name)
    local self = { _name = name or "MockEditBox", _text = "", _cursor = 0 }
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
        System = { DEBUG = false, VERBOSE = false },
        Spellcheck = {
            Enabled = true,
            Locale = "tloc",
            AutocorrectEnabled = true,
            AutocorrectToast = false, -- toasts exercised separately
        },
    },
}

local function loadModule(path)
    local loader, err = loadfile(path)
    if not loader then
        print("FATAL: cannot load " .. path .. ": " .. tostring(err))
        os.exit(1)
    end
    loader(YapperName, YapperTable)
end

loadModule("Src/Utils.lua")
YapperTable.Utils.Print = function() end

loadModule("Src/Spellcheck.lua")
loadModule("Src/Spellcheck/Dictionary.lua")
loadModule("Src/Spellcheck/Engine.lua")
loadModule("Src/Spellcheck/Autocorrect.lua")

local Spellcheck  = YapperTable.Spellcheck
local Autocorrect = Spellcheck.Autocorrect

-- Canonical text accessors normally come from Recolour; the edit boxes here
-- hold plain text, so a trivial shim is equivalent.
YapperTable.Recolour = {
    CanonicalText = function(box) return box:GetText() end,
    CanonicalTextAndCursor = function(box)
        return box:GetText(), box:GetCursorPosition()
    end,
}

-- API event spy + history snapshot spy.
local firedEvents = {}
YapperTable.API = { Fire = function(_, ev, a, b) firedEvents[#firedEvents + 1] = { ev, a, b } end }
local snapshots = 0
YapperTable.History = { AddSnapshot = function() snapshots = snapshots + 1 end }

-- ---------------------------------------------------------------------------
-- Controllable stubs around the suggestion/YAS pipeline
-- ---------------------------------------------------------------------------
local GOOD_WORDS    = {}   -- words IsWordCorrect accepts
local SUGGESTIONS   = {}   -- entries GetSuggestions returns
local YAS_DECISION  = nil  -- decision table ClassifySuggestion returns
local YAS_DECISIONS = nil  -- optional per-candidate map: cand -> decision
local YAS_INTENTS   = {}   -- token -> intent class returned by GetIntent
local YAS_DB        = nil  -- when non-nil, GetLocaleDB returns this db
local selectionLog  = {}
local rejectLog     = {}
local undoRing      = {}

Spellcheck.GetConfig          = function() return YapperTable.Config.Spellcheck end
Spellcheck.IsEnabled          = function() return true end
Spellcheck.GetLocale          = function() return "tloc" end
Spellcheck.GetMinWordLength   = function() return 2 end
Spellcheck.GetIgnoredRanges   = function() return {} end
Spellcheck.IsRangeIgnored     = function() return false end
Spellcheck.GetUserSets        = function() return nil, nil, nil end
Spellcheck.IsWordCorrect      = function(_, w) return GOOD_WORDS[w] == true end
Spellcheck.GetSuggestions     = function() return SUGGESTIONS end
Spellcheck.ScheduleRefresh    = function() end

Spellcheck.YAS = {
    IsEnabled           = function() return true end,
    ClassifySuggestion  = function(_, _, cand)
        if YAS_DECISIONS and YAS_DECISIONS[cand] ~= nil then
            return YAS_DECISIONS[cand]
        end
        return YAS_DECISION
    end,
    GetIntent           = function(_, w) return YAS_INTENTS[w] end,
    GetLocaleDB         = function(_, _, _) return YAS_DB end,
    RecordSelection     = function(_, typo, corr, gain, loc)
        selectionLog[#selectionLog + 1] = { typo = typo, corr = corr, gain = gain, loc = loc }
    end,
    RecordAutoReject    = function(_, typo, corr, loc)
        rejectLog[#rejectLog + 1] = { typo = typo, corr = corr, loc = loc }
    end,
    PushUndo = function(_, e) undoRing[#undoRing + 1] = e end,
    PopUndo  = function() return table.remove(undoRing) end,
    PeekUndo = function() return undoRing[#undoRing] end,
}

local function resetState()
    GOOD_WORDS   = {}
    SUGGESTIONS  = {}
    YAS_DECISION = nil
    YAS_DECISIONS = nil
    YAS_INTENTS   = {}
    YAS_DB        = nil
    selectionLog = {}
    rejectLog    = {}
    undoRing     = {}
    firedEvents  = {}
    snapshots    = 0
    Autocorrect._corrections = {}
    Autocorrect._suppressed  = {}
    Spellcheck.ActiveRange   = nil
    Spellcheck.EditBox       = nil
end

-- ===========================================================================
-- Test 1: core ClassifyBoundary defaults (no engine registered)
-- ===========================================================================
print("\nTest 1: ClassifyBoundary core defaults")

resetState()
check("space commits",            Spellcheck:ClassifyBoundary("hi ", 3) == "commit")
check("newline commits",          Spellcheck:ClassifyBoundary("hi\n", 3) == "commit")
check("period closes",            Spellcheck:ClassifyBoundary("hi.", 3) == "close")
check("comma closes",             Spellcheck:ClassifyBoundary("a,b", 2) == "close")
check("question mark closes",     Spellcheck:ClassifyBoundary("huh?", 4) == "close")
check("letter is none",           Spellcheck:ClassifyBoundary("abc", 2) == "none")
check("apostrophe is none",       Spellcheck:ClassifyBoundary("don't", 4) == "none")
check("out-of-range is none",     Spellcheck:ClassifyBoundary("hi", 99) == "none")
check("bad args are none",        Spellcheck:ClassifyBoundary(nil, 1) == "none")

-- Quote parity: '"' before an even count of prior quotes opens, odd closes.
check("first quote opens",        Spellcheck:ClassifyBoundary('say "', 5) == "open")
check("second quote closes",      Spellcheck:ClassifyBoundary('"hi"', 4) == "close")
check("third quote opens again",  Spellcheck:ClassifyBoundary('"a" "b"', 5) == "open")
check("fourth quote closes",      Spellcheck:ClassifyBoundary('"a" "b"', 7) == "close")

-- ===========================================================================
-- Test 2: engine contract for ClassifyBoundary
-- ===========================================================================
print("\nTest 2: engine override + contract probes")

local function byteSet(extra)
    local t = {}
    for b = 65, 90 do t[b] = true end
    for b = 97, 122 do t[b] = true end
    for b = 128, 255 do t[b] = true end
    for _, b in ipairs(extra or {}) do t[b] = true end
    return t
end

local function makeEngine()
    return {
        NormaliseWord   = function(w) return type(w) == "string" and w:lower() or "" end,
        NormaliseVowels = function(w) return (w:lower():gsub("[aeiou]", "*")) end,
        GetPhoneticHash = function(w) return w:upper():gsub("[AEIOU]", "") end,
        HashWord        = function(w)
            local h = 5381
            for i = 1, #w do h = (h * 33 + w:byte(i)) % 4294967296 end
            return h
        end,
        BlockedHashes   = {},
        WordBytes       = byteSet({ 39 }),
        WordStartBytes  = byteSet(),
        Locales         = { "tloc" },
    }
end

local function resetEngines()
    Spellcheck.LanguageEngines = {}
    Spellcheck._engineOwners = {}
    Spellcheck._engineFamily = {}
    Spellcheck._failedEngines = {}
    Spellcheck.Dictionaries = {}
    Spellcheck._failedLocaleLoads = {}
    Spellcheck.UserDictCache = {}
    Spellcheck:ClearSuggestionCache()
end

-- nil / valid enum returns pass registration.
for _, ret in ipairs({ "commit", "close", "open", "none", "" }) do
    resetEngines()
    local e = makeEngine()
    e.ClassifyBoundary = function() return ret end
    check("ClassifyBoundary '" .. ret .. "' accepted",
        Spellcheck:_RegisterLanguageEngine("cb", e) == true)
end

resetEngines()
local eNil = makeEngine()
eNil.ClassifyBoundary = function() return nil end
check("ClassifyBoundary nil accepted",
    Spellcheck:_RegisterLanguageEngine("cbn", eNil) == true)

-- Invalid enum value rejected at registration.
resetEngines()
local eBad = makeEngine()
eBad.ClassifyBoundary = function() return "sideways" end
check("invalid enum rejected",
    Spellcheck:_RegisterLanguageEngine("cbb", eBad) ~= true)

-- Erroring probe rejected.
resetEngines()
local eErr = makeEngine()
eErr.ClassifyBoundary = function() error("boom") end
check("erroring probe rejected",
    Spellcheck:_RegisterLanguageEngine("cbe", eErr) ~= true)

-- Non-function type rejected by the optional-field type check.
resetEngines()
local eType = makeEngine()
eType.ClassifyBoundary = 42
check("non-function rejected",
    Spellcheck:_RegisterLanguageEngine("cbt", eType) ~= true)

-- Engine override wins at runtime: "none" for every byte disables commits.
resetEngines()
local eNone = makeEngine()
eNone.ClassifyBoundary = function() return "none" end
check("none-engine registers", Spellcheck:_RegisterLanguageEngine("cb2", eNone) == true)
check("engine override wins (space -> none)",
    Spellcheck:ClassifyBoundary("hi ", 3) == "none")

-- Runtime-invalid return falls through to the core default (probe sees nil).
resetEngines()
local eFlaky = makeEngine()
eFlaky.ClassifyBoundary = function(_, pos)
    if pos == 12 then return nil end  -- the contract probe position
    return "bogus"
end
check("flaky engine registers", Spellcheck:_RegisterLanguageEngine("cb3", eFlaky) == true)
check("invalid runtime return falls back to core",
    Spellcheck:ClassifyBoundary("hi ", 3) == "commit")

resetEngines() -- leave no engine registered for the module tests below

-- ===========================================================================
-- Test 3: boundary-commit application
-- ===========================================================================
print("\nTest 3: OnBoundaryCommit applies AUTO-tier corrections")

resetState()
SUGGESTIONS  = { { kind = "word", value = "the" } }
YAS_DECISION = { tier = "AUTO", suggestion = "the", confidence = 0.9 }

local box = MockEditBox("b1")
box:SetText("teh ")
box:SetCursorPosition(4)
Autocorrect:OnBoundaryCommit(box, "teh ", 4)
check("correction applied", box:GetText() == "the ")
check("caret preserved after boundary", box:GetCursorPosition() == 4)
check("correction recorded", #Autocorrect._corrections == 1)
check("undo entry pushed", #undoRing == 1)
check("AUTOCORRECT_APPLIED fired", firedEvents[1] and firedEvents[1][1] == "AUTOCORRECT_APPLIED")
check("implicit accept recorded with zero gain",
    selectionLog[1] and selectionLog[1].typo == "teh"
    and selectionLog[1].corr == "the" and selectionLog[1].gain == 0)

-- Non-AUTO tiers never touch the text.
resetState()
SUGGESTIONS  = { { kind = "word", value = "the" } }
YAS_DECISION = { tier = "SUGGEST" }
box = MockEditBox("b2")
box:SetText("teh ")
box:SetCursorPosition(4)
Autocorrect:OnBoundaryCommit(box, "teh ", 4)
check("SUGGEST tier does not apply", box:GetText() == "teh ")

resetState()
YAS_DECISION = nil -- classifier declined
box:SetText("teh ")
box:SetCursorPosition(4)
Autocorrect:OnBoundaryCommit(box, "teh ", 4)
check("nil decision does not apply", box:GetText() == "teh ")

-- Multiple candidates: the highest-confidence AUTO wins, not rank order
-- ("doign" -> "deign" was rank 1 but "doing" classifies more confidently).
resetState()
SUGGESTIONS = {
    { kind = "word", value = "deign" },
    { kind = "word", value = "doing" },
}
YAS_DECISIONS = {
    deign = { tier = "AUTO", confidence = 0.80 },
    doing = { tier = "AUTO", confidence = 0.85 },
}
box = MockEditBox("m1")
box:SetText("doign ")
box:SetCursorPosition(6)
Autocorrect:OnBoundaryCommit(box, "doign ", 6)
check("highest-confidence AUTO wins over rank", box:GetText() == "doing ",
    box:GetText())

-- A non-AUTO rank 1 does not block an AUTO rank 2.
resetState()
SUGGESTIONS = {
    { kind = "word", value = "deign" },
    { kind = "word", value = "doing" },
}
YAS_DECISIONS = {
    deign = { tier = "OFFER", confidence = 0.1 },
    doing = { tier = "AUTO", confidence = 0.85 },
}
box = MockEditBox("m2")
box:SetText("doign ")
box:SetCursorPosition(6)
Autocorrect:OnBoundaryCommit(box, "doign ", 6)
check("AUTO rank 2 applies past OFFER rank 1", box:GetText() == "doing ")

-- A suppressed pair is skipped, not fatal: the next AUTO candidate applies.
resetState()
SUGGESTIONS = {
    { kind = "word", value = "deign" },
    { kind = "word", value = "doing" },
}
YAS_DECISIONS = {
    deign = { tier = "AUTO", confidence = 0.80 },
    doing = { tier = "AUTO", confidence = 0.85 },
}
Autocorrect._suppressed["doign\0doing"] = true
box = MockEditBox("m3")
box:SetText("doign ")
box:SetCursorPosition(6)
Autocorrect:OnBoundaryCommit(box, "doign ", 6)
check("suppressed pair skipped, next AUTO applies", box:GetText() == "deign ")

-- A token-level veto short-circuits the whole candidate list.
resetState()
SUGGESTIONS = {
    { kind = "word", value = "deign" },
    { kind = "word", value = "doing" },
}
YAS_DECISIONS = {
    deign = { tier = "SUPPRESS", vetoReasons = { intentional = true } },
    doing = { tier = "AUTO", confidence = 0.85 },
}
box = MockEditBox("m4")
box:SetText("doign ")
box:SetCursorPosition(6)
Autocorrect:OnBoundaryCommit(box, "doign ", 6)
check("intentional veto stops all candidates", box:GetText() == "doign ")

-- ===========================================================================
-- Test 4: commit guards
-- ===========================================================================
print("\nTest 4: guards (mid-word, slash, correct, ignored, open-quote)")

resetState()
SUGGESTIONS  = { { kind = "word", value = "the" } }
YAS_DECISION = { tier = "AUTO" }

-- Mid-word: '.' inserted inside "hello" must not commit the "hel" fragment.
box = MockEditBox("g1")
box:SetText("hel.lo")
box:SetCursorPosition(4)
Autocorrect:OnBoundaryCommit(box, "hel.lo", 4)
check("mid-word boundary does not commit", box:GetText() == "hel.lo")

-- Slash commands are never corrected.
box = MockEditBox("g2")
box:SetText("/teh ")
box:SetCursorPosition(5)
Autocorrect:OnBoundaryCommit(box, "/teh ", 5)
check("slash command skipped", box:GetText() == "/teh ")

-- Already-correct words are skipped.
resetState()
GOOD_WORDS["the"] = true
SUGGESTIONS  = { { kind = "word", value = "the" } }
YAS_DECISION = { tier = "AUTO" }
box = MockEditBox("g3")
box:SetText("the ")
box:SetCursorPosition(4)
Autocorrect:OnBoundaryCommit(box, "the ", 4)
check("correct word skipped", #Autocorrect._corrections == 0)

-- Ignored words are skipped (user intent).
resetState()
SUGGESTIONS  = { { kind = "word", value = "the" } }
YAS_DECISION = { tier = "AUTO" }
Spellcheck.GetUserSets = function() return nil, { teh = true }, nil end
box = MockEditBox("g4")
box:SetText("teh ")
box:SetCursorPosition(4)
Autocorrect:OnBoundaryCommit(box, "teh ", 4)
check("ignored word skipped", box:GetText() == "teh ")
Spellcheck.GetUserSets = function() return nil, nil, nil end

-- An opening '"' is not a commit boundary.
resetState()
SUGGESTIONS  = { { kind = "word", value = "the" } }
YAS_DECISION = { tier = "AUTO" }
box = MockEditBox("g5")
box:SetText('"')
box:SetCursorPosition(1)
Autocorrect:OnBoundaryCommit(box, '"', 1)
check("opening quote does not commit", box:GetText() == '"')

-- A parity-closing '"' DOES commit the word inside the quote.
box = MockEditBox("g6")
box:SetText('"teh"')
box:SetCursorPosition(5)
Autocorrect:OnBoundaryCommit(box, '"teh"', 5)
check('closing quote commits ("teh" -> "the")', box:GetText() == '"the"')

-- ===========================================================================
-- Test 5: backspace revert (stateless match against the stored post-apply text)
-- ===========================================================================
print("\nTest 5: backspace revert")

resetState()
SUGGESTIONS  = { { kind = "word", value = "the" } }
YAS_DECISION = { tier = "AUTO" }
box = MockEditBox("r1")
box:SetText("teh ")
box:SetCursorPosition(4)
Autocorrect:OnBoundaryCommit(box, "teh ", 4)
check("setup: applied", box:GetText() == "the ")

-- Backspace deletes the boundary space: "the" with caret at 3.
box:SetText("the")
box:SetCursorPosition(3)
local didRevert = Autocorrect:OnUserTextChanged(box, "the", 3)
check("backspace reverts", didRevert == true)
check("text restored", box:GetText() == "teh")
check("caret after restored word", box:GetCursorPosition() == 3)
check("rejection signalled to YAS",
    rejectLog[1] and rejectLog[1].typo == "teh" and rejectLog[1].corr == "the")
check("correction flagged reverted", Autocorrect._corrections[1].reverted == true)

-- Suppression: retyping the same pair must not re-apply this session.
box:SetText("teh ")
box:SetCursorPosition(4)
Autocorrect:OnBoundaryCommit(box, "teh ", 4)
check("reverted pair is suppressed on retype", box:GetText() == "teh ")

-- ...unless the user manually re-corrects it: ClearSuppression (invoked by
-- YAS:RecordSelection on a manual pick) restores the pair's eligibility.
Autocorrect:ClearSuppression("teh", "the")
Autocorrect:OnBoundaryCommit(box, "teh ", 4)
check("manual re-pick lifts suppression", box:GetText() == "the ")
check("suppression entry removed", Autocorrect._suppressed["teh\0the"] == nil)

-- A non-matching edit does not revert.
resetState()
SUGGESTIONS  = { { kind = "word", value = "the" } }
YAS_DECISION = { tier = "AUTO" }
box = MockEditBox("r2")
box:SetText("teh ")
box:SetCursorPosition(4)
Autocorrect:OnBoundaryCommit(box, "teh ", 4)
box:SetText("the c")
box:SetCursorPosition(5)
check("ordinary typing does not revert",
    Autocorrect:OnUserTextChanged(box, "the c", 5) == false
    and Autocorrect._corrections[1].reverted ~= true)

-- A backspace on a different box does not revert.
local other = MockEditBox("other")
other:SetText("the")
other:SetCursorPosition(3)
check("foreign box does not revert",
    Autocorrect:OnUserTextChanged(other, "the", 3) == false)

-- ===========================================================================
-- Test 6: Ctrl+Z detection + toast undo validation
-- ===========================================================================
print("\nTest 6: undo paths")

resetState()
SUGGESTIONS  = { { kind = "word", value = "the" } }
YAS_DECISION = { tier = "AUTO" }
box = MockEditBox("u1")
box:SetText("teh ")
box:SetCursorPosition(4)
Autocorrect:OnBoundaryCommit(box, "teh ", 4)

-- History restores the pre-correction text: prevText = "the " -> "teh ".
Autocorrect:OnUndo(box, "the ", "teh ")
check("undo flags reverted", Autocorrect._corrections[1].reverted == true)
check("undo suppresses pair",
    Autocorrect._suppressed["teh\0the"] == true)
check("undo fires reject", #rejectLog == 1)

-- An unrelated transition flags nothing.
resetState()
SUGGESTIONS  = { { kind = "word", value = "the" } }
YAS_DECISION = { tier = "AUTO" }
box = MockEditBox("u2")
box:SetText("teh ")
box:SetCursorPosition(4)
Autocorrect:OnBoundaryCommit(box, "teh ", 4)
Autocorrect:OnUndo(box, "other text", "older text")
check("unrelated undo ignored", Autocorrect._corrections[1].reverted ~= true)

-- Toast undo: the entry must be the newest pending undo.
resetState()
SUGGESTIONS  = { { kind = "word", value = "the" } }
YAS_DECISION = { tier = "AUTO" }
box = MockEditBox("u3")
box:SetText("teh ")
box:SetCursorPosition(4)
Autocorrect:OnBoundaryCommit(box, "teh ", 4)
local entry = Autocorrect._corrections[1].undoEntry
check("toast undo pops + reverts",
    Autocorrect:UndoByToast(entry) == true and box:GetText() == "teh ")
check("toast undo consumed ring", #undoRing == 0)

-- Stale toast: entry no longer at the top of the ring.
resetState()
SUGGESTIONS  = { { kind = "word", value = "the" } }
YAS_DECISION = { tier = "AUTO" }
box = MockEditBox("u4")
box:SetText("teh ")
box:SetCursorPosition(4)
Autocorrect:OnBoundaryCommit(box, "teh ", 4)
local staleEntry = Autocorrect._corrections[1].undoEntry
undoRing[#undoRing + 1] = { original = "x", applied = "y" } -- newer record
check("stale toast undo refused",
    Autocorrect:UndoByToast(staleEntry) == false
    and Autocorrect._corrections[1].reverted ~= true)

-- ===========================================================================
-- Test 7: correction rings and LiveCorrectionAt
-- ===========================================================================
print("\nTest 7: correction tracking")

resetState()
SUGGESTIONS  = { { kind = "word", value = "the" } }
YAS_DECISION = { tier = "AUTO" }
box = MockEditBox("t1")
box:SetText("teh ")
box:SetCursorPosition(4)
Autocorrect:OnBoundaryCommit(box, "teh ", 4)

check("LiveCorrectionAt finds covering range",
    Autocorrect:LiveCorrectionAt(box, 1, 3) ~= nil)
check("LiveCorrectionAt rejects foreign box",
    Autocorrect:LiveCorrectionAt(MockEditBox("zz"), 1, 3) == nil)
check("LiveCorrectionAt rejects disjoint range",
    Autocorrect:LiveCorrectionAt(box, 10, 12) == nil)
Autocorrect._corrections[1].reverted = true
check("reverted corrections are not live",
    Autocorrect:LiveCorrectionAt(box, 1, 3) == nil)

-- Ring cap: more than CORRECTIONS_CAP corrections evict the oldest.
resetState()
SUGGESTIONS  = { { kind = "word", value = "the" } }
YAS_DECISION = { tier = "AUTO" }
box = MockEditBox("t2")
for i = 1, 25 do
    box:SetText("teh ")
    box:SetCursorPosition(4)
    Autocorrect._suppressed = {} -- allow re-apply
    Autocorrect:OnBoundaryCommit(box, "teh ", 4)
    -- manually clear so the next apply is a fresh correction record
    box:SetText("teh ")
end
check("correction ring is bounded", #Autocorrect._corrections <= 20)

-- ===========================================================================
-- Test 8: two-token structural fixes (stray-space join + missing-space split)
-- ===========================================================================
print("\nTest 8: stray-space join + missing-space split")

-- Merged token splits unambiguously: "whe nthere" -> "when there".
resetState()
GOOD_WORDS = { ["when"] = true, ["there"] = true }
box = MockEditBox("j1")
box:SetText("whe nthere ")
box:SetCursorPosition(11)
Autocorrect:OnBoundaryCommit(box, "whe nthere ", 11)
check("join fixes stray space inside word", box:GetText() == "when there ")
check("caret preserved at boundary", box:GetCursorPosition() == 11)
check("join records two-token original",
    Autocorrect._corrections[1] and Autocorrect._corrections[1].original == "whe nthere")
check("join records applied pair",
    Autocorrect._corrections[1] and Autocorrect._corrections[1].applied == "when there")

-- Merged token is itself a word: "wh en" -> "when".
resetState()
GOOD_WORDS = { ["when"] = true }
box = MockEditBox("j2")
box:SetText("wh en ")
box:SetCursorPosition(6)
Autocorrect:OnBoundaryCommit(box, "wh en ", 6)
check("merged word joins fragments", box:GetText() == "when ")

-- Leading capital on the first fragment mirrors onto the result.
resetState()
GOOD_WORDS = { ["When"] = true } -- mock IsWordCorrect matches raw input
box = MockEditBox("j3")
box:SetText("Wh en ")
box:SetCursorPosition(6)
Autocorrect:OnBoundaryCommit(box, "Wh en ", 6)
check("capital mirrors onto join", box:GetText() == "When ")

-- A correct previous word blocks the join: "the xw" is not "the" + stray.
resetState()
GOOD_WORDS = { ["the"] = true }
box = MockEditBox("j4")
box:SetText("the xw ")
box:SetCursorPosition(7)
Autocorrect:OnBoundaryCommit(box, "the xw ", 7)
check("correct prev fragment blocks join", box:GetText() == "the xw ")

-- Punctuation between fragments is not a stray space.
resetState()
GOOD_WORDS = { ["when"] = true, ["there"] = true }
box = MockEditBox("j5")
box:SetText("whe,nthere ")
box:SetCursorPosition(11)
Autocorrect:OnBoundaryCommit(box, "whe,nthere ", 11)
check("punctuation gap blocks join", box:GetText() == "whe,nthere ")

-- Ambiguous merged split ("carpen" -> car|pen or carp|en): leave it alone.
resetState()
GOOD_WORDS = { ["car"] = true, ["pen"] = true, ["carp"] = true, ["en"] = true }
box = MockEditBox("j6")
box:SetText("ca rpen ")
box:SetCursorPosition(8)
Autocorrect:OnBoundaryCommit(box, "ca rpen ", 8)
check("ambiguous merged split leaves text", box:GetText() == "ca rpen ")

-- INTENTIONAL intent on a fragment vetoes the join.
resetState()
GOOD_WORDS = { ["when"] = true }
YAS_INTENTS = { ["en"] = "INTENTIONAL" }
box = MockEditBox("j7")
box:SetText("wh en ")
box:SetCursorPosition(6)
Autocorrect:OnBoundaryCommit(box, "wh en ", 6)
check("intent veto blocks join", box:GetText() == "wh en ")

-- A suppressed join pair does not re-apply.
resetState()
GOOD_WORDS = { ["when"] = true, ["there"] = true }
Autocorrect._suppressed[
    Spellcheck.NormaliseWord("whe nthere") .. "\0"
    .. Spellcheck.NormaliseWord("when there")] = true
box = MockEditBox("j8")
box:SetText("whe nthere ")
box:SetCursorPosition(11)
Autocorrect:OnBoundaryCommit(box, "whe nthere ", 11)
check("suppressed join does not re-apply", box:GetText() == "whe nthere ")

-- Unambiguous kind=split suggestion applies (run-together word).
resetState()
SUGGESTIONS = { { kind = "split", value = "hello world" } }
box = MockEditBox("s1")
box:SetText("helloworld ")
box:SetCursorPosition(11)
Autocorrect:OnBoundaryCommit(box, "helloworld ", 11)
check("unambiguous split applies", box:GetText() == "hello world ")

-- Two split candidates are ambiguous: falls through to word eval.
resetState()
SUGGESTIONS = {
    { kind = "split", value = "hello world" },
    { kind = "split", value = "hell ow orld" },
}
box = MockEditBox("s2")
box:SetText("helloworld ")
box:SetCursorPosition(11)
Autocorrect:OnBoundaryCommit(box, "helloworld ", 11)
check("ambiguous splits do not apply", box:GetText() == "helloworld ")

-- ===========================================================================
-- Test 9: space-fix certainty gate (YAS disagreement demands pair support)
-- ===========================================================================
print("\nTest 9: space-fix certainty gate")

local function SpaceKey(orig, cand) -- mirrors Autocorrect's C() key hygiene
    return Spellcheck.NormaliseWord(orig):gsub("[%p%c%s]", "")
        .. ":" .. Spellcheck.NormaliseWord(cand):gsub("[%p%c%s]", "")
end

-- Learned vocabulary vetoes the structural fix: "bobbysue" is a word the
-- user actually sends (freq > 2), so splitting it needs pair support.
resetState()
GOOD_WORDS  = { ["bobby"] = true, ["sue"] = true }
SUGGESTIONS = { { kind = "split", value = "bobby sue" } }
YAS_DB      = { freq = { ["bobbysue"] = { c = 4 } }, bias = {}, negBias = {} }
box = MockEditBox("g1")
box:SetText("bobbysue ")
box:SetCursorPosition(9)
Autocorrect:OnBoundaryCommit(box, "bobbysue ", 9)
check("learned token blocks split", box:GetText() == "bobbysue ")

-- Same token, but the user has manually made this correction before.
resetState()
GOOD_WORDS  = { ["bobby"] = true, ["sue"] = true }
SUGGESTIONS = { { kind = "split", value = "bobby sue" } }
YAS_DB      = {
    freq = { ["bobbysue"] = { c = 4 } },
    bias = { [SpaceKey("bobbysue", "bobby sue")] = { c = 1 } },
    negBias = {},
}
box = MockEditBox("g2")
box:SetText("bobbysue ")
box:SetCursorPosition(9)
Autocorrect:OnBoundaryCommit(box, "bobbysue ", 9)
check("learned pair overrides disagreement", box:GetText() == "bobby sue ")

-- ACCIDENT intent on a source fragment also satisfies the support demand.
resetState()
GOOD_WORDS  = { ["when"] = true }
YAS_DB      = { freq = { ["en"] = { c = 5 } }, bias = {}, negBias = {} }
YAS_INTENTS = { ["en"] = "ACCIDENT" }
box = MockEditBox("g3")
box:SetText("wh en ")
box:SetCursorPosition(6)
Autocorrect:OnBoundaryCommit(box, "wh en ", 6)
check("ACCIDENT intent overrides disagreement", box:GetText() == "when ")

-- A previously reverted pair (negBias) refuses to re-fire next session.
resetState()
GOOD_WORDS  = { ["when"] = true }
YAS_DB      = { freq = {}, bias = {},
    negBias = { [SpaceKey("wh en", "when")] = { c = 1, t = 1 } } }
box = MockEditBox("g4")
box:SetText("wh en ")
box:SetCursorPosition(6)
Autocorrect:OnBoundaryCommit(box, "wh en ", 6)
check("negBias pair refuses re-fire", box:GetText() == "wh en ")

-- Weak learned presence (freq <= 2) does not count as disagreement.
resetState()
GOOD_WORDS  = { ["when"] = true }
YAS_DB      = { freq = { ["en"] = { c = 2 } }, bias = {}, negBias = {} }
box = MockEditBox("g5")
box:SetText("wh en ")
box:SetCursorPosition(6)
Autocorrect:OnBoundaryCommit(box, "wh en ", 6)
check("weak freq does not block join", box:GetText() == "when ")

-- ===========================================================================
-- Summary
-- ===========================================================================
print(string.format("\n%d tests, %d failures", TESTS, FAILURES))
os.exit(FAILURES == 0 and 0 or 1)
