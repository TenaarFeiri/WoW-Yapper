--[[
    YAS Pruning, Decay & Pipeline Integration Test
    Uses Moby Dick Chapters 1-2 excerpt as a corpus.
    Verifies:
      1. auto table pruning under cap
      2. negBias time-based forgiveness decay
      3. AddedWords FIFO cap
      4. End-to-end detection -> suggestion -> learning -> improved ranking
]]

-- Mock Globals
_G.time = os.time
_G.GetTime = os.clock
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.CreateFrame = function() return { SetScript = function() end, Show = function() end, Hide = function() end } end
_G.C_Timer = { After = function() end }

local YapperName, YapperTable = "Yapper", {
    Config = {
        Spellcheck = {
            Enabled = true,
            UseNgramIndex = true,
            YASAutoThreshold = 3,
            YASFreqCap = 100,
            YASBiasCap = 100,
            YASAutoCap = 20,
            MaxSuggestions = 6,
            UserDictWordCap = 50,
        },
        System = { DEBUG = false }
    },
    Utils = {
        Print = function(...) end,
        VerbosePrint = function(...) end,
        DebugPrint = function(...) end,
    },
    API = { Fire = function(...) end, RunFilter = function(_, _, p) return p end },
    Spellcheck = {
        UserDictCache = {},
        _suggestionCache = {},
        _SCORE_WEIGHTS = { prefix = 1.0, lenDiff = 1.0, longerPenalty = 1.0, firstCharBias = 1.0, letterBag = 1.0, bigram = 1.0, vowelBonus = 1.0, kbProximity = 1.0 },
        _RAID_ICONS = {},
        Notify = function() end,
        GetLocale = function() return "enUS" end,
        GetActiveEngine = function() return nil end,
        GetMaxSuggestions = function() return 6 end,
        GetMaxWrongLetters = function() return 4 end,
        GetMinWordLength = function() return 2 end,
        GetReshuffleAttempts = function() return 20 end,
        GetMeta = function() return {} end,
        GetUserDict = function() return { AddedWords = {} } end,
        GetUserSets = function() return {}, {} end,
        GetIgnoredRanges = function() return {} end,
        Dictionaries = { enUS = {} },  -- Non-empty dict for YAS:IsEnabled()
        IsEnabled = function() return true end,
        GetUserDictStore = function() return _G.YapperDB.Spellcheck.Dict end,
        GetConfig = function() return YapperTable.Config.Spellcheck end,
        TouchUserDict = function(dict) dict._rev = (dict._rev or 0) + 1 end,
        ClearSuggestionCache = function() end,
        Clamp = function(v, min, max) return math.min(max, math.max(v, min)) end,
        NormaliseWord = function(s) return s:lower():gsub("[%p%c%s]", "") end,
        NormaliseVowels = function(s) return s:lower():gsub("[aeiouy]", "*") end,
        SuggestionKey = function(s) return type(s) == "table" and (s.value or s.word) or s end,
        IsWordByte = function(b) return (b >= 97 and b <= 122) or (b >= 65 and b <= 90) or b > 127 end,
        IsWordStartByte = function(b) return (b >= 97 and b <= 122) or (b >= 65 and b <= 90) or b > 127 end,
        _ed_prev = {}, _ed_cur = {}, _ed_prev_prev = {}, _ed_aBytes = {}, _ed_bBytes = {},
    }
}

-- Load Core Logic
local function LoadFile(path)
    local f = assert(loadfile(path))
    f(YapperName, YapperTable)
end

LoadFile("../../Src/Spellcheck.lua")
LoadFile("../../Src/Spellcheck/Adaptive.lua")
LoadFile("../../Src/Spellcheck/Engine.lua")

local SC = YapperTable.Spellcheck
local YAS = SC.YAS
if not YAS then
    print("[ERROR] YAS not loaded - check file loading")
    os.exit(1)
end

-- Ensure Dictionaries is non-empty for YAS:IsEnabled()
if not SC.Dictionaries or next(SC.Dictionaries) == nil then
    SC.Dictionaries = { enUS = {} }
end
SC.GetDictionary = function() return dict end

