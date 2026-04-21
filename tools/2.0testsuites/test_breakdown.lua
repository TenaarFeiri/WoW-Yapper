--[[
    "Breakdown" Test: Finding the Tipping Point
    Determining the limits of Yapper's performance under extreme conditions.
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
        UserDictCache = {}, _suggestionCache = {}, _SCORE_WEIGHTS = { prefix = 1, lenDiff = 1, longerPenalty = 1, firstCharBias = 1, letterBag = 1, bigram = 1, vowelBonus = 1 },
        GetLocale = function() return "enUS" end,
        GetDictionary = function(self, locale) return self.Dictionaries[locale or self:GetLocale()] end,
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
        SuggestionKey = function(s) return s end,
        IsWordByte = function(b) return (b >= 97 and b <= 122) or b > 127 end,
        IsWordStartByte = function(b) return (b >= 97 and b <= 122) or b > 127 end,
        _ed_prev = {}, _ed_cur = {}, _ed_prev_prev = {}, _ed_aBytes = {}, _ed_bBytes = {},
        GetUserDict = function() return { AddedWords = {}, IgnoredWords = {} } end,
        GetUserSets = function() return { added = {}, _rev = 0 }, {} end,
    }
}

local function LoadFile(path)
    local f = assert(loadfile(path))
    f(YapperName, YapperTable)
end

LoadFile("Src/Spellcheck/YALLM.lua")
LoadFile("Src/Spellcheck/Engine.lua")

local SC = YapperTable.Spellcheck

local function RunStress(wordCount, garbagePerWordMB)
    -- Build Giant Dictionary
    local dict = { words = {}, set = {}, index = {}, phonetics = {}, ngramIndex2 = {}, ngramIndex3 = {} }
    for i = 1, wordCount do
        local w = "word" .. i
        table.insert(dict.words, w)
        dict.set[w] = true
        local key = w:sub(1,1)
        dict.index[key] = dict.index[key] or {}
        table.insert(dict.index[key], w)
    end
    SC.Dictionaries["enUS"] = dict

    -- Background Garbage
    local garbagePool = {}
    local function MakeNoise()
        for i = 1, (garbagePerWordMB * 10) do -- Approx scale
            local t = { a=1, b=2, c={x=i} }
            table.insert(garbagePool, t)
        end
        if #garbagePool > 1000 then garbagePool = {} end
        collectgarbage("step", 100)
    end

    local latencies = {}
    for i = 1, 100 do
        MakeNoise()
        local start = os.clock()
        SC:GetSuggestions("tsetword") -- Use a typo to force scoring
        local stop = os.clock()
        table.insert(latencies, (stop - start) * 1000)
    end
    
    table.sort(latencies)
    return latencies[#latencies], latencies[50] -- Max, Median
end

print("Scaling Stress Test (Finding the Tipping Point)...")
print("Threshold for concern: >10ms Max Latency")
print("--------------------------------------------------")

local steps = {
    { words = 50000,   noise = 1,   label = "Normal (50k words)" },
    { words = 200000,  noise = 5,   label = "Heavy (200k words, 5MB noise)" },
    { words = 500000,  noise = 20,  label = "Extreme (500k words, 20MB noise)" },
    { words = 1000000, noise = 50,  label = "Ludicrous (1M words, 50MB noise)" },
    { words = 2000000, noise = 150, label = "Tipping (2M words, 150MB noise)" },
}

for _, step in ipairs(steps) do
    collectgarbage("collect") -- Reset
    local max, med = RunStress(step.words, step.noise)
    local status = (max > 10) and " [PROBLEMATIC]" or " [OK]"
    print(string.format("%-40s | Max: %7.3fms | Med: %7.3fms | Mem: %4d MB %s", 
        step.label, max, med, collectgarbage("count")/1024, status))
end
