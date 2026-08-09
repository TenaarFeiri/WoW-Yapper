#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_recolour.lua  --  Recolour module unit tests
-- Run from the repo root:  lua tools/2.0testsuites/test_recolour.lua
--
-- Covers the pure translation layer (canonical <-> display) and the
-- Apply/Clear engine behaviour with a mocked editbox + spellcheck hub.
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

_G.print = print

local YapperName = "Yapper"
local YapperTable = {
    Config = {
        System = { DEBUG = false, VERBOSE = false },
        Spellcheck = {},
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
-- Silence prints from the real Utils.
YapperTable.Utils.Print = function() end

loadModule("Src/Spellcheck/Recolour.lua")

local Recolour = YapperTable.Recolour

-- ===========================================================================
-- EditBox mock
-- ===========================================================================

local function makeBox(text, cursor)
    local b = { _text = text or "", _cursor = cursor or 0, _setTextCalls = 0 }
    function b:GetText() return self._text end
    function b:SetText(t) self._text = t; self._setTextCalls = self._setTextCalls + 1 end
    function b:GetCursorPosition() return self._cursor end
    function b:SetCursorPosition(p) self._cursor = p end
    return b
end

-- ===========================================================================
-- Test 1: ColourPrefix
-- ===========================================================================
print("\nTest 1: ColourPrefix")

check("pure red", Recolour.ColourPrefix({ r = 1, g = 0, b = 0 }) == "|cffff0000")
check("default-ish red", Recolour.ColourPrefix({ r = 1.0, g = 0.2, b = 0.2 }) == "|cffff3333")
check("zero", Recolour.ColourPrefix({ r = 0, g = 0, b = 0 }) == "|cff000000")
check("clamps above 1", Recolour.ColourPrefix({ r = 2, g = 1, b = 1 }) == "|cffffffff")
check("clamps below 0", Recolour.ColourPrefix({ r = -1, g = 0, b = 0 }) == "|cff000000")
check("missing components default to 0", Recolour.ColourPrefix({}) == "|cff000000")

-- ===========================================================================
-- Test 2: BuildDisplayText
-- ===========================================================================
print("\nTest 2: BuildDisplayText")

local P = "|cff111111"

check("no spans returns canonical",
    Recolour.BuildDisplayText("hello world", {}, P) == "hello world")
check("nil spans returns canonical",
    Recolour.BuildDisplayText("hello world", nil, P) == "hello world")
check("non-string returns empty",
    Recolour.BuildDisplayText(nil, { { startPos = 1, endPos = 1 } }, P) == "")
check("single middle span",
    Recolour.BuildDisplayText("foo bar baz", { { startPos = 5, endPos = 7 } }, P)
        == "foo |cff111111bar|r baz")
check("span at start",
    Recolour.BuildDisplayText("bar baz", { { startPos = 1, endPos = 3 } }, P)
        == "|cff111111bar|r baz")
check("span at end",
    Recolour.BuildDisplayText("foo bar", { { startPos = 5, endPos = 7 } }, P)
        == "foo |cff111111bar|r")
check("adjacent spans",
    Recolour.BuildDisplayText("a b", { { startPos = 1, endPos = 1 }, { startPos = 3, endPos = 3 } }, P)
        == "|cff111111a|r |cff111111b|r")
check("overlapping second span skipped",
    Recolour.BuildDisplayText("abcdef", { { startPos = 1, endPos = 3 }, { startPos = 2, endPos = 5 } }, P)
        == "|cff111111abc|rdef")
check("out-of-range span skipped",
    Recolour.BuildDisplayText("abc", { { startPos = 5, endPos = 9 } }, P) == "abc")
check("whole text one span",
    Recolour.BuildDisplayText("abc", { { startPos = 1, endPos = 3 } }, P) == "|cff111111abc|r")

-- ===========================================================================
-- Test 3: ToDisplayCursor
-- ===========================================================================
print("\nTest 3: ToDisplayCursor")

local span = { { startPos = 5, endPos = 7 } } -- "bar" in "foo bar baz"

check("no spans identity", Recolour.ToDisplayCursor(6, nil) == 6)
check("caret at 0 stays 0", Recolour.ToDisplayCursor(0, span) == 0)
check("caret before span unchanged", Recolour.ToDisplayCursor(4, span) == 4)
check("caret at span start stays outside", Recolour.ToDisplayCursor(4, span) == 4)
check("caret after first byte of span gains opening", Recolour.ToDisplayCursor(5, span) == 15)
check("caret at span end stays inside colour run", Recolour.ToDisplayCursor(7, span) == 17)
check("caret past span gains opening and closing", Recolour.ToDisplayCursor(8, span) == 20)
check("caret at end of text", Recolour.ToDisplayCursor(11, span) == 23)

local two = { { startPos = 1, endPos = 1 }, { startPos = 3, endPos = 3 } } -- "a b"
check("two spans: caret between them", Recolour.ToDisplayCursor(2, two) == 14)
-- c == endPos of the trailing span: caret stays inside the colour run so a
-- typed character extends the coloured word until the next pass.
check("two spans: caret at end stays inside trailing span", Recolour.ToDisplayCursor(3, two) == 25)

-- ===========================================================================
-- Test 4: CanonicalCursorFromText
-- ===========================================================================
print("\nTest 4: CanonicalCursorFromText")

local disp = "|cffff0000hello|r" -- 10 escape + 5 word + 2 reset = 17 bytes

check("plain text identity", Recolour.CanonicalCursorFromText("hello", 3) == 3)
check("zero stays zero", Recolour.CanonicalCursorFromText(disp, 0) == 0)
check("inside opening escape clamps to 0", Recolour.CanonicalCursorFromText(disp, 5) == 0)
check("after opening escape", Recolour.CanonicalCursorFromText(disp, 12) == 2)
check("at word end (before reset)", Recolour.CanonicalCursorFromText(disp, 15) == 5)
check("past reset counts word only", Recolour.CanonicalCursorFromText(disp, 17) == 5)
check("hyperlink bytes count (preserved)",
    Recolour.CanonicalCursorFromText("|Hitem:1|h[L]|h", 9) == 9)
check("texture escape skipped", Recolour.CanonicalCursorFromText("a|Tx|tb", 6) == 1)
check("atlas escape skipped", Recolour.CanonicalCursorFromText("a|Ax|ab", 6) == 1)
check("named colour skipped", Recolour.CanonicalCursorFromText("|cnRED:hi|r", 7) == 0)
local itemLink = "|cffa335ee|Hitem:1234|h[Shiny Sword]|h|r"
check("quality-coloured item link remains canonical",
    YapperTable.Utils:StripDisplayEscapes(itemLink) == itemLink)
local itemLinkBox = makeBox(itemLink, #itemLink)
check("Recolour canonical text retains item link wrapper",
    Recolour.CanonicalText(itemLinkBox) == itemLink)
check("quality-coloured item link cursor bytes count",
    Recolour.CanonicalCursorFromText(itemLink, #itemLink) == #itemLink)
local namedItemLink = "|cnIQ4:|Hitem:1234|h[Coiled Serpent Idol]|h|r"
local namedRanges = YapperTable.Spellcheck:GetIgnoredRanges(namedItemLink)
check("named-colour item link is one ignored range",
    namedRanges[1] and namedRanges[1].startPos == 1
        and namedRanges[1].endPos == #namedItemLink)
check("named-colour marker cannot be recoloured",
    YapperTable.Spellcheck:IsRangeIgnored(2, 6, namedRanges))
check("nil text gives 0", Recolour.CanonicalCursorFromText(nil, 5) == 0)

-- ===========================================================================
-- Test 5: canonical round-trip through a box
-- ===========================================================================
print("\nTest 5: canonical round-trip")

local canonical = "I mispelled a wurd here"
local spans = { { startPos = 3, endPos = 11 }, { startPos = 15, endPos = 18 } }
local display = Recolour.BuildDisplayText(canonical, spans, P)
local box = makeBox(display, 0)

check("CanonicalText strips injected escapes", Recolour.CanonicalText(box) == canonical)

-- Place display caret inside the second span and check canonical position.
-- "|cff111111" (10) + "I mispelled a " (14) + "|r" (2) ... compute via builder.
-- Easier: caret at end of display text must equal canonical length.
box:SetCursorPosition(#display)
check("end-of-display maps to end-of-canonical",
    Recolour.CanonicalCursor(box) == #canonical)

-- And the inverse: canonical end must map to display end.
check("ToDisplayCursor inverts at end",
    Recolour.ToDisplayCursor(#canonical, spans) == #display)

-- Full round-trip property for every canonical caret position.
local roundTripOk = true
for c = 0, #canonical do
    local d = Recolour.ToDisplayCursor(c, spans)
    local back = Recolour.CanonicalCursorFromText(display, d)
    if back ~= c then
        roundTripOk = false
        print("    round-trip broke at canonical " .. c .. " -> display " .. d .. " -> " .. back)
    end
end
check("canonical->display->canonical round-trips for all positions", roundTripOk)

-- CanonicalTextAndCursor combined helper.
box:SetCursorPosition(#display)
local ct, cc = Recolour.CanonicalTextAndCursor(box)
check("CanonicalTextAndCursor text", ct == canonical)
check("CanonicalTextAndCursor cursor", cc == #canonical)

-- ===========================================================================
-- Test 6: ResolveColour (passthrough seam)
-- ===========================================================================
print("\nTest 6: ResolveColour")

YapperTable.Spellcheck = {
    GetMisspellingColour = function() return { r = 0, g = 1, b = 0 } end,
}
local c = Recolour.ResolveColour(nil)
check("returns configured colour", c.r == 0 and c.g == 1 and c.b == 0)

YapperTable.Spellcheck = {}
c = Recolour.ResolveColour(nil)
check("falls back to default magenta", c.r == 1.0 and c.g == 0.0 and c.b == 1.0)

-- ===========================================================================
-- Test 7: Apply / Clear engine behaviour
-- ===========================================================================
print("\nTest 7: Apply / Clear")

local detected = { { startPos = 3, endPos = 11 } }
_G.YapperAPI = {
    FindMisspellings = function(_, text)
        if text == canonical then return detected end
        return nil
    end,
}
YapperTable.Spellcheck = {
    IsEnabled = function() return true end,
    GetDictionary = function() return {} end,
    GetMisspellingColour = function() return { r = 1, g = 0.2, b = 0.2 } end, -- |cffff3333
    IsWordByte = function(b)
        return (b >= 65 and b <= 90) or (b >= 97 and b <= 122)
    end,
}

local eb = makeBox(canonical, #canonical)
Recolour:Apply(eb)
check("Apply injects escapes", eb:GetText() == "I |cffff3333mispelled|r a wurd here")
check("Apply preserves caret at end", eb:GetCursorPosition() == #("I |cffff3333mispelled|r a wurd here"))

local callsAfterFirst = eb._setTextCalls
Recolour:Apply(eb)
check("second Apply with unchanged text does not SetText (diff loop-breaker)",
    eb._setTextCalls == callsAfterFirst)

-- Caret inside the coloured word is translated, not clamped away.
local eb2 = makeBox(canonical, 5) -- inside "mispelled"
Recolour:Apply(eb2)
check("caret inside span lands inside colour run",
    eb2:GetCursorPosition() == Recolour.ToDisplayCursor(5, detected))

-- User edits the word to a correct spelling: next Apply unwraps.
local fixed = "I spelled a wurd here"
_G.YapperAPI.FindMisspellings = function(_, text)
    if text == fixed then return { { startPos = 13, endPos = 16 } } end -- "wurd"
    return nil
end
local eb3 = makeBox(fixed, 2)
Recolour:Apply(eb3)
check("changed text recolours the new misspelling",
    eb3:GetText() == "I spelled a |cffff3333wurd|r here")

-- Clear strips escapes and restores canonical caret.
Recolour:Clear(eb3)
check("Clear restores canonical text", eb3:GetText() == fixed)

local eb4 = makeBox("I |cffff3333mispelled|r a wurd here", 12)
Recolour:Clear(eb4)
check("Clear restores canonical caret", eb4:GetCursorPosition() == 2)
check("Clear strips escapes", eb4:GetText() == canonical)

-- Apply is a no-op when spellcheck is disabled.
YapperTable.Spellcheck.IsEnabled = function() return false end
local eb5 = makeBox(canonical, 0)
Recolour:Apply(eb5)
check("Apply no-ops when disabled", eb5:GetText() == canonical)
YapperTable.Spellcheck.IsEnabled = function() return true end

-- Apply is a no-op on empty text.
local eb6 = makeBox("", 0)
Recolour:Apply(eb6)
check("Apply no-ops on empty text", eb6:GetText() == "")

-- Invalidate forces a rescan despite unchanged text.
local eb7 = makeBox(canonical, 0)
Recolour:Apply(eb7)
_G.YapperAPI.FindMisspellings = function() return nil end -- dictionary "learned" the words
Recolour:Invalidate()
Recolour:Apply(eb7)
check("Invalidate forces rescan (unwraps learned words)", eb7:GetText() == canonical)

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
