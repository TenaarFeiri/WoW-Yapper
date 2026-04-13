-- =========================================================================
-- YALLM (Yapper Adaptive Learning Language Model) DIAGNOSTIC
-- =========================================================================

math.randomseed(42)

-- 1. WOW ENVIRONMENT MOCKS
-- =========================================================================
_G = _G or {}
_G.string_sub = string.sub
_G.string_lower = string.lower
_G.string_gsub = string.gsub
_G.string_byte = string.byte

YapperDB = {
    SpellcheckLearned = nil
}
YapperTable = { 
    Config = { Spellcheck = { UseNgramIndex = true } },
    Dictionaries = {},
    Utils = { Print = function(_, msg) print("Yapper: " .. msg) end }
}
LibStub = { libs = {}, NewLibrary = function(s, n) s.libs[n] = s.libs[n] or {} return s.libs[n] end }
GetLocale = function() return "enUS" end
GetTime = function() return os.time() end
C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end }
CreateFrame = function() return { SetScript = function() end, SetPoint = function() end } end

local function load_module(path) assert(loadfile(path))(nil, YapperTable) end

load_module("Src/Spellcheck.lua")
load_module("Src/Spellcheck/Learned.lua")

local Spellcheck = YapperTable.Spellcheck
local YALLM = Spellcheck.Learned
Spellcheck.Dictionaries["enUS"] = { words = {}, index = { ["l"] = { "limbs", "limes" } } }

-- 2. TEST CASE 1: Frequency Learning
-- =========================================================================
print("--- TEST 1: Frequency Bias ---")
YALLM:Init()
-- Simulate typing "limbs" 10 times in chat
for i = 1, 10 do YALLM:RecordUsage("We use limbs to climb things.") end

local bonusLimbs = YALLM:GetBonus("limbs", "lims")
local bonusLimes = YALLM:GetBonus("limes", "lims")

print(string.format("  'limbs' Bonus: %.1f", bonusLimbs))
print(string.format("  'limes' Bonus: %.1f", bonusLimes))
if bonusLimbs < bonusLimes then 
    print("  SUCCESS: 'limbs' is more favored than 'limes'.")
else
    print("  FAILURE: Frequency bias not working.")
end

-- 3. TEST CASE 2: Selection Bias
-- =========================================================================
print("\n--- TEST 2: Selection Bias ---")
-- Simulate user picking 'limes' for 'lims' once
YALLM:RecordSelection("lims", "limes")

local newBonusLimes = YALLM:GetBonus("limes", "lims")
print(string.format("  'limes' New Bonus: %.1f", newBonusLimes))
if newBonusLimes < bonusLimbs then
    print("  SUCCESS: User selection bias overrode frequency.")
else
    print("  FAILURE: Selection bias not applied.")
end

-- 4. TEST CASE 3: Auto-Acceptance
-- =========================================================================
print("\n--- TEST 3: Auto-Acceptance ---")
local persistentWord = "fubarking"
-- Mock AddWord
Spellcheck.AddWord = function(self, w) print("  Spellcheck: Added '" .. w .. "' to dictionary!") end

for i = 1, 10 do
    YALLM:RecordIgnored(persistentWord)
end

if not YapperDB.SpellcheckLearned.auto[persistentWord] then
    print("  SUCCESS: Word promoted and reset from auto-table.")
else
    print("  FAILURE: Word still in auto-table.")
end

print("\nYALLM DIAGNOSTIC COMPLETE.")
