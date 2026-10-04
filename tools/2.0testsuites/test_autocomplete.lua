#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_autocomplete.lua  --  Autocomplete GetSuggestion cascade tests
-- Run from the repo root:  lua tools/2.0testsuites/test_autocomplete.lua
--
-- Exercises the real Autocomplete:GetSuggestion against a mocked Spellcheck
-- hub: YAS freq tier, user-dict tier, dictionary tier, negBias penalty, and
-- the YAS bigram context bonus (prevWord -> next-word transitions).
-- ---------------------------------------------------------------------------

local PASS, FAIL = 0, 0

local function check(label, cond, extra)
    if cond then
        print("  [PASS] " .. label)
        PASS = PASS + 1
    else
        print("  [FAIL] " .. label .. (extra and ("  <- got " .. tostring(extra)) or ""))
        FAIL = FAIL + 1
    end
end

-- ===========================================================================
-- Mock environment
-- ===========================================================================
_G.C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end }
_G.time    = os.time

local DB  -- the active mock locale partition; tests swap this

local YapperTable = {
    Utils = {
        Deleet     = function(s) return s end,
        DebugPrint = function() end,
        Print      = function() end,
    },
    Config = {
        EditBox    = { AutocompleteEnabled = true },
        Spellcheck = { Enabled = true },
    },
    Spellcheck = {
        GetLocale    = function() return "enUS" end,
        NormaliseWord = function(w) return string.lower(w) end,
        IsWordByte   = function(b)
            return (b >= 65 and b <= 90) or (b >= 97 and b <= 122)
                or b == 39 or b == 45 or (b >= 48 and b <= 57)
        end,
        IsEnabled   = function() return true end,
        Dictionaries = {},
    },
}
local SC = YapperTable.Spellcheck

SC.YAS = {
    GetLocaleDB      = function(_, _, _) return DB end,
    EnsureFreqSorted = function() return DB and DB.freqSorted end,
}

local loader, err = loadfile("Src/Autocomplete.lua")
if not loader then
    io.stderr:write("FATAL: " .. tostring(err) .. "\n")
    os.exit(2)
end
loader("Yapper", YapperTable)
local AC = YapperTable.Autocomplete

-- Recolour supplies CanonicalCursor for the ghost-anchor check in the
-- OnCursorChanged hook. Plain ASCII test text needs no escape stripping.
local reLoader, reErr = loadfile("Src/Spellcheck/Recolour.lua")
assert(reLoader, reErr)
reLoader("Yapper", YapperTable)

-- ===========================================================================
-- 1. Tier 1: YAS personal lexicon
-- ===========================================================================
print("Tier 1: YAS freq")

DB = {
    freq = {
        stormwind  = { c = 10 },
        stormscale = { c = 5 },
        store      = { c = 1 },
    },
    freqSorted = { "stormscale", "stormwind", "store" },
    bigram = {},
}
check("highest-freq match wins", AC:GetSuggestion("sto") == "stormwind",
    AC:GetSuggestion("sto"))

DB.bigram = { quick = { stormscale = { c = 8 } } }
check("bigram context beats raw freq", AC:GetSuggestion("storm", nil, "quick") == "stormscale",
    AC:GetSuggestion("storm", nil, "quick"))
check("no context -> freq order unchanged", AC:GetSuggestion("storm", nil, "never") == "stormwind",
    AC:GetSuggestion("storm", nil, "never"))

-- ===========================================================================
-- 2. Tier 2: dictionary fallback + bigram bonus
-- ===========================================================================
print("\nTier 2: dictionary + bigram")

DB = { freq = {}, freqSorted = {}, bigram = {} }
SC.GetDictionary = function()
    return { words = { "baker", "banana", "bank" } }
end

check("dict fallback returns a match", AC:GetSuggestion("ba") ~= nil)
check("shortest word wins by default", AC:GetSuggestion("ba") == "bank",
    AC:GetSuggestion("ba"))

DB.bigram = { eat = { banana = { c = 6 } } }
check("bigram boosts dict candidate", AC:GetSuggestion("ba", nil, "eat") == "banana",
    AC:GetSuggestion("ba", nil, "eat"))
check("unrelated context falls back to default", AC:GetSuggestion("ba", nil, "xyz") == "bank")

-- Sentence-initial bucket: no prevWord resolves to "<s>".
DB.bigram = { ["<s>"] = { banana = { c = 6 } } }
check("sentence-initial bigram applies", AC:GetSuggestion("ba") == "banana",
    AC:GetSuggestion("ba"))

