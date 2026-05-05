-- Mock Globals
_G.YapperDB = {}
_G.time = os.time

local YapperName, YapperTable = "Yapper", {
    Config = { 
        Spellcheck = { 
            Enabled = true, 
            YALLMFreqCap = 5, 
            YALLMBiasCap = 100,
            YALLMAutoThreshold = 3
        },
        System = { DEBUG = false }
    },
    Spellcheck = { 
        GetLocale = function() return "enUS" end,
        GetDictionary = function() return nil end, -- No ngram check for basic tests
    }
}

-- Load the real YALLM
loadfile("Src/Spellcheck/YALLM.lua")(YapperName, YapperTable)
local YALLM = YapperTable.Spellcheck.YALLM
YALLM:Init()

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

print("Verifying YALLM Refactor & New Logic...")
print("---------------------------------------")

-- 1. IsSaneWord Invariants (Pre-cleaned expectations)
print("1. IsSaneWord (Pre-cleaned):")
assert_bool(YALLM:IsSaneWord("apple"), true, "Valid word accepted")
assert_bool(YALLM:IsSaneWord("a"), false, "Too short rejected")
assert_bool(YALLM:IsSaneWord("thisiswaytoolongtobeactuallyconsideredasanehumanword"), false, "Too long rejected")
assert_bool(YALLM:IsSaneWord("strngthss"), false, "Consonant cluster rejected")
assert_bool(YALLM:IsSaneWord("aaab"), false, "Keyboard smash rejected")

-- 2. RecordUsage Logic (Standard)
print("\n2. RecordUsage (Standard):")
YALLM:RecordUsage("The quick brown fox", "enUS")
local db = YALLM:GetLocaleDB("enUS")
assert_eq(db.freq["quick"] ~= nil, true, "Recorded standard word")
assert_eq(db.freq["the"] ~= nil, true, "Recorded lowercase word")

-- 3. Slash Command Skipping
print("\n3. Slash Command Skipping:")
YALLM:Reset("enUS")
YALLM:RecordUsage("/dance happily", "enUS")
db = YALLM:GetLocaleDB("enUS")
assert_eq(db.freq["dance"], nil, "Ignored first word of slash command (/dance)")
assert_eq(db.freq["happily"] ~= nil, true, "Recorded subsequent words in slash command")

YALLM:Reset("enUS")
YALLM:RecordUsage("   /dance happily", "enUS")
db = YALLM:GetLocaleDB("enUS")
assert_eq(db.freq["dance"], nil, "Ignored first word with leading spaces")

-- 4. Learning Pruning (Capacity)
print("\n4. Capacity Pruning (Cap=100):")
YapperTable.Config.Spellcheck.YALLMFreqCap = 100
YALLM:Reset("enUS")
for i = 1, 100 do
    YALLM:RecordUsage("word" .. i, "enUS")
end
db = YALLM:GetLocaleDB("enUS")
assert_eq(db.total, 100, "Reached capacity")

YALLM:RecordUsage("extra", "enUS")
print("  Total after 'extra':", db.total)
assert_eq(db.total <= 100, true, "Stayed at or below capacity (pruned)")
assert_eq(db.freq["extra"] ~= nil, true, "Newly added word exists")

-- 5. RecordIgnored (Auto-Learn Path)
print("\n5. RecordIgnored (Manual Word Typing):")
YALLM:Reset("enUS")
local learned = false
YapperTable.Spellcheck.AddUserWord = function(self, loc, word)
    if word == "SpecialWord" then learned = true end
end

YALLM:RecordIgnored("SpecialWord", "enUS")
YALLM:RecordIgnored("SpecialWord", "enUS")
assert_bool(learned, false, "Not learned yet (Threshold=3)")
YALLM:RecordIgnored("SpecialWord", "enUS")
assert_bool(learned, true, "Learned after 3 ignores")

print("\nAll YALLM extended tests passed successfully.")
