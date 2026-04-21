--[[
    Suggestion Cache Stress Test
    Measures the memory and performance impact of a massive result cache.
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
        UserDictCache = {},
        _suggestionCache = {},
        _SCORE_WEIGHTS = { prefix = 1, lenDiff = 1, longerPenalty = 1, firstCharBias = 1, letterBag = 1, bigram = 1, vowelBonus = 1 },
        GetLocale = function() return "enUS" end,
        GetDictionary = function(self) return self.Dictionaries["enUS"] end,
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

-- 1. Setup a small dictionary
local dict = { words = {"apple", "banana", "cherry"}, set = {apple=true, banana=true, cherry=true}, index = {a={"apple"}, b={"banana"}, c={"cherry"}}, phonetics = {}, ngramIndex2 = {}, ngramIndex3 = {} }
SC.Dictionaries["enUS"] = dict

local function GetMem()
    collectgarbage("collect")
    return collectgarbage("count")
end

print("Suggestion Cache Stress Test")
print("----------------------------")
local baseline = GetMem()
print(string.format("Baseline: %.2f KB", baseline))

-- 2. Fill Cache
local targetSize = 50000
print(string.format("\nFilling cache with %d unique results...", targetSize))

local start = os.clock()
for i = 1, targetSize do
    SC:GetSuggestions("word" .. i)
end
local stop = os.clock()
local fillTime = (stop - start)

local fullMem = GetMem()
local cacheMem = fullMem - baseline
print(string.format("Memory Used by Cache: %.2f KB (Avg: %.2f bytes per entry)", cacheMem, (cacheMem * 1024) / targetSize))
print(string.format("Fill Time: %.3f s (%.3f ms per miss)", fillTime, (fillTime * 1000) / targetSize))

-- 3. Test Hit Performance (High Table Density)
print("\nTesting Hit Performance (10,000 hits)...")
local hitStart = os.clock()
for i = 1, 10000 do
    SC:GetSuggestions("word" .. i)
end
local hitStop = os.clock()
print(string.format("Avg Hit Time: %.5f ms", ((hitStop - hitStart) * 1000) / 10000))

-- 4. Reclaim Test
print("\nClearing Cache (SC._suggestionCache = {})...")
SC._suggestionCache = {}
local postClearMem = GetMem()
print(string.format("Final Memory: %.2f KB (Delta: %.2f KB)", postClearMem, postClearMem - baseline))

if math.abs(postClearMem - baseline) < 50 then
    print("\nSUCCESS: Cache memory fully reclaimed.")
else
    print("\nWARNING: Cache might be leaking or pinning objects.")
end
