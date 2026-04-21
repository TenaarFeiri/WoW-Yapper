--[[
    "German Breakdown" Test: Finding the Tipping Point
    Determining the limits of Yapper's performance under German engine conditions.
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

-- Mock YapperAPI for engine registration
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

local function RunStress(wordCount, garbagePerWordMB)
    SC._suggestionCache = {} -- COLD START
    
    -- Build Giant Dictionary
    local dict = { words = {}, set = {}, index = {}, phonetics = {}, ngramIndex2 = {}, ngramIndex3 = {} }
    for i = 1, wordCount do
        local w = "wort" .. i -- Use German-like words
        table.insert(dict.words, w)
        dict.set[w] = true
        local key = w:sub(1,1)
        dict.index[key] = dict.index[key] or {}
        table.insert(dict.index[key], w)
        
        -- German Engine Specifics: Phonetic Hash
        if engine and engine.GetPhoneticHash then
            local h = engine.GetPhoneticHash(w)
            dict.phonetics[h] = dict.phonetics[h] or {}
            table.insert(dict.phonetics[h], i)
        end
    end
    SC.Dictionaries["deDE"] = dict

    -- Background Garbage
    local garbagePool = {}
    local function MakeNoise()
        for i = 1, (garbagePerWordMB * 5) do -- Scale slightly lower to avoid OOM in test
            local t = { a=1, b=2, c={x=i} }
            table.insert(garbagePool, t)
        end
        if #garbagePool > 500 then garbagePool = {} end
        collectgarbage("step", 50)
    end

    local latencies = {}
    for i = 1, 50 do -- Run 50 iterations for average
        MakeNoise()
        local start = os.clock()
        SC:GetSuggestions("tstwort" .. i) 
        local stop = os.clock()
        table.insert(latencies, (stop - start) * 1000)
    end
    
    table.sort(latencies)
    return latencies[#latencies], latencies[25] -- Max, Median
end

print("Scaling German Stress Test (REAL RUN)...")
print("--------------------------------------------------")

local steps = {
    { words = 50000,   noise = 1,   label = "Normal (50k words)" },
    { words = 100000,  noise = 2,   label = "Medium (100k words)" },
    { words = 250000,  noise = 5,   label = "Heavy (250k words)" },
    { words = 500000,  noise = 10,  label = "Extreme (500k words)" },
}

for _, step in ipairs(steps) do
    collectgarbage("collect")
    local max, med = RunStress(step.words, step.noise)
    print(string.format("%-40s | Max: %7.3fms | Med: %7.3fms | Mem: %4d MB", 
        step.label, max, med, collectgarbage("count")/1024))
end
