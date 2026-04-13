-- =========================================================================
-- YALLM COLLISION CALIBRATION (Targeted)
-- =========================================================================
-- Measuring how many "Manual Selections" are required to flip rankings.
-- =========================================================================

math.randomseed(42)

-- 1. WOW ENVIRONMENT MOCKS
-- =========================================================================
_G = _G or {}
YapperDB = { SpellcheckLearned = nil }
YapperTable = { 
    Config = { 
        Spellcheck = { 
            Enabled = true, 
            UseNgramIndex = true,
            MinWordLength = 3,
            MaxSuggestions = 6,
            DistanceLimit = 2.5,
        },
        System = { DEBUG = false }
    },
    Dictionaries = {},
    Utils = { Print = function(_, msg) print("Yapper: " .. msg) end }
}

_G.string_sub = string.sub
_G.string_lower = string.lower
_G.string_gsub = string.gsub
_G.string_byte = string.byte
_G.math_abs = math.abs
_G.math_min = math.min
_G.math_max = math.max

LibStub = { libs = {}, NewLibrary = function(s, n) s.libs[n] = s.libs[n] or {} return s.libs[n] end }
GetLocale = function() return "enUS" end
GetTime = function() return os.time() end
C_Timer = { After = function(sec, func) func() end }
CreateFrame = function() return { SetScript = function() end, SetPoint = function() end } end

local function load_module(path) assert(loadfile(path))(nil, YapperTable) end

load_module("Src/Spellcheck.lua")
load_module("Src/Spellcheck/YALLM.lua")

local Spellcheck = YapperTable.Spellcheck
local YALLM = Spellcheck.YALLM

-- Build a Targeted Dictionary Synchronously
local testWords = { "limbs", "limes", "the", "heart", "hear", "than" }
Spellcheck:RegisterDictionary("enUS", {
    words = testWords,
    isPreBuilt = false
})

YALLM:Init()

-- 2. CALIBRATION FUNCTION
-- =========================================================================
local function EvaluateRanking(typo, target)
    local suggestions = Spellcheck:GetSuggestions(typo)
    
    local rank = 99
    local topValue = "None"
    
    for i, s in ipairs(suggestions) do
        if s.kind == "word" then
            if topValue == "None" then topValue = s.value end
            if s.value == target then
                rank = i
                break
            end
        end
    end
    return rank, topValue
end

local function RunTest(name, typo, target)
    print(string.format("\n--- CALIBRATING: %s ('%s' -> '%s') ---", name, typo, target))
    YALLM:Reset()
    
    local rank, top = EvaluateRanking(typo, target)
    print(string.format("  Initial State:  Top is '%s' (Rank of target: %d)", top, rank))

    -- Phase 1: Frequency Training
    print("  Phase 1: Simulating 20 passive usages (Frequency Bonus)...")
    for i = 1, 20 do YALLM:RecordUsage("I am using " .. target) end
    rank, top = EvaluateRanking(typo, target)
    print(string.format("  After Freq:     Top is '%s' (Rank of target: %d)", top, rank))

    -- Phase 2: Selection Training
    if rank ~= 1 then
        print("  Phase 2: Simulating manual selections (Bias Bonus)...")
        for i = 1, 3 do
            YALLM:RecordSelection(typo, target)
            rank, top = EvaluateRanking(typo, target)
            print(string.format("    Selection %d: Top is '%s' (Rank: %d)", i, top, rank))
            if rank == 1 then break end
        end
    else
        print("  SUCCESS: Rank 1 achieved!")
    end
end

-- 3. RUN SCENARIOS
-- =========================================================================
RunTest("Phonetic Collision", "lims", "limbs")
RunTest("Common Misspelling", "hte", "the")
RunTest("Suffix Collision", "hear", "heart")

print("\nCALIBRATION COMPLETE.")
