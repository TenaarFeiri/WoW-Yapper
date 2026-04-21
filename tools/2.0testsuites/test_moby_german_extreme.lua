--[[
    "Extreme" Noisy Adversarial Test: German Moby Dick
    Simulates:
    - 3x Background Memory Churn (15MB/word addon chatter)
    - Adversarial User Input (Sustained Typos)
    - Full German Language Engine (Phonetics/Vowels)
    - Cache Performance (O(1) tracking)
]]

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

-- Mock Globals
_G.time = os.time
_G.GetTime = os.clock
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local YapperName, YapperTable = "Yapper", {
    Config = { 
        Spellcheck = { Enabled = true, UseNgramIndex = true, YALLMAutoThreshold = 5, MaxSuggestions = 6 },
        System = { DEBUG = false }
    },
    Utils = { Print = function(...) end },
    API = { Fire = function(...) end, RunFilter = function(_, _, p) return p end },
    Spellcheck = {
        UserDictCache = {}, _suggestionCache = {}, _suggestionCacheCount = 0,
        _SCORE_WEIGHTS = { prefix = 1, lenDiff = 1, longerPenalty = 1, firstCharBias = 1, letterBag = 1, bigram = 1, vowelBonus = 1 },
        _RAID_ICONS = {}, Notify = function() end,
        GetLocale = function() return "deDE" end,
        GetDictionary = function(self, locale) return self.Dictionaries[locale or self:GetLocale()] end,
        GetActiveEngine = function(self) return self.Engines["de"] end,
        GetMaxSuggestions = function() return 6 end,
        GetMaxWrongLetters = function() return 4 end,
        GetMinWordLength = function() return 2 end,
        GetReshuffleAttempts = function() return 20 end,
        GetMeta = function() return {} end,
        GetIgnoredRanges = function() return {} end,
        GetKeyboardLayout = function() return "QWERTZ" end,
        GetSuggestionCacheSize = function() return 5000 end,
        _GetKBDistFromLayouts = function() return setmetatable({}, {__index = function() return 2.0 end}) end,
        _KB_LAYOUTS = {},
        GetUserDict = function() return { AddedWords = {}, IgnoredWords = {} } end,
        GetUserSets = function() return { added = {}, _rev = 0 }, {} end,
        Dictionaries = {}, Engines = {},
        Clamp = function(v, min, max) return math.min(max, math.max(v, min)) end,
        NormaliseWord = function(s) return s:lower():gsub("[%p%c%s]", ""):gsub("ß", "ss") end,
        NormaliseVowels = function(s) return s:lower():gsub("[aeiouyäöü]", "*") end,
        SuggestionKey = function(s) return type(s) == "table" and (s.value or s.word) or s end,
        IsWordByte = function(b) return (b >= 97 and b <= 122) or b > 127 end,
        IsWordStartByte = function(b) return (b >= 97 and b <= 122) or b > 127 end,
        _ed_prev = {}, _ed_cur = {}, _ed_prev_prev = {}, _ed_aBytes = {}, _ed_bBytes = {},
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
local YALLM = SC.YALLM
_G.YapperDB = { SpellcheckLearned = {} }
YALLM:Init()

-- Implement centralized cache clearing for the mock
function SC:ClearSuggestionCache()
    self._suggestionCache = {}
    self._suggestionCacheCount = 0
end

-- Load German Dict (Simulated)
local deDict = { words = {}, set = {}, index = {}, phonetics = {}, ngramIndex2 = {}, ngramIndex3 = {} }
for w in MobyText:gmatch("[%wäöüß']+") do
    local lw = w:lower()
    if not deDict.set[lw] then
        table.insert(deDict.words, lw)
        deDict.set[lw] = true
        local n = SC.NormaliseVowels(lw)
        -- Indices
        local engine = SC:GetActiveEngine()
        if engine and engine.GetPhoneticHash then
            local h = engine.GetPhoneticHash(lw)
            deDict.phonetics[h] = deDict.phonetics[h] or {}
            table.insert(deDict.phonetics[h], #deDict.words)
        end
    end
end
SC.Dictionaries["deDE"] = deDict

-- Background Noise Maker (3x Intensity)
local garbage_co = coroutine.create(function()
    while true do
        local pool = {}
        for i = 1, 30000 do pool[i] = { a=i, b="spam"..i, c={x=i, y=i*2} } end
        collectgarbage("step", 200)
        coroutine.yield()
    end
end)

local function MakeNoise()
    coroutine.resume(garbage_co)
end

-- Adversarial Noise Generator
local function ApplyTypos(word)
    local r = math.random()
    if r < 0.15 then -- Misspell: Swap adjacent
        if #word < 2 then return word end
        local i = math.random(1, #word - 1)
        return word:sub(1, i-1) .. word:sub(i+1, i+1) .. word:sub(i, i) .. word:sub(i+2)
    elseif r < 0.15 then -- Incomplete
        local min = math.max(2, math.floor(#word * 0.4))
        local max = #word - 1
        if min <= max then return word:sub(1, math.random(min, max)) end
    end
    return word
end

-- Simulator
print("Starting EXTREME Noisy Adversarial Test (German)...")
print("Conditions: 3x Churn (~15MB/word) + German Engine + Typos")
print("------------------------------------------------------------")

local wordsList = {}
for w in MobyText:gmatch("[%wäöüßÄÖÜẞ']+") do table.insert(wordsList, w) end

local function RunPass(passNum)
    local telemetry = { hits = 0, total = 0, latencies = {} }
    math.randomseed(42)

    for i, original in ipairs(wordsList) do
        MakeNoise()
        local typed = ApplyTypos(original)
        
        telemetry.total = telemetry.total + 1
        local start = os.clock()
        local suggestions = SC:GetSuggestions(typed)
        local stop = os.clock()
        
        table.insert(telemetry.latencies, (stop - start) * 1000)
        if suggestions[1] and suggestions[1].value:lower() == original:lower() then
            telemetry.hits = telemetry.hits + 1
            YALLM:RecordSelection(typed, original, 1.0, "deDE")
        end
        YALLM:RecordUsage(original, "deDE")
    end

    table.sort(telemetry.latencies)
    local max = telemetry.latencies[#telemetry.latencies]
    local avg = 0
    for _, l in ipairs(telemetry.latencies) do avg = avg + l end
    avg = avg / #telemetry.latencies
    local p95 = telemetry.latencies[math.floor(#telemetry.latencies * 0.95)]

    print(string.format("Pass %d: Top1 = %.1f%% | Avg = %.3fms | P95 = %.3fms | Max = %.3fms | Mem = %.1f MB", 
        passNum, (telemetry.hits / telemetry.total) * 100, avg, p95, max, collectgarbage("count") / 1024))
end

for p = 1, 6 do
    RunPass(p)
end

print("\nFinal Results Summary:")
print("- The cache survived 6 passes of repeated typos with 3x background churn.")
print("- If Avg/P95 remain steady, the O(1) optimization and cache cap are working.")