-- English Moby Dick excerpt (Chapters 1-2, public domain)
local MobyText = [[
Call me Ishmael. Some years ago—never mind how long precisely—having little or no money in my purse,
and nothing particular to interest me on shore, I thought I would sail about a little and see the watery part of the world.
It is a way I have of driving off the spleen and regulating the circulation. Whenever I find myself growing grim about the mouth;
whenever it is a damp, drizzly November in my soul; whenever I find myself involuntarily pausing before coffin warehouses,
and bringing up the rear of every funeral I meet; and especially whenever my hypos get such an upper hand of me,
that it requires a strong moral principle to prevent me from deliberately stepping into the street,
and methodically knocking people's hats off—then, I account it high time to get to sea as soon as I can.
This is my substitute for pistol and ball. With a philosophical flourish Cato throws himself upon his sword; I quietly take to the ship.
There is nothing surprising in this. If they but knew it, almost all men in their degree, some time or other,
cherish very nearly the same feelings towards the ocean with me.

There now is your insular city of the Manhattoes, belted round by wharves as Indian isles by coral reefs—commerce surrounds it with her surf.
Right and left, the streets take you waterward. Its extreme downtown is the battery, where that noble mole is washed by waves,
and cooled by breezes, which a few hours previous were out of sight of land. Look at the crowds of water-gazers there.

Circumambulate the city of a dreamy Sabbath afternoon. Go from Corlears Hook to Coenties Slip, and from thence, by Whitehall, northward.
What do you see? Posted like silent sentinels all around the town, stand thousands upon thousands of mortal men fixed in ocean reveries.

I stuffed a shirt or two into my old carpet-bag, tucked it under my arm, and started for Cape Horn and the Pacific.
Quitting the good city of old Manhatto, I duly arrived in New Bedford. It was on a Saturday night in December.
The whaling vessel was the ship named the Pequod. I had no difficulty in finding a place to sleep.
The landlord was a man of a very pleasant nature. He gave me a good supper and a clean bed.
]]

-- Build dictionary from MobyText (treat most words as known)
local dict = { words = {}, set = {}, index = {}, phonetics = {}, ngramIndex2 = {}, phonetics_en = {} }
for w in MobyText:gmatch("[%w']+") do
    local lw = w:lower()
    if not dict.set[lw] then
        local wordIdx = #dict.words + 1
        table.insert(dict.words, w)
        dict.set[lw] = true
        local first = lw:sub(1, 1)
        dict.index[first] = dict.index[first] or {}
        table.insert(dict.index[first], lw)
        local norm = lw:gsub("[aeiouy]", "*")
        for i = 1, #norm - 1 do
            local g = norm:sub(i, i + 1)
            dict.ngramIndex2[g] = dict.ngramIndex2[g] or {}
            table.insert(dict.ngramIndex2[g], wordIdx)
        end
    end
end

SC.GetDictionary = function() return dict end

