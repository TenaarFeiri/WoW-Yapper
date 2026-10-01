-- Mock Globals
_G.YapperDB = {}
_G.time = os.time

local YapperName, YapperTable = "Yapper", {
    Utils = {
        EnsureTable = function(_, t) return type(t) == "table" and t or {} end,
        Print = function() end,
        VerbosePrint = function() end,
        DebugPrint = function() end,
    },
    Config = { Spellcheck = { Enabled = true, YASFreqCap = 100, YASBiasCap = 100 } },
    Spellcheck = {
        Notify = function() end,
        IsDebugEnabled = function() return false end,
        GetConfig = function(self) return YapperTable.Config.Spellcheck end,
        IsEnabled = function() return true end,
        GetDictionary = function() return nil end,
        GetLocale = function() return "enUS" end,
        Dictionaries = { enUS = {} }, -- YAS:IsEnabled requires a loaded dictionary
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

local failures = 0
local function check(cond, msg)
    if cond then
        print("  [PASS] " .. msg)
    else
        print("  [FAIL] " .. msg)
        failures = failures + 1
    end
end

print("Verifying YAS Engineering Refinements...")
print("-----------------------------------------")

-- 1. Test Consonant Cluster Fix
print("1. Consonant Cluster Filter:")
local sane = YAS:IsSaneWord("strngths") -- 7 consonants
local insane = YAS:IsSaneWord("strngthss") -- 8 consonants
check(not sane and not insane, "Correctly rejected 7+ consonant runs.")

-- 2. Test Logarithmic Scaling
print("\n2. Logarithmic Scaling (freqBonus = -2.5):")
-- Record 'apple' 10 times, 'banana' 100 times
for i = 1, 10 do YAS:RecordUsage("apple", "enUS") end
for i = 1, 100 do YAS:RecordUsage("banana", "enUS") end

local b1 = YAS:GetBonus("apple", "appleTypo", nil, "enUS")
local b2 = YAS:GetBonus("banana", "bananaTypo", nil, "enUS")

print(string.format("  Apple (10 usage)  Bonus: %.4f", b1))
print(string.format("  Banana (100 usage) Bonus: %.4f", b2))

check(b2 < b1, "More frequent word gets a stronger (lower) bonus.")

-- 3. Test Bias Capping
-- Bias bonus saturates at WEIGHTS.biasBonus * min(c,3) * max(u,5.0);
-- count caps at 3, utility caps at 5.0, so both need ~10 selections
-- to saturate before the bonuses converge.
print("\n3. Selection Bias Capping (biasBonus = -5.0):")
for i = 1, 15 do YAS:RecordSelection("chry", "cherry", 0.5, "enUS") end
for i = 1, 25 do YAS:RecordSelection("dt", "date", 0.5, "enUS") end

local c1 = YAS:GetBonus("cherry", "chry", nil, "enUS")
local c2 = YAS:GetBonus("date", "dt", nil, "enUS")

print(string.format("  Cherry (5 hits) Bonus: %.4f", c1))
print(string.format("  Date (20 hits)  Bonus: %.4f", c2))

check(math.abs(c1 - c2) < 0.1, "Selection bias correctly saturated at the cap.")

print("")
if failures > 0 then
    print(failures .. " check(s) FAILED")
    os.exit(1)
end
print("All targeted logic tests passed.")
