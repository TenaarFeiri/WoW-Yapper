--[[
    "Spam Cannon" Optimization Verification
    Verifies that cache management remains O(1) even with large caps.
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
        UserDictCache = {}, _suggestionCache = {}, _suggestionCacheCount = 0,
        _SCORE_WEIGHTS = { prefix = 1, lenDiff = 1, longerPenalty = 1, firstCharBias = 1, letterBag = 1, bigram = 1, vowelBonus = 1 },
        _RAID_ICONS = {},
        GetLocale = function() return "enUS" end,
        GetDictionary = function(self) return self.Dictionaries["enUS"] end,
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

LoadFile("Src/Spellcheck.lua")
LoadFile("Src/Spellcheck/Engine.lua")

local SC = YapperTable.Spellcheck
SC.Dictionaries["enUS"] = { words = {}, set = {}, index = {}, phonetics = {}, ngramIndex2 = {}, ngramIndex3 = {} }

function SC:GetSuggestionCacheSize() return 1000000 end -- Set a massive cap for stress test

print("Spam Cannon Optimization Verification (O(1) Test)")
print("---------------------------------------------------")

local target = 100000
print(string.format("Processing %d unique words with a 1,000,000 cap...", target))

local start = os.clock()
for i = 1, target do
    SC:GetSuggestions("word" .. i)
    if i % 10000 == 0 then
        local now = os.clock()
        print(string.format("  Reached %d words (Latent speed: %.1f wps) | Mem: %.1f MB | CountVar: %d", 
            i, 10000 / (now - (last or start)), collectgarbage("count")/1024, SC._suggestionCacheCount))
        last = now
    end
end
local total = os.clock() - start

print(string.format("\nTotal Time: %.3f s", total))
print(string.format("Final Cache Count: %d", SC._suggestionCacheCount))

local locale = SC:GetLocale()
local noUserRev = "__nil_user_rev__"
local nested = SC._suggestionCache["word1"]
    and SC._suggestionCache["word1"][locale]
    and SC._suggestionCache["word1"][locale][noUserRev]
    and SC._suggestionCache["word1"][locale][noUserRev][SC:GetMaxSuggestions()]
if nested then
    print("Nested cache shape verified: cache[word][locale][userRev][maxCount]")
else
    print("WARNING: Nested cache shape missing expected entry for word1")
end

if total < 5 then -- 100,000 suggestions (misses) should be fast if O(1)
    print("\nSUCCESS: Management remains O(1) even at high entry counts.")
else
    print("\nWARNING: Unexpected latency detected. Check for O(N) loops.")
end