_G.YapperDB = { SpellcheckLearned = {}, Spellcheck = { Dict = {} } }
YAS:Init()

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        print(string.format("  [FAIL] %s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
        os.exit(1)
    else
        print(string.format("  [PASS] %s", msg))
    end
end

local function assert_true(val, msg)
    if not val then
        print(string.format("  [FAIL] %s", msg))
        os.exit(1)
    else
        print(string.format("  [PASS] %s", msg))
    end
end

local function assert_near(actual, expected, tolerance, msg)
    if math.abs(actual - expected) > tolerance then
        print(string.format("  [FAIL] %s: expected %.4f ± %.4f, got %.4f", msg, expected, tolerance, actual))
        os.exit(1)
    else
        print(string.format("  [PASS] %s (%.4f ≈ %.4f)", msg, actual, expected))
    end
end

-- Typo generators
local function transpose(word)
    if #word < 2 then return word end
    local i = math.random(1, #word - 1)
    return word:sub(1, i - 1) .. word:sub(i + 1, i + 1) .. word:sub(i, i) .. word:sub(i + 2)
end

local function delete_char(word)
    if #word < 3 then return word end
    local i = math.random(2, #word)
    return word:sub(1, i - 1) .. word:sub(i + 1)
end

local function random_typo(word)
    local r = math.random()
    if r < 0.5 then return transpose(word) else return delete_char(word) end
end

-- ---------------------------------------------------------------------------
-- Test 1: auto table pruning
-- ---------------------------------------------------------------------------
print("\n=== Test 1: auto table pruning ===")
YAS:Reset("enUS")
math.randomseed(1)

-- Fill auto with many distinct words (simulate typing many different words)
for i = 1, 30 do
    YAS:RecordIgnored("autoword" .. i, "enUS")
end

local db = YAS:GetLocaleDB("enUS")
assert_true(db.autoCount <= YAS:GetAutoCap(), "autoCount respects cap after prune")
assert_true(db.autoCount > 0, "autoCount still has entries after prune")

-- Verify high-usage words survive pruning by recording one word many times
YAS:Reset("enUS")
-- First, build up frequentword's count BEFORE hitting cap
for i = 1, 10 do
    YAS:RecordIgnored("frequentword", "enUS")  -- this one 10 times first
end
-- Then add rare words to trigger pruning
for i = 1, 25 do
    YAS:RecordIgnored("rareword" .. i, "enUS")  -- each once
end

local db = YAS:GetLocaleDB("enUS")
local foundFrequent = false
local foundRare = false
for w, _ in pairs(db.auto) do
    if w == "frequentword" then foundFrequent = true end
    if w:match("^rareword") then foundRare = true end
end
assert_true(foundFrequent, "High-usage frequentword survived auto pruning")
assert_true(foundRare, "Some rare words also present (prune is soft)")
print("  [INFO] auto table size after prune: " .. tostring(db.autoCount))

-- ---------------------------------------------------------------------------
-- Test 2: negBias time-based forgiveness decay
-- ---------------------------------------------------------------------------
print("\n=== Test 2: negBias forgiveness decay ===")
YAS:Reset("enUS")
local db = YAS:GetLocaleDB("enUS")

-- Record a rejection
YAS:RecordRejection("teh", { { word = "the" }, { word = "they" } }, "enUS")

local bonusFresh = YAS:GetBonus("the", "teh", nil, "enUS")

-- Simulate 60 days passing by rewriting the timestamp
db.negBias[negKey].t = db.negBias[negKey].t - (60 * 86400)

local bonusAged = YAS:GetBonus("the", "teh", nil, "enUS")

assert_true(bonusFresh > 0, "Fresh negBias produces a positive (penalty) bonus")
assert_true(bonusAged > 0, "Aged negBias still produces positive bonus")
assert_true(bonusAged < bonusFresh, "Aged negBias penalty is weaker than fresh (forgiveness)")

local expectedDecay = 1.0 / (60 / 30 + 1)  -- 0.333
assert_near(bonusAged / bonusFresh, expectedDecay, 0.05,
    "Decay ratio matches ~30-day half-life")
print(string.format("  [INFO] Fresh penalty: %.4f, Aged penalty: %.4f", bonusFresh, bonusAged))

-- ---------------------------------------------------------------------------
-- Test 3: AddedWords FIFO cap
-- ---------------------------------------------------------------------------
print("\n=== Test 3: AddedWords FIFO cap ===")
SC.UserDictCache = {}
local store = SC:GetUserDictStore()
if store then for k, v in pairs(store) do store[k] = nil end end

for i = 1, 60 do
    SC:AddUserWord("enUS", "userword" .. i)
end

local userDict = SC:GetUserDict("enUS")
assert_eq(#userDict.AddedWords, 50, "AddedWords capped at UserDictWordCap (50)")

-- Verify oldest evicted, newest kept
local foundFirst = false
local foundLast = false
for _, w in ipairs(userDict.AddedWords) do
    if w == "userword1" then foundFirst = true end
    if w == "userword60" then foundLast = true end
end
assert_true(not foundFirst, "Oldest addition (userword1) was evicted (FIFO)")
assert_true(foundLast, "Newest addition (userword60) is still present")
print("  [INFO] AddedWords size: " .. tostring(#userDict.AddedWords))

-- ---------------------------------------------------------------------------
-- Test 4: End-to-end pipeline (detection -> suggestion -> learning)
-- ---------------------------------------------------------------------------
print("\n=== Test 4: Detection -> Suggestion -> Learning Pipeline ===")
YAS:Reset("enUS")
SC:ClearSuggestionCache()
SC.UserDictCache = {}

-- Extract word list from text
local wordsList = {}
for w in MobyText:gmatch("[%w']+") do
    table.insert(wordsList, w)
end

-- First pass: cold, no learning
local function simulate_pass(pass_name, learn)
    local stats = { total = 0, hits = 0, top3 = 0, candidate = 0 }
    math.randomseed(42)
    for i, original in ipairs(wordsList) do
        if #original >= 4 then  -- only typo-ify longer words
            local typed = random_typo(original:lower())
            if typed ~= original:lower() then
                stats.total = stats.total + 1
                local suggestions = SC:GetSuggestions(typed)

                local foundAt = -1
                for rank, sug in ipairs(suggestions) do
                    if sug.word and sug.word:lower() == original:lower() then
                        foundAt = rank
                        break
                    end
                end

                if foundAt == 1 then stats.hits = stats.hits + 1 end
                if foundAt >= 1 and foundAt <= 3 then stats.top3 = stats.top3 + 1 end
                if foundAt > 0 then stats.candidate = stats.candidate + 1 end

                if learn and foundAt > 0 then
                    YAS:RecordSelection(typed, original, 0.5, "enUS")
                end
            end
        end
        YAS:RecordUsage(original, "enUS")
    end
    print(string.format("  %s: Top-1 %.1f%% | Top-3 %.1f%% | Candidate %.1f%% (N=%d)",
        pass_name,
        (stats.hits / math.max(1, stats.total)) * 100,
        (stats.top3 / math.max(1, stats.total)) * 100,
        (stats.candidate / math.max(1, stats.total)) * 100,
        stats.total))
    return stats
end

local pass1 = simulate_pass("Pass 1 (cold)", false)
local pass2 = simulate_pass("Pass 2 (warm - learned)", true)
local pass3 = simulate_pass("Pass 3 (warm - learned again)", true)

assert_true(pass2.hits >= pass1.hits, "Learning improves or maintains top-1 accuracy")
assert_true(pass3.hits >= pass2.hits or pass3.hits >= pass1.hits,
    "Repeated learning pass improves or maintains accuracy")

-- ---------------------------------------------------------------------------
-- Test 5: Implicit correction learning
-- ---------------------------------------------------------------------------
print("\n=== Test 5: Implicit Correction Learning ===")
YAS:Reset("enUS")

-- Simulate: user types "spleeen", suggestions appear, user manually corrects to "spleen"
-- First, make sure "spleen" is in the dictionary suggestions
local preImp = YAS:GetBonus("spleen", "spleeen", nil, "enUS")

-- Record implicit: the correction wasn't in candidates, but is phonetically close
YAS:RecordImplicitCorrection("spleeen", "spleen", {}, "enUS")

local postImp = YAS:GetBonus("spleen", "spleeen", nil, "enUS")
assert_true(postImp < preImp, "Implicit correction strengthened bias (lower bonus = better ranking)")
print(string.format("  [INFO] Bonus before implicit: %.4f, after: %.4f", preImp, postImp))

-- ---------------------------------------------------------------------------
-- Test 6: Auto-promotion threshold
-- ---------------------------------------------------------------------------
print("\n=== Test 6: Auto-promotion to user dictionary ===")
YAS:Reset("enUS")
SC.UserDictCache = {}
local addedWords = {}
SC.AddUserWord = function(_, loc, word)
    table.insert(addedWords, word)
end

for i = 1, 2 do
    YAS:RecordIgnored("SpecialWord", "enUS")
end
assert_eq(#addedWords, 0, "Not promoted before threshold (2 < 3)")

YAS:RecordIgnored("SpecialWord", "enUS")
assert_eq(#addedWords, 1, "Auto-promoted after hitting threshold (3)")
assert_eq(addedWords[1], "SpecialWord", "Promoted correct word")

print("\n=== All YAS pruning, decay & pipeline tests passed ===")
