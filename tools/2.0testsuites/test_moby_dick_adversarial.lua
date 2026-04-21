--[[
    Adversarial Stress Test R2: German Text in English Locale + User Dictionary
    Force enUS locale and observe how YALLM + User Dictionary overcome language mismatch.
]]

-- Mock Globals
_G.time = os.time
_G.GetTime = os.clock
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.CreateFrame = function() return { SetScript = function() end, Show = function() end, Hide = function() end } end
_G.C_Timer = { After = function() end }
_G.table_remove = table.remove

local YapperName, YapperTable = "Yapper", {
    Config = { 
        Spellcheck = { Enabled = true, UseNgramIndex = true, YALLMAutoThreshold = 5, MaxSuggestions = 6 },
        System = { DEBUG = false }
    },
    Utils = { Print = function(...) end },
    API = { Fire = function(...) end, RunFilter = function(_, _, p) return p end },
    Spellcheck = {
        UserDictCache = {},
        _suggestionCache = {},
        _SCORE_WEIGHTS = { prefix = 1.0, lenDiff = 1.0, longerPenalty = 1.0, firstCharBias = 1.0, letterBag = 1.0, bigram = 1.0, vowelBonus = 1.0 },
        _RAID_ICONS = {},
        Notify = function() end,
        GetLocale = function() return "enUS" end, -- FORCED
        GetActiveEngine = function() return nil end,
        GetMaxSuggestions = function() return 6 end,
        GetMaxWrongLetters = function() return 4 end,
        GetMinWordLength = function() return 2 end,
        GetReshuffleAttempts = function() return 20 end,
        GetMeta = function() return {} end,
        GetIgnoredRanges = function() return {} end,
        Dictionaries = {},
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

LoadFile("Src/Spellcheck/YALLM.lua")
LoadFile("Src/Spellcheck/Engine.lua")

local SC = YapperTable.Spellcheck
local YALLM = SC.YALLM

-- Implement User Dictionary Logic in Mock
function SC:GetUserDictStore()
    if not _G.YapperDB.Spellcheck then _G.YapperDB.Spellcheck = {} end
    if not _G.YapperDB.Spellcheck.Dict then _G.YapperDB.Spellcheck.Dict = {} end
    return _G.YapperDB.Spellcheck.Dict
end

function SC:GetUserDict(locale)
    local store = self:GetUserDictStore()
    if not store[locale] then store[locale] = { AddedWords = {}, IgnoredWords = {}, _rev = 0 } end
    return store[locale]
end

function SC:GetUserSets(locale)
    local dict = self:GetUserDict(locale)
    return { added = self:BuildWordSet(dict.AddedWords), _rev = dict._rev or 0 }, {}
end

function SC:BuildWordSet(list)
    local set = {}
    for _, w in ipairs(list) do set[self.NormaliseWord(w)] = true end
    return set
end

function SC:AddUserWord(locale, word)
    local dict = self:GetUserDict(locale)
    table.insert(dict.AddedWords, word)
    dict._rev = (dict._rev or 0) + 1
    self._suggestionCache = {}
end

-- 100 Most Common English Words
local EnglishWords = {
    "the", "be", "to", "of", "and", "a", "in", "that", "have", "it", "for", "not", "on", "with", "he", "as", "you", "do", "at", "this", "but", "his", "by", "from", "they", "we", "say", "her", "she", "or", "an", "will", "my", "one", "all", "would", "there", "their", "what", "so", "up", "out", "if", "about", "who", "get", "which", "go", "me", "when", "make", "can", "like", "time", "no", "just", "him", "know", "take", "people", "into", "year", "your", "good", "some", "could", "them", "see", "other", "than", "then", "now", "look", "only", "come", "its", "over", "think", "also", "back", "after", "use", "two", "how", "our", "work", "first", "well", "way", "even", "new", "want", "because", "any", "these", "give", "day", "most", "us"
}

local enDict = {
    words = EnglishWords, set = {}, index = {}, phonetics = {}, ngramIndex2 = {}
}
for i, w in ipairs(enDict.words) do
    local lw = w:lower()
    enDict.set[lw] = true
    local norm = lw:gsub("[aeiouy]", "*")
    for j = 1, #norm - 1 do
        local g = norm:sub(j, j + 1)
        enDict.ngramIndex2[g] = enDict.ngramIndex2[g] or {}
        table.insert(enDict.ngramIndex2[g], i)
    end
end

-- Mock Engine for enUS
local enEngine = {
    GetPhoneticHash = function(s) return s:sub(1,1):upper() .. #s end,
    KBLayouts = { "qwerty" },
    ScoreWeights = { prefix = 10, phonetic = 7 },
    HasVariantRules = true,
    VariantRules = {}
}

SC.GetDictionary = function() return enDict end
_G.SC_Addon_Internal = { ["enUS"] = { engine = enEngine } }

_G.YapperDB = { SpellcheckLearned = {}, Spellcheck = { Dict = {} } }
YALLM:Init()

local MobyText = [[
Nenne mich Ismael. Hör zu, was ich dir zu erzählen habe. Es gibt Jahre ohne Gesicht, 
man hat wenig oder gar kein Geld in der Tasche, weiß nichts Besonderes anzufangen an Land, 
da packt einen das Verlangen, auf See zu fahren und den wässerigen Teil der Welt zu sehen. 
Das ist so meine Art und Weise, den Miesmacher aus meinem Herzen zu verjagen und das Blut 
in Bewegung zu setzen. Wenn ich Bitterkeitsfalten spüre um den Mund, wenn meine Seele 
wie ein naßkalter and nieselnder November ist, wenn ich mich dabei ertappe, daß ich vor 
jedem Sargmagazin stehenbleibe und wie von selbst jedem Leichenzug folge, dann und 
hauptsächlich, wenn mein Miesmacher dermaßen Oberhand gewinnt, daß ich an mich halten 
muß, um nicht auf die Straße hinunterzusteigen und den Leuten die Hüte vom Kopf zu 
schlagen, dann begreife ich, daß es höchste Zeit für mich ist, auf See zu gehen. 
Das ersetzt mir den Gebrauch von Pistole und Kugel.
]]

-- Noise Generator
local function ApplyNoise(word)
    local r = math.random()
    if r < 0.10 then -- Misspell: Swap adjacent
        if #word < 2 then return word end
        local i = math.random(1, #word - 1)
        return word:sub(1, i-1) .. word:sub(i+1, i+1) .. word:sub(i, i) .. word:sub(i+2)
    elseif r < 0.20 then -- Incomplete
        local min = math.max(2, math.floor(#word * 0.4))
        local max = #word - 1
        if min <= max then
            return word:sub(1, math.random(min, max))
        end
    end
    return word
end

-- Simulator
print("Starting Adversarial Stress Test R2 (enUS Locale + User Dictionary)...")
print("---------------------------------------------------------------------")
local wordsList = {}
for w in MobyText:gmatch("[%wäöüßÄÖÜẞ']+") do table.insert(wordsList, w) end

local function RunPass(passNum)
    local telemetry = {
        total = 0, hits = 0, top3 = 0, candidate = 0,
        latencies = {}
    }

    math.randomseed(42) -- Same seed each pass
    for i, original in ipairs(wordsList) do
        telemetry.total = telemetry.total + 1
        local typed = ApplyNoise(original)
        local isError = (typed:lower() ~= original:lower())
        
        local start = os.clock()
        local suggestions = SC:GetSuggestions(typed)
        local stop = os.clock()
        table.insert(telemetry.latencies, (stop - start) * 1000)
        
        local foundAt = -1
        for rank, sug in ipairs(suggestions) do
            if sug.value and sug.value:lower() == original:lower() then
                foundAt = rank
                break
            end
        end
        
        if foundAt == 1 then telemetry.hits = telemetry.hits + 1 end
        if foundAt >= 1 and foundAt <= 3 then telemetry.top3 = telemetry.top3 + 1 end
        if foundAt > 0 then telemetry.candidate = telemetry.candidate + 1 end
        
        -- Simulation Logic:
        -- If it's a miss (foundAt <= 0), simulate the user "Adding to Dictionary" on Pass 1.
        if foundAt <= 0 and passNum == 1 then
            SC:AddUserWord("enUS", original)
        end

        -- Record Selection bias even if we had to add it manually
        YALLM:RecordSelection(typed, original, 0.5, "enUS")
        YALLM:RecordUsage(original, "enUS")
    end

    print(string.format("Pass %d: Top 1 = %.1f%% | Top 3 = %.1f%% | Any = %.1f%%", 
        passNum, (telemetry.hits / telemetry.total) * 100, (telemetry.top3 / telemetry.total) * 100, (telemetry.candidate / telemetry.total) * 100))
end

for p = 1, 6 do
    RunPass(p)
end

local yallmSummary = YALLM:GetDataSummary("enUS")
local userDict = SC:GetUserDict("enUS")

print("\n--- Final enUS State ---")
print(string.format("YALLM Entries:   %d", #yallmSummary.freq))
print(string.format("User Dict Words: %d", #userDict.AddedWords))

print("\nTop Learned Candidates (YALLM rank in enUS):")
table.sort(yallmSummary.freq, function(a, b) return a.count > b.count end)
for i = 1, math.min(10, #yallmSummary.freq) do
    print(string.format("  [%d] %-15s (count: %d)", i, yallmSummary.freq[i].word, yallmSummary.freq[i].count))
end

-- Verification: Did accuracy improve?
-- Expected: Pass 2-6 accuracy should be MUCH higher than Pass 1.
