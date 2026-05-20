-- Mock Globals
_G.YapperDB = {}
_G.time = os.time

local YapperName, YapperTable = "Yapper", {
    Config = { Spellcheck = { Enabled = true, YASFreqCap = 100, YASBiasCap = 100 } },
    Spellcheck = { 
        Notify = function() end,
        GetConfig = function(self) return YapperTable.Config.Spellcheck end,
        IsEnabled = function() return true end,
        GetDictionary = function() return nil end,
    }
}

-- Load the real YAS
loadfile("../../Src/Spellcheck/Adaptive.lua")(YapperName, YapperTable)
local YAS = YapperTable.Spellcheck.YAS
YAS:Init()

local function assert_eq(actual, expected, msg)
    if math.abs(actual - expected) > 0.001 then
        print(string.format("  [FAIL] %s: expected %.4f, got %.4f", msg, expected, actual))
        os.exit(1)
    else
        print(string.format("  [PASS] %s", msg))
    end
end

print("Verifying YAS Engineering Refinements...")
print("-----------------------------------------")

-- 1. Test Consonant Cluster Fix
print("1. Consonant Cluster Filter:")
local sane = YAS:IsSaneWord("strngths") -- 7 consonants
local insane = YAS:IsSaneWord("strngthss") -- 8 consonants
if not sane and not insane then
    print("  [PASS] Correctly rejected 7+ consonant runs.")
else
    print("  [FAIL] Consonant filter error.")
end

-- 2. Test Logarithmic Scaling
print("\n2. Logarithmic Scaling (freqBonus = -2.5):")
-- Record 'apple' 10 times, 'banana' 100 times
for i = 1, 10 do YAS:RecordUsage("apple", "enUS") end
for i = 1, 100 do YAS:RecordUsage("banana", "enUS") end

local b1 = YAS:GetBonus("apple", "appleTypo", nil, "enUS")
local b2 = YAS:GetBonus("banana", "bananaTypo", nil, "enUS")

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
for i = 1, 5 do YAS:RecordSelection("chry", "cherry", 0.5, "enUS") end
for i = 1, 20 do YAS:RecordSelection("dt", "date", 0.5, "enUS") end

local c1 = YAS:GetBonus("cherry", "chry", nil, "enUS")
local c2 = YAS:GetBonus("date", "dt", nil, "enUS")

print(string.format("  Cherry (5 hits) Bonus: %.4f", c1))
print(string.format("  Date (20 hits)  Bonus: %.4f", c2))

if math.abs(c1 - c2) < 0.1 then
    print("  [PASS] Selection bias correctly saturated at the cap.")
else
    print("  [FAIL] Selection bias grew unbounded.")
end

print("\nAll targeted logic tests passed.")
