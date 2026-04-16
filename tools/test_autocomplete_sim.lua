#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_autocomplete_sim.lua  —  Autocomplete + Spellcheck logic test harness
-- Run from the repo root:  lua tools/test_autocomplete_sim.lua
--
-- Tests pure-data functions only: no WoW UI API required.
-- Avoids GetSuggestions (expensive scoring engine) and Init (needs UI).
-- ---------------------------------------------------------------------------

-- ===== Minimal WoW stub =====================================================
-- Only the handful of globals the source files reference on *load* or in the
-- pure functions we're exercising.  C_Timer is intentionally a no-op so any
-- accidental scheduling just silently does nothing.
C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end }
time    = os.time
-- WoW's Clamp is a global helper; Spellcheck.lua defines its own local, so
-- we don't need to stub it.

-- ===== Shared YapperTable ===================================================
local YapperTable = {
    Config = {
        EditBox    = { AutocompleteEnabled = true },
        Spellcheck = { Enabled = true, MinWordLength = 3 },
    },
    API = {
        RunFilter = function(self, _, payload) return payload end,
        Fire      = function() end,
    },
    Utils = { DebugPrint = function() end, Print = function() end },
}

-- ===== File loader ==========================================================
local function loadFile(path)
    local f, err = loadfile(path)
    if not f then
        io.stderr:write("FATAL: cannot load " .. path .. ": " .. tostring(err) .. "\n")
        os.exit(2)
    end
    f("__test__", YapperTable)
end

-- Load in dependency order — Spellcheck hub first, then Engine (re-localises
-- helpers from the hub), then Autocomplete.
loadFile("Src/Spellcheck.lua")
loadFile("Src/Spellcheck/Engine.lua")
loadFile("Src/Autocomplete.lua")

local SC   = YapperTable.Spellcheck
local Auto = YapperTable.Autocomplete

-- ===== Test framework =======================================================
local PASS, FAIL = 0, 0

local function check(label, cond, extra)
    if cond then
        io.write("  [PASS] " .. label .. "\n")
        PASS = PASS + 1
    else
        io.write("  [FAIL] " .. label .. (extra and ("  ← " .. extra) or "") .. "\n")
        FAIL = FAIL + 1
    end
end