-- ===========================================================================
-- 2b. Tier 1c: known player names (Src/Names.lua)
-- ===========================================================================
print("\nTier 1c: player names")

DB = { freq = {}, freqSorted = {}, bigram = {} }
YapperTable.Names = {
    FindByPrefix = function(_, p) return p == "vel" and "velkira" or nil end,
}
check("name tier beats dictionary", AC:GetSuggestion("vel") == "velkira",
    AC:GetSuggestion("vel"))
check("name-tier miss falls through to dict", AC:GetSuggestion("ba") == "bank",
    AC:GetSuggestion("ba"))
check("capital mirrors onto name", AC:GetSuggestion("Vel") == "Velkira",
    AC:GetSuggestion("Vel"))

DB = { freq = { velasquez = { c = 1 } }, freqSorted = { "velasquez" }, bigram = {} }
check("YAS freq outranks name tier", AC:GetSuggestion("vel") == "velasquez",
    AC:GetSuggestion("vel"))
YapperTable.Names = nil

-- ===========================================================================
-- 3. negBias penalty + capitalisation mirror
-- ===========================================================================
print("\nnegBias + casing")

DB = {
    freq = {}, freqSorted = {}, bigram = {},
    negBias = { ["ba:bank"] = { c = 4 } },  -- 4 dismissals: -12
}
check("dismissed dict word sinks", AC:GetSuggestion("ba") == "baker",
    AC:GetSuggestion("ba"))

DB.negBias = { ["ba:banana"] = { c = 100 } } -- capped penalty still applies
check("capital mirrors onto suggestion", AC:GetSuggestion("Ba") == "Bank",
    AC:GetSuggestion("Ba"))

-- ===========================================================================
-- 4. No YAS / edge cases
-- ===========================================================================
print("\nEdge cases")

DB = nil
SC.YAS.GetLocaleDB = function() return nil end
check("no YAS db -> dict only", AC:GetSuggestion("ba") == "bank",
    AC:GetSuggestion("ba"))

check("prefix below MIN_PREFIX_LEN -> nil", AC:GetSuggestion("b") == nil)
check("no match -> nil", AC:GetSuggestion("zzz") == nil)

-- _base fallback
SC.GetDictionary = function()
    return { words = { "apple" }, extends = "enBASE" }
end
SC.Dictionaries = { enBASE = { words = { "baseline", "basic" } } }
check("base dict fallback", AC:GetSuggestion("bas") == "basic"
    or AC:GetSuggestion("bas") == "baseline", AC:GetSuggestion("bas"))

-- ===========================================================================
-- 5. Ghost anchor: caret move off the anchor invalidates the ghost
-- ===========================================================================
print("\nGhost anchor (OnCursorChanged)")

-- Fake FontString: enough surface for HideGhost / PositionGhost.
local fs = { _shown = false, _text = "" }
function fs:SetText(t)     self._text = t end
function fs:Show()         self._shown = true end
function fs:Hide()         self._shown = false end
function fs:ClearAllPoints() end
function fs:SetPoint()     end
function fs:SetParent()    end
function fs:SetFontObject() end

-- Fake EditBox with script storage and a movable caret.
local box = { _text = "hello world", _cursor = 9, _scripts = {} }
function box:GetText()            return self._text end
function box:GetCursorPosition()  return self._cursor end
function box:GetScript(n)         return self._scripts[n] end
function box:SetScript(n, fn)     self._scripts[n] = fn end
function box:GetEffectiveScale()  return 1 end

_G.UIParent = { GetEffectiveScale = function() return 1 end }

AC:_InstallCursorHook(box)
local onCursor = box._scripts.OnCursorChanged
check("cursor hook installed", type(onCursor) == "function")

-- Ghost anchored at canonical caret pos 9 ("hello wor|ld").
AC.Active        = true
AC.CurrentSugg   = "world"
AC.CurrentPrefix = "wor"
AC.PrefixText    = "hello wor"
AC.GhostFS       = fs
fs._shown        = true

onCursor(box, 10, 0, 0, 10)
check("caret on anchor keeps ghost", AC.Active == true and fs._shown == true)

-- Arrow-key into the middle of the committed word.
box._cursor = 5
onCursor(box, 10, 0, 0, 10)
check("caret off anchor hides ghost", AC.Active == false and fs._shown == false)

-- ===========================================================================
print(string.format("\n%s\nResults: %d/%d passed",
    string.rep("=", 50), PASS, PASS + FAIL))
if FAIL > 0 then os.exit(1) end
print("All tests passed.")
