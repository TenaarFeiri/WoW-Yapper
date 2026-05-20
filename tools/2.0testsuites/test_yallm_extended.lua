-- Mock Globals
_G.YapperDB = {}
_G.time = os.time

local YapperName, YapperTable = "Yapper", {
    Config = { 
        Spellcheck = { 
            Enabled = true, 
            YASFreqCap = 5, 
            YASBiasCap = 100,
            YASAutoThreshold = 3
        },
        System = { DEBUG = false }
    },
    Spellcheck = {
        IsEnabled = function() return true end,
        GetLocale = function() return "enUS" end,
        GetDictionary = function() return nil end, -- No ngram check for basic tests
    }
}

-- Load the real YAS
loadfile("../../Src/Spellcheck/Adaptive.lua")(YapperName, YapperTable)
local YAS = YapperTable.Spellcheck.YAS
YAS:Init()

local function assert_bool(val, expected, msg)
    if val ~= expected then
        print(string.format("  [FAIL] %s: expected %s, got %s", msg, tostring(expected), tostring(val)))
        os.exit(1)
    else
        print(string.format("  [PASS] %s", msg))
    end
end

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        print(string.format("  [FAIL] %s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
        os.exit(1)
    else
        print(string.format("  [PASS] %s", msg))
    end
end

print("Verifying YAS Refactor & New Logic...")
print("---------------------------------------")

-- 1. IsSaneWord Invariants (Pre-cleaned expectations)
print("1. IsSaneWord (Pre-cleaned):")
assert_bool(YAS:IsSaneWord("apple"), true, "Valid word accepted")
assert_bool(YAS:IsSaneWord("a"), false, "Too short rejected")
assert_bool(YAS:IsSaneWord("thisiswaytoolongtobeactuallyconsideredasanehumanword"), false, "Too long rejected")
assert_bool(YAS:IsSaneWord("strngthss"), false, "Consonant cluster rejected")
assert_bool(YAS:IsSaneWord("aaab"), false, "Keyboard smash rejected")

-- 2. RecordUsage Logic (Standard)
print("\n2. RecordUsage (Standard):")
YAS:RecordUsage("The quick brown fox", "enUS")
local db = YAS:GetLocaleDB("enUS")
assert_eq(db.freq["quick"] ~= nil, true, "Recorded standard word")
assert_eq(db.freq["the"] ~= nil, true, "Recorded lowercase word")

-- 3. Slash Command Skipping
print("\n3. Slash Command Skipping:")
YAS:Reset("enUS")
YAS:RecordUsage("/dance happily", "enUS")
db = YAS:GetLocaleDB("enUS")
assert_eq(db.freq["dance"], nil, "Ignored first word of slash command (/dance)")
assert_eq(db.freq["happily"] ~= nil, true, "Recorded subsequent words in slash command")

YAS:Reset("enUS")
YAS:RecordUsage("   /dance happily", "enUS")
db = YAS:GetLocaleDB("enUS")
assert_eq(db.freq["dance"], nil, "Ignored first word with leading spaces")

-- 4. Learning Pruning (Capacity)
print("\n4. Capacity Pruning (Cap=100):")
YapperTable.Config.Spellcheck.YASFreqCap = 100
YAS:Reset("enUS")
for i = 1, 100 do
    YAS:RecordUsage("word" .. i, "enUS")
end
db = YAS:GetLocaleDB("enUS")
assert_eq(db.total, 100, "Reached capacity")

YAS:RecordUsage("extra", "enUS")
print("  Total after 'extra':", db.total)
assert_eq(db.total <= 100, true, "Stayed at or below capacity (pruned)")
assert_eq(db.freq["extra"] ~= nil, true, "Newly added word exists")

-- 5. RecordIgnored (Auto-Learn Path)
print("\n5. RecordIgnored (Manual Word Typing):")
YAS:Reset("enUS")
local learned = false
YapperTable.Spellcheck.AddUserWord = function(self, loc, word)
    if word == "SpecialWord" then learned = true end
end

YAS:RecordIgnored("SpecialWord", "enUS")
YAS:RecordIgnored("SpecialWord", "enUS")
assert_bool(learned, false, "Not learned yet (Threshold=3)")
YAS:RecordIgnored("SpecialWord", "enUS")
assert_bool(learned, true, "Learned after 3 ignores")

print("\nAll YAS extended tests passed successfully.")