local function section(name)
    io.write("\n" .. name .. "\n" .. string.rep("-", #name) .. "\n")
end

-- ===== Helpers ==============================================================
-- Restore mocks that tests might mutate
local function mockUserSets()
    SC.GetUserSets = function() return {}, {} end
    SC.GetLocale   = function() return "enUS" end
end

-- ============================================================================
-- 1. NormaliseWord
-- ============================================================================
section("1. Spellcheck: NormaliseWord")

check("lowercase ASCII",     SC.NormaliseWord("Hello")    == "hello")
check("already lower",       SC.NormaliseWord("world")    == "world")
check("mixed case",          SC.NormaliseWord("ElvUI")    == "elvui")
check("empty string",        SC.NormaliseWord("")          == "")
check("non-string → empty",  SC.NormaliseWord(42)          == "")

-- ============================================================================
-- 2. GetPhoneticHash
-- ============================================================================
section("2. Spellcheck: GetPhoneticHash")

-- Walk through the algorithm mentally for each expected value:
--   "Knight" → upper=KNIGHT → strip dupe → KNIGHT → KN→N: NIGHT → GHT→T: NIT
--            → first=N rest=IT → strip vowels(I) → T → "NT"
check("Knight → NT",   SC.GetPhoneticHash("Knight") == "NT")

--   "Phone" → PHONE → PH→F: FONE → first=F rest=ONE → strip vowels(O,E) → N → "FN"
check("Phone → FN",    SC.GetPhoneticHash("Phone")  == "FN")

--   "Write" → WRITE → WR→R: RITE → first=R rest=ITE → strip vowels(I,E) → T → "RT"
check("Write → RT",    SC.GetPhoneticHash("Write")  == "RT")

--   "Enough" → ENOUGH → ends with GH→F: ENOUF → first=E rest=NUF → strip vowels(U) → NF → "ENF"
check("Enough → ENF",  SC.GetPhoneticHash("Enough") == "ENF")

--   "Chat" → CHAT → CH→K: KAT → first=K rest=AT → strip vowels(A) → T → "KT"
check("Chat → KT",     SC.GetPhoneticHash("Chat")   == "KT")

-- ============================================================================
-- 3. ShouldCheckWord
-- ============================================================================
section("3. Spellcheck: ShouldCheckWord")

-- Engine.lua implements ShouldCheckWord; Engine was loaded above.
check("too short (< minLen)",     SC:ShouldCheckWord("OK",        3) == false)
check("contains digit",           SC:ShouldCheckWord("word123",   3) == false)
check("all-caps acronym",         SC:ShouldCheckWord("CAPS",      3) == false)
check("normal word passes",       SC:ShouldCheckWord("hello",     3) == true)
check("Title-case passes",        SC:ShouldCheckWord("Stormwind", 3) == true)
-- edge: exactly minLen letters
check("exactly minLen passes",    SC:ShouldCheckWord("dog",       3) == true)

-- ============================================================================
-- 4. CollectMisspellings
-- ============================================================================
section("4. Spellcheck: CollectMisspellings")
mockUserSets()

local dict4 = { set = { ["hello"] = true, ["world"] = true, ["let"] = true, ["be"] = true } }

local hits4 = SC:CollectMisspellings("Hello wrold, let numbers 123 CAPS be ignord", dict4)
local found = {}
for _, m in ipairs(hits4) do found[m.word] = true end

check("detects 'wrold'",           found["wrold"]   == true)
check("detects 'ignord'",          found["ignord"]  == true)
check("'Hello' not flagged (known after normalise)", found["Hello"]  == nil)
check("digits not flagged",        found["123"]     == nil)
check("all-caps not flagged",      found["CAPS"]    == nil)

-- Empty string returns empty table (no misspellings)
local empty_result = SC:CollectMisspellings("", dict4)
check("empty text → empty table",  type(empty_result) == "table" and #empty_result == 0)

-- ============================================================================
-- 5. IsWordCorrect
-- ============================================================================
section("5. Spellcheck: IsWordCorrect")
mockUserSets()
SC.GetDictionary = function()
    return { set = { ["hello"] = true, ["world"] = true } }
end

check("known word → correct",      SC:IsWordCorrect("hello")    == true)
check("Title-case → correct",      SC:IsWordCorrect("Hello")    == true)   -- normalised
check("unknown word → incorrect",  SC:IsWordCorrect("wrold")    == false)
check("empty string → false",      SC:IsWordCorrect("")         == false)
check("nil → false",               SC:IsWordCorrect(nil)        == false)

-- Word in user added set
SC.GetUserSets = function() return { ["myword"] = true }, {} end
check("user-added word → correct", SC:IsWordCorrect("myword")   == true)

-- Word in ignored set → also "correct" for learning purposes
SC.GetUserSets = function() return {}, { ["sic"] = true } end
check("ignored word → correct",    SC:IsWordCorrect("sic")      == true)

mockUserSets()  -- restore

-- ============================================================================
-- 6. ExtractWordAtCursor
-- ============================================================================
section("6. Autocomplete: ExtractWordAtCursor")

local function extract(text, pos)
    return Auto:ExtractWordAtCursor(text, pos)
end

local w, s = extract("Hello world", 11)
check("last word extracted",       w == "world")
check("start index correct",       s == 7)

local w2, _ = extract("Hello world", 5)
check("mid-word extraction",       w2 == "Hello")

-- Cursor at a space — the word before it
local w3, _ = extract("Hello world", 6)  -- pos 6 = space character
-- pos 6 is a space, so the walk-back should hit the space immediately
-- and return a 0-length token → below MIN_PREFIX_LEN → nil
check("cursor at space → nil",     w3 == nil)

-- Word too short for autocomplete (< MIN_PREFIX_LEN = 2)
local w4, _ = extract("a test", 1)
check("single-char prefix → nil",  w4 == nil)

local w5, _ = extract("", 0)
check("empty text → nil",          w5 == nil)

-- ============================================================================
-- 7. SearchDictionary (binary search)
-- ============================================================================
section("7. Autocomplete: SearchDictionary")

-- The word list MUST be sorted for binary search to work correctly.
local words7 = { "apple", "application", "apply", "banana", "band", "bandwidth", "zulu" }

local r1 = Auto:SearchDictionary(words7, "app")
check("finds shortest 'app*' completion",      r1 == "apple")

local r2 = Auto:SearchDictionary(words7, "band")
check("skips exact-length match 'band'",       r2 == "bandwidth")

local r3 = Auto:SearchDictionary(words7, "xyz")
check("no match → nil",                        r3 == nil)

local r4 = Auto:SearchDictionary({}, "app")
check("empty word list → nil",                 r4 == nil)

local r5 = Auto:SearchDictionary(words7, "application")
-- "application" itself is exact-length match (skipped), "apply" doesn't start with it
check("prefix that is a full word → nil",      r5 == nil)

-- ============================================================================
-- 8. SearchYALLM
-- ============================================================================
section("8. Autocomplete: SearchYALLM")

-- Inject a mock YALLM with frequency data.
SC.YALLM = {
    db = {
        freq = {
            ["Stormwind"]  = { c = 10 },
            ["Stormscale"] = { c = 5  },
            ["Store"]      = { c = 1  },
        }
    }
}

local y1 = Auto:SearchYALLM("sto")
check("highest-freq 'sto*' match",   y1 == "Stormwind")

local y2 = Auto:SearchYALLM("storm")
check("prefix 'storm' → Stormwind",  y2 == "Stormwind")

-- Boost Stormscale above Stormwind
SC.YALLM.db.freq["Stormscale"] = { c = 20 }
local y3 = Auto:SearchYALLM("storm")
check("adapts to frequency change",  y3 == "Stormscale")

local y4 = Auto:SearchYALLM("xyz")
check("no match → nil",              y4 == nil)

-- Entry is a raw number (legacy format), not a table
SC.YALLM.db.freq["numericEntry"] = 7
local y5 = Auto:SearchYALLM("num")
check("numeric freq entry handled",  y5 == "numericEntry")

-- ============================================================================
-- 9. GetSuggestion cascade
-- ============================================================================
section("9. Autocomplete: GetSuggestion cascade")

SC.YALLM = { db = { freq = { ["Stormwind"] = { c = 10 } } } }
SC.GetDictionary = function()
    return {
        words = { "stable", "stall", "star", "stork", "storm", "stormrage" },
        _base = { words = { "baseline", "basic", "basis" } },
    }
end

local g1 = Auto:GetSuggestion("sto")
check("YALLM hit takes priority",         g1 == "Stormwind")

-- Remove the YALLM hit so it falls through to dict
SC.YALLM.db.freq["Stormwind"] = nil
local g2 = Auto:GetSuggestion("sto")
-- binary search on sorted list → first/shortest "sto*" word
check("dict fallback works",              g2 ~= nil and g2:sub(1, 3):lower() == "sto")

-- Test _base fallback
SC.YALLM = nil  -- no YALLM
SC.GetDictionary = function()
    return {
        words = { "apple", "apricot" },  -- no "bas*" words
        _base = { words = { "baseline", "basic", "basis" } },
    }
end
local g3 = Auto:GetSuggestion("bas")
check("_base dict fallback works",        g3 ~= nil and g3:sub(1, 3):lower() == "bas")

-- Too-short prefix
local g4 = Auto:GetSuggestion("s")
check("prefix below MIN_PREFIX_LEN → nil", g4 == nil)

-- ============================================================================
-- Summary
-- ============================================================================
io.write(string.format("\n%s\nResults: %d/%d passed\n",
    string.rep("=", 50), PASS, PASS + FAIL))

if FAIL > 0 then
    io.write(FAIL .. " test(s) failed.\n")
    os.exit(1)
else
    io.write("All tests passed.\n")
end
