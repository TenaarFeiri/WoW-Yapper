--[[
    "German Breakdown" Test: Cold vs Warm Cache
    Measures the impact of the suggestion cache on the German engine.
]]

-- Mock Globals
_G.time = os.time
_G.GetTime = os.clock
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local YapperName, YapperTable = "Yapper", {
    Config = { Spellcheck = { Enabled = true, UseNgramIndex = true, MaxSuggestions = 6 } },
    Utils = { Print = function(...) end },
    API = { Fire = function(...) end, RunFilter = function(_, _, p) return p end },
    Spellcheck = {
        UserDictCache = {}, _suggestionCache = {},
        _SCORE_WEIGHTS = { prefix = 1, lenDiff = 1, longerPenalty = 1, firstCharBias = 1, letterBag = 1, bigram = 1, vowelBonus = 1 },
        _RAID_ICONS = {},
        GetLocale = function() return "deDE" end,
        GetDictionary = function(self, locale) return self.Dictionaries[locale or self:GetLocale()] end,
        GetActiveEngine = function(self) return self.Engines["de"] end,
        GetMaxSuggestions = function() return 6 end,
        GetMaxWrongLetters = function() return 4 end,
        GetMinWordLength = function() return 2 end,
        GetReshuffleAttempts = function() return 20 end,
        GetMeta = function() return {} end,
        GetIgnoredRanges = function() return {} end,
        Dictionaries = {}, Engines = {},
        Clamp = function(v, min, max) return math.min(max, math.max(v, min)) end,
        NormaliseWord = function(s) return s:lower():gsub("[%p%c%s]", ""):gsub("ß", "ss") end,
        NormaliseVowels = function(s) return s:lower():gsub("[aeiouy]", "*") end,
        SuggestionKey = function(s) return s end,
        IsWordByte = function(b) return (b >= 97 and b <= 122) or b > 127 end,
        IsWordStartByte = function(b) return (b >= 97 and b <= 122) or b > 127 end,
        _ed_prev = {}, _ed_cur = {}, _ed_prev_prev = {}, _ed_aBytes = {}, _ed_bBytes = {},
        GetUserDict = function() return { AddedWords = {}, IgnoredWords = {} } end,
        GetUserSets = function() return { added = {}, _rev = 0 }, {} end,
    }
}

_G.YapperAPI = {
    RegisterLanguageEngine = function(self, lang, engine)
        YapperTable.Spellcheck.Engines[lang] = engine
        return true
    end
}

local function LoadFile(path)
    local f = assert(loadfile(path))
    f(YapperName, YapperTable)
end

LoadFile("Src/Spellcheck/YALLM.lua")
LoadFile("Src/Spellcheck/Engine.lua")
LoadFile("Dictionaries/Yapper_Dict_deDE/Engine.lua")

local SC = YapperTable.Spellcheck
local engine = SC:GetActiveEngine()

local function RunStress(wordCount)
    SC._suggestionCache = {} -- Reset for Cold Measurement
    
    -- Build Giant Dictionary
    local dict = { words = {}, set = {}, index = {}, phonetics = {}, ngramIndex2 = {}, ngramIndex3 = {} }
    for i = 1, wordCount do
        local w = "wort" .. i
        table.insert(dict.words, w)
        dict.set[w] = true
        local key = w:sub(1,1)
        dict.index[key] = dict.index[key] or {}
        table.insert(dict.index[key], w)
        if engine and engine.GetPhoneticHash then
            local h = engine.GetPhoneticHash(w)
            dict.phonetics[h] = dict.phonetics[h] or {}
            table.insert(dict.phonetics[h], i)
        end
    end
    SC.Dictionaries["deDE"] = dict

    -- 1. Measure Cold Start
    local coldStart = os.clock()
    SC:GetSuggestions("tstwort")
    local coldStop = os.clock()
    local cold = (coldStop - coldStart) * 1000

    -- 2. Measure Warm Hit (Immediate)
    local warmStart = os.clock()
    SC:GetSuggestions("tstwort")
    local warmStop = os.clock()
    local warm = (warmStop - warmStart) * 1000

    return cold, warm
end

print("German Cache Scaling Test (REAL RUN)")
print("--------------------------------------------------")
print(string.format("%-20s | %-12s | %-12s", "Scale", "Cold Latency", "Warm Latency"))
print("--------------------------------------------------")

local steps = { 50000, 100000, 250000, 500000, 1000000 }
for _, words in ipairs(steps) do
    collectgarbage("collect")
    local cold, warm = RunStress(words)
    print(string.format("%-20s | %8.3f ms | %8.3f ms", words .. " words", cold, warm))
end
