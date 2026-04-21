--[[
    Moby Dick Stress Test: German Engine + YALLM (Locale-Partitioned)
    Simulates high-load typing with introduced errors and measures adaptive learning.
]]

-- Mock Globals
_G.time = os.time
_G.GetTime = os.clock
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.CreateFrame = function() return { SetScript = function() end, Show = function() end, Hide = function() end } end
_G.C_Timer = { After = function() end }

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
        GetLocale = function() return "deDE" end,
        GetActiveEngine = function() return nil end, -- Fallback to synthetic
        GetMaxSuggestions = function() return 6 end,
        GetMaxWrongLetters = function() return 4 end,
        GetMinWordLength = function() return 2 end,
        GetReshuffleAttempts = function() return 20 end,
        GetMeta = function() return {} end,
        GetUserDict = function() return { AddedWords = {} } end,
        GetUserSets = function() return {}, {} end,
        GetIgnoredRanges = function() return {} end,
        Dictionaries = {},
        Clamp = function(v, min, max) return math.min(max, math.max(v, min)) end,
        NormaliseWord = function(s) return s:lower():gsub("[%p%c%s]", "") end,
        NormaliseVowels = function(s) return s:lower():gsub("[aeiouyäöü]", "*") end,
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

-- Mock Dictionary Logic
local MobyText = [[
Nenne mich Ismael. Hör zu, was ich dir zu erzählen habe. Es gibt Jahre ohne Gesicht, 
man hat wenig oder gar kein Geld in der Tasche, weiß nichts Besonderes anzufangen an Land, 
da packt einen das Verlangen, auf See zu fahren und den wässerigen Teil der Welt zu sehen. 
Das ist so meine Art und Weise, den Miesmacher aus meinem Herzen zu verjagen und das Blut 
in Bewegung zu setzen. Wenn ich Bitterkeitsfalten spüre um den Mund, wenn meine Seele 
wie ein naßkalter und nieselnder November ist, wenn ich mich dabei ertappe, daß ich vor 
jedem Sargmagazin stehenbleibe und wie von selbst jedem Leichenzug folge, dann und 
hauptsächlich, wenn mein Miesmacher dermaßen Oberhand gewinnt, daß ich an mich halten 
muß, um nicht auf die Straße hinunterzusteigen und den Leuten die Hüte vom Kopf zu 
schlagen, dann begreife ich, daß es höchste Zeit für mich ist, auf See zu gehen. 
Das ersetzt mir den Gebrauch von Pistole und Kugel.
]]

local deDict = {
    words = {}, set = {}, index = {}, phonetics = {}, ngramIndex2 = {}, phonetics_de = {}
}
for w in MobyText:gmatch("[%wäöüßÄÖÜẞ']+") do
    local lw = w:lower()
    if not deDict.set[lw] then
        local wordIdx = #deDict.words + 1
        table.insert(deDict.words, w)
        deDict.set[lw] = true
        -- Populate ngramIndex2 for sanity check
        local norm = lw:gsub("[aeiouyäöü]", "*")
        for i = 1, #norm - 1 do
            local g = norm:sub(i, i+1)
            deDict.ngramIndex2[g] = deDict.ngramIndex2[g] or {}
            table.insert(deDict.ngramIndex2[g], wordIdx)
        end
    end
end
-- Mock Engine for deDE
local deEngine = {
    GetPhoneticHash = function(s) return s:sub(1,1):upper() .. #s end,
    KBLayouts = { "qwertz" },
    ScoreWeights = { prefix = 10, phonetic = 7 },
    HasVariantRules = false
}

SC.GetDictionary = function() return deDict end
_G.SC_Addon_Internal = { ["deDE"] = { engine = deEngine } }

_G.YapperDB = { SpellcheckLearned = {} }
YALLM:Init()

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
            local len = math.random(min, max)
            return word:sub(1, len)
        end
    end
    return word
end

-- Simulator
print("Starting Moby Dick Stress Test (German)...")
print("-----------------------------------------")
local wordsList = {}
for w in MobyText:gmatch("[%wäöüßÄÖÜẞ']+") do table.insert(wordsList, w) end

local function RunPass(passName)
    local telemetry = {
        total = 0, hits = 0, top3 = 0, candidate = 0,
        latencies = {}
    }

    math.randomseed(42) -- Same seed = same noise
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
        
        -- Simulator Feedback: User chooses the word
        if isError and foundAt > 0 then
            YALLM:RecordSelection(typed, original, 0.5, "deDE")
        end
        YALLM:RecordUsage(original, "deDE")
    end

    local avgLat = 0
    for _, l in ipairs(telemetry.latencies) do avgLat = avgLat + l end
    avgLat = avgLat / #telemetry.latencies

    print(string.format("\n--- %s Report ---", passName))
    print(string.format("Top 1 Accuracy:    %.1f%%", (telemetry.hits / telemetry.total) * 100))
    print(string.format("Top 3 Accuracy:    %.1f%%", (telemetry.top3 / telemetry.total) * 100))
    print(string.format("Avg Latency:       %.2f ms", avgLat))
    return telemetry
end

local pass1 = RunPass("Pass 1 (Cold)")
local pass2 = RunPass("Pass 2 (Warm - YALLM)")

local summary = YALLM:GetDataSummary("deDE")
print(string.format("\nYALLM Partition:   deDE [Learned %d items]", #summary.freq))

-- Verify Partitioning (Leakage Test)
print("\n--- Leakage Case: English Test ---")
local enSummary = YALLM:GetDataSummary("enUS")
if not enSummary or #enSummary.freq == 0 then
    print("SUCCESS: No data leaked into enUS partition.")
else
    print("FAILURE: Data found in enUS partition!")
end
