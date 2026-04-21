--[[
    Noisy Environment Stress Test: Moby Dick + Background GC Pressure
    Simulates high-activity WoW environment with memory-churning addons.
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
    Config = { Spellcheck = { Enabled = true, UseNgramIndex = true, YALLMAutoThreshold = 5, MaxSuggestions = 6 } },
    Utils = { Print = function(...) end },
    API = { Fire = function(...) end, RunFilter = function(_, _, p) return p end },
    Spellcheck = {
        UserDictCache = {}, _suggestionCache = {}, _SCORE_WEIGHTS = { prefix = 1, lenDiff = 1, longerPenalty = 1, firstCharBias = 1, letterBag = 1, bigram = 1, vowelBonus = 1 },
        GetLocale = function() return "deDE" end,
        GetDictionary = function(self, locale) return self.Dictionaries[locale or self:GetLocale()] end,
        GetActiveEngine = function() return nil end,
        GetMaxSuggestions = function() return 6 end,
        GetMaxWrongLetters = function() return 4 end,
        GetMinWordLength = function() return 2 end,
        GetReshuffleAttempts = function() return 20 end,
        GetMeta = function() return {} end,
        GetIgnoredRanges = function() return {} end,
        GetUserDict = function() return { AddedWords = {}, IgnoredWords = {} } end,
        GetUserSets = function() return { added = {}, _rev = 0 }, {} end,
        Dictionaries = {},
        Clamp = function(v, min, max) return math.min(max, math.max(v, min)) end,
        NormaliseWord = function(s) return s:lower():gsub("[%p%c%s]", "") end,
        NormaliseVowels = function(s) return s:lower():gsub("[aeiouy]", "*") end,
        SuggestionKey = function(s) return s end,
        IsWordByte = function(b) return (b >= 97 and b <= 122) or b > 127 end,
        IsWordStartByte = function(b) return (b >= 97 and b <= 122) or b > 127 end,
        _ed_prev = {}, _ed_cur = {}, _ed_prev_prev = {}, _ed_aBytes = {}, _ed_bBytes = {},
    }
}

local function LoadFile(path)
    local f = assert(loadfile(path))
    f(YapperName, YapperTable)
end

LoadFile("Src/Spellcheck/YALLM.lua")
LoadFile("Src/Spellcheck/Engine.lua")

local SC = YapperTable.Spellcheck
local YALLM = SC.YALLM
_G.YapperDB = { SpellcheckLearned = {} }
YALLM:Init()

-- Load German Dict (Simulated)
local deDict = { words = {}, set = {}, index = {}, phonetics = {}, ngramIndex2 = {} }
for w in MobyText:gmatch("[%wäöüß']+") do
    local lw = w:lower()
    if not deDict.set[lw] then
        table.insert(deDict.words, lw)
        deDict.set[lw] = true
        local n = SC.NormaliseVowels(lw)
        for j = 1, #n-1 do
            local g = n:sub(j, j+1)
            deDict.ngramIndex2[g] = deDict.ngramIndex2[g] or {}
            table.insert(deDict.ngramIndex2[g], #deDict.words)
        end
    end
end
SC.Dictionaries["deDE"] = deDict

-- Background Noise Maker
local garbage_co = coroutine.create(function()
    local cycles = 0
    while true do
        local pool = {}
        for i = 1, 10000 do pool[i] = { a=i, b="string"..i, c={x=i} } end
        cycles = cycles + 1
        -- Small step to keep the collector working
        collectgarbage("step", 50)
        coroutine.yield()
    end
end)

local function MakeNoise()
    coroutine.resume(garbage_co)
end

-- Simulator
print("Starting Noisy Environment Stress Test...")
print("-----------------------------------------")

local wordsList = {}
for w in MobyText:gmatch("[%wäöüßÄÖÜẞ']+") do table.insert(wordsList, w) end

local function RunPass(passNum)
    local telemetry = { hits = 0, total = 0, latencies = {} }
    math.randomseed(42)

    for i, original in ipairs(wordsList) do
        MakeNoise() -- Induce GC pressure before each word
        
        telemetry.total = telemetry.total + 1
        local start = os.clock()
        local suggestions = SC:GetSuggestions(original)
        local stop = os.clock()
        
        table.insert(telemetry.latencies, (stop - start) * 1000)
        if suggestions[1] and suggestions[1].value:lower() == original:lower() then
            telemetry.hits = telemetry.hits + 1
            YALLM:RecordSelection(original, original, 1.0, "deDE")
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

print("\nConclusion:")
print("- The test simulated constant memory churn (simulating other addons).")
print("- If Avg latency remains < 1ms and Max < 10ms, Yapper is frame-safe under pressure.")
