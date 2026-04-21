--[[
    Dictionary Lifecycle & GC Stress Test
    Validates memory reclamation when dictionaries are swapped or purged.
]]

-- Mock Globals
_G.time = os.time
_G.GetTime = os.clock
_G.C_Timer = { After = function() end }
_G.table_remove = table.remove
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local YapperName, YapperTable = "Yapper", {
    Config = { Spellcheck = { Enabled = true, DICT_CHUNK_SIZE = 1000 } },
    Utils = { Print = function(...) end },
    Spellcheck = {
        Dictionaries = {},
        _asyncLoaders = {},
        _DICT_CHUNK_SIZE = 1000,
        Clamp = function(v, min, max) return math.min(max, math.max(v, min)) end,
        NormaliseWord = function(s) return s:lower():gsub("[%p%c%s]", "") end,
        NormaliseVowels = function(s) return s:lower():gsub("[aeiouy]", "*") end,
        IsWordStartByte = function(b) return (b >= 97 and b <= 122) or (b >= 65 and b <= 90) or b > 127 end,
        Notify = function(msg) print("  NOTIFY: " .. msg) end,
        IsEnabled = function() return true end,
        ScheduleRefresh = function() end,
        GetConfig = function() return { Locale = "enUS" } end,
        _RegisterLanguageEngine = function() end,
        ClearUnderlines = function() end,
        SuggestionFrame = nil,
        HintFrame = nil,
    }
}

-- Load Core Logic
local function LoadFile(path)
    local f = assert(loadfile(path))
    f(YapperName, YapperTable)
end

LoadFile("Src/Spellcheck/Dictionary.lua")
LoadFile("Src/Spellcheck/UI.lua") -- For UnloadAllDictionaries

local SC = YapperTable.Spellcheck

local function GetMem()
    collectgarbage("collect") -- Force a clean count for the reading
    return collectgarbage("count")
end

local function GetMemNoPurge()
    return collectgarbage("count")
end

print("Starting Dictionary Lifecycle & GC Stress Test...")
print("------------------------------------------------")

local baseline = GetMem()
print(string.format("Baseline Memory: %.2f KB", baseline))

-- 1. Create a large dummy dictionary
local function CreateDictionary(size)
    local words = {}
    for i = 1, size do
        words[i] = "word" .. i .. "extralongstringtofillmemory"
    end
    return {
        words = words,
        languageFamily = "en",
        engine = {}
    }
end

-- 2. Load Dictionary A (Sync)
print("\nLoading Dictionary A (50k words)...")
local dictA = CreateDictionary(50000)
SC:RegisterDictionary("enUS", dictA)
local memA = GetMem()
print(string.format("Memory with Dict A: %.2f KB (Delta: +%.2f KB)", memA, memA - baseline))

-- 3. Load Dictionary B (Sync)
print("\nLoading Dictionary B (50k words)...")
local dictB = CreateDictionary(50000)
SC:RegisterDictionary("deDE", dictB)
local memB = GetMem()
print(string.format("Memory with Dict A+B: %.2f KB (Delta: +%.2f KB)", memB, memB - memA))

-- 4. Purge All Dictionaries
print("\nPurging All Dictionaries (UnloadAllDictionaries)...")
dictA = nil -- UNPIN
dictB = nil -- UNPIN
SC:UnloadAllDictionaries(false) -- Scrub tables but don't force collect
local memPostPurge = GetMemNoPurge()
print(string.format("Memory immediately after purge (No GC): %.2f KB", memPostPurge))

-- 5. Incremental GC Simulation
print("\nSimulating Incremental GC (100 steps of 100)...")
for i = 1, 10 do
    for j = 1, 10 do
        collectgarbage("step", 100)
    end
    print(string.format("  Step %d/10: %.2f KB", i, GetMemNoPurge()))
end

-- 6. Final Clean
local finalMem = GetMem()
local finalDelta = finalMem - baseline
print(string.format("\nFinal Memory (Forced GC): %.2f KB (Delta from baseline: %.2f KB)", finalMem, finalDelta))

if math.abs(finalDelta) < 100 then
    print("\nSUCCESS: All dictionary memory reclaimed.")
else
    print("\nWARNING: Persistent delta of " .. finalDelta .. " KB detected.")
end

-- 7. Leak Test for Async Loaders
print("\nTesting Async Loader Cancellation...")
SC._asyncLoaders = {}
SC:RegisterDictionary("frFR", { words = {"a","b"}, languageFamily = "fr" })
SC:UnloadAllDictionaries(false)
if SC._asyncLoaders["frFR"] == nil then
    print("SUCCESS: Async loaders cleared on unload.")
else
    print("FAILURE: Async loaders persisting after unload.")
end
