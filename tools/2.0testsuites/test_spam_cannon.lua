--[[
    The "Spam Cannon" Torture Test
    Simulates extreme, sustained input to find the failure point of the cache and GC.
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
        GetLocale = function() return "enUS" end,
        GetDictionary = function(self, locale) return self.Dictionaries[locale or self:GetLocale()] end,
        GetActiveEngine = function() return nil end,
        GetMaxSuggestions = function() return 6 end,
        GetMaxWrongLetters = function() return 4 end,
        GetMinWordLength = function() return 2 end,
        GetReshuffleAttempts = function() return 20 end,
        GetMeta = function() return {} end,
        GetIgnoredRanges = function() return {} end,
        Dictionaries = {}, Clamp = function(v, min, max) return math.min(max, math.max(v, min)) end,
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

-- Setup Dict
local dict = { words = {}, set = {}, index = {}, phonetics = {}, ngramIndex2 = {}, ngramIndex3 = {} }
for i = 1, 10000 do
    local w = "word" .. i
    table.insert(dict.words, w)
    dict.set[w] = true
    local key = w:sub(1,1)
    dict.index[key] = dict.index[key] or {}
    table.insert(dict.index[key], w)
end
SC.Dictionaries["enUS"] = dict

local function GetMem()
    return collectgarbage("count")
end

print("Starting The Spam Cannon Torture Test...")
print("Simulating 60,000 WPM (1,000 words per second) unique input.")
print("------------------------------------------------------------")

local totalWords = 0
local startTime = os.clock()
local lastReport = startTime
local memoryLimitKB = 600 * 1024 -- 600MB

for i = 1, 1000000 do -- Try to process 1 Million words
    totalWords = totalWords + 1
    
    -- Random "Spam" word
    local word = "spam" .. i .. math.random(1, 1000)
    SC:GetSuggestions(word)
    
    -- Simulate periodic GC (like WoW does)
    if i % 100 == 0 then
        collectgarbage("step", 10)
    end
    
    -- Report every 10k words
    if i % 10000 == 0 then
        local now = os.clock()
        local elapsed = now - lastReport
        local mem = GetMem()
        print(string.format("Processed: %d words | Speed: %.1f wps | Mem: %.1f MB", 
            i, 10000 / elapsed, mem / 1024))
        lastReport = now
        
        if mem > memoryLimitKB then
            print("\n!!! BREAKING POINT REACHED: OOM / 600MB Threshold !!!")
            break
        end
    end
end

local totalElapsed = os.clock() - startTime
print("\nFinal Result:")
print(string.format("Total Words: %d", totalWords))
print(string.format("Total Time: %.2f s", totalElapsed))
print(string.format("Average Speed: %.1f words/sec", totalWords / totalElapsed))
print(string.format("Final Memory: %.1f MB", GetMem() / 1024))
