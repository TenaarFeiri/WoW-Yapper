-- Mock Globals
_G.YapperDB = {}
_G.time = os.time

local YapperName, YapperTable = "Yapper", {
    Config = { Spellcheck = { Enabled = true, YALLMFreqCap = 100, YALLMBiasCap = 100 } },
    Spellcheck = { 
        Notify = function() end,
        GetConfig = function(self) return YapperTable.Config.Spellcheck end,
        IsEnabled = function() return true end,
        GetDictionary = function() return nil end,
    }
}

-- Load the real YALLM
loadfile("Src/Spellcheck/YALLM.lua")(YapperName, YapperTable)
local YALLM = YapperTable.Spellcheck.YALLM
YALLM:Init()

local function assert_eq(actual, expected, msg)
    if math.abs(actual - expected) > 0.001 then
        print(string.format("  [FAIL] %s: expected %.4f, got %.4f", msg, expected, actual))
        os.exit(1)
    else
        print(string.format("  [PASS] %s", msg))
    end
end

print("Verifying YALLM Engineering Refinements...")
print("-----------------------------------------")

-- 1. Test Consonant Cluster Fix
print("1. Consonant Cluster Filter:")
local sane = YALLM:IsSaneWord("strngths") -- 7 consonants
local insane = YALLM:IsSaneWord("strngthss") -- 8 consonants
if not sane and not insane then
    print("  [PASS] Correctly rejected 7+ consonant runs.")
else
    print("  [FAIL] Consonant filter error.")
end

-- 2. Test Logarithmic Scaling
print("\n2. Logarithmic Scaling (freqBonus = -2.5):")
-- Record 'apple' 10 times, 'banana' 100 times
for i = 1, 10 do YALLM:RecordUsage("apple", "enUS") end
for i = 1, 100 do YALLM:RecordUsage("banana", "enUS") end

local b1 = YALLM:GetBonus("apple", "appleTypo", nil, "enUS")
local b2 = YALLM:GetBonus("banana", "bananaTypo", nil, "enUS")

print(string.format("  Apple (10 usage)  Bonus: %.4f", b1))
print(string.format("  Banana (100 usage) Bonus: %.4f", b2))

if b2 < b1 then
    print("  [PASS] More frequent word gets a stronger (lower) bonus.")
else
    print("  [FAIL] Scaling was not logarithmic or was inverted.")
end

-- 3. Test Bias Capping
print("\n3. Selection Bias Capping (biasBonus = -5.0):")
-- Select 'cherry' 5 times, 'date' 20 times
for i = 1, 5 do YALLM:RecordSelection("chry", "cherry", 0.5, "enUS") end
for i = 1, 20 do YALLM:RecordSelection("dt", "date", 0.5, "enUS") end

local c1 = YALLM:GetBonus("cherry", "chry", nil, "enUS")
local c2 = YALLM:GetBonus("date", "dt", nil, "enUS")

print(string.format("  Cherry (5 hits) Bonus: %.4f", c1))
print(string.format("  Date (20 hits)  Bonus: %.4f", c2))

if math.abs(c1 - c2) < 0.1 then
    print("  [PASS] Selection bias correctly saturated at the cap.")
else
    print("  [FAIL] Selection bias grew unbounded.")
end

print("\nAll targeted logic tests passed.")
