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
print(string.format("\n%s\nResults: %d/%d passed",
    string.rep("=", 50), PASS, PASS + FAIL))
if FAIL > 0 then os.exit(1) end
print("All tests passed.")
