#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_german_harness.lua  —  Performance & Memory Telemetry Simulation
-- Run from the repo root:  lua tools/2.0testsuites/test_german_harness.lua
-- ---------------------------------------------------------------------------

-- 1. WoW Environment Mocks
local _G = _G or {}
C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end }
time    = os.time
GetCurrentRegion = function() return 3 end -- Europe
GetLocale = function() return "deDE" end
LoadAddOn = function() return true end

-- CPU timing in milliseconds mock
local tStart = os.clock()
function debugprofilestop() return (os.clock() - tStart) * 1000 end

-- 2. Yapper Architecture Mocks
local YapperTable = {
    Config = {
        EditBox    = { AutocompleteEnabled = true },
        Spellcheck = { Enabled = true, MinWordLength = 3, Locale = "deDE" },
    },
    Utils = { DebugPrint = function() end, Print = function(m) print(m) end },
    API = {
        RunFilter = function(self, _, payload) return payload end,
    },
}

local function loadFile(path)
    local f, err = loadfile(path)
    if not f then
        io.stderr:write("FATAL: cannot load " .. path .. ": " .. tostring(err) .. "\n")
        os.exit(2)
    end
    f("__test__", YapperTable)
end

-- Load Core Modules
loadFile("Src/Spellcheck.lua")
loadFile("Src/Spellcheck/Engine.lua")
loadFile("Src/Spellcheck/Dictionary.lua")
loadFile("Src/Autocomplete.lua")
-- Mock YALLM initialization
YapperTable.Spellcheck.YALLM = {
    Init = function() end,
    RecordImplicitCorrection = function() end,
    ApplyState = function() end,
    db = { freq = {} }
}
YapperTable.Spellcheck.Dictionaries = {}

-- 3. Public API Bridge for LOD Addons
_G.YapperAPI = {
    RegisterLanguageEngine = function(_, family, engine)
        return YapperTable.Spellcheck:_RegisterLanguageEngine(family, engine)
    end,
    RegisterDictionary = function(_, loc, data)
        return YapperTable.Spellcheck:RegisterDictionary(loc, data)
    end
}

-- 4. Memory Profiling & LOD Injection
collectgarbage("collect")
local memBefore = collectgarbage("count") / 1024 -- MB
print("\n[Telemetry] Base Engine Memory: " .. string.format("%.2f MB", memBefore))

print("[Telemetry] Loading Dictionaries/Yapper_Dict_deDE/Engine.lua...")
dofile("Dictionaries/Yapper_Dict_deDE/Engine.lua")

print("[Telemetry] Loading 282,000+ string German Dictionary (Dict_deDE.lua)...")
local tLoadStart = os.clock()
dofile("Dictionaries/Yapper_Dict_deDE/Dict_deDE.lua")
local tLoadEnd = os.clock()

collectgarbage("collect")
local memAfter = collectgarbage("count") / 1024 -- MB
print("[Telemetry] Dictionary Load Time: " .. string.format("%.0f ms", (tLoadEnd - tLoadStart) * 1000))
print("[Telemetry] Total Memory Footprint: " .. string.format("%.2f MB", memAfter))
print("[Telemetry] Dictionary Object Delta: " .. string.format("%.2f MB", memAfter - memBefore))


-- 5. Establish Active Engine and Prepare Sets
local activeLocale = YapperTable.Spellcheck:GetLocale()
print("[Debug] activeLocale: ", tostring(activeLocale))
YapperTable.Spellcheck:EnsureLocale(activeLocale)
local dict = YapperTable.Spellcheck.Dictionaries[activeLocale]
print("[Debug] Dictionaries[activeLocale] exists: ", dict ~= nil)

if dict then
    dict.status = "loaded"
    dict.set = {}
    for _, w in ipairs(dict.words) do
        dict.set[YapperTable.Spellcheck.NormaliseWord(w)] = true
        dict.set[w] = true
    end
end
print("[Debug] Spellcheck:GetDictionary(activeLocale) returns: ", YapperTable.Spellcheck:GetDictionary(activeLocale) ~= nil)


-- 6. Typist Simulator
-- The user typed letter by letter. We measure the underlying function CPU time decoupled from the simulation overhead.
local function SimulateTyping(wordToType)
    local SC = YapperTable.Spellcheck
    local isCorrect = SC:IsWordCorrect(wordToType, dict)
    local typed = ""
    local totalAutoCompleteTime = 0
    local foundInTopIdx = nil
    local foundInAnyIdx = nil
    
    for i = 1, #wordToType do
        typed = typed .. wordToType:sub(i, i)
        
        -- Single-Line Autocomplete Simulation
        local t0 = debugprofilestop()
        local suggestion = YapperTable.Autocomplete:GetSuggestion(typed)
        local t1 = debugprofilestop()
        totalAutoCompleteTime = totalAutoCompleteTime + (t1 - t0)

        -- Progress Tracking: At what point does the correct word appear?
        -- (Only for misspelled test words where we want a correction)
        if not isCorrect then
            local instantSuggs = SC:GetSuggestions(typed)
            if instantSuggs then
                -- Check Top 3
                if not foundInTopIdx then
                    for j = 1, math.min(3, #instantSuggs) do
                        if instantSuggs[j].value and instantSuggs[j].value:lower() == wordToType:lower() then
                            foundInTopIdx = i
                            break
                        end
                    end
                end
                -- Check Any
                if not foundInAnyIdx then
                    for j = 1, #instantSuggs do
                        if instantSuggs[j].value and instantSuggs[j].value:lower() == wordToType:lower() then
                            foundInAnyIdx = i
                            break
                        end
                    end
                end
            end
        end
    end
    
    -- Final Spellcheck (after space)
    local tCheckStart = debugprofilestop()
    local hits = SC:CollectMisspellings(wordToType .. " ", dict)
    local tCheckEnd = debugprofilestop()
    
    local suggestionsTime = 0
    local YALLMTime = 0
    local suggestions = {}
    
    if not isCorrect then
        local tSugStart = debugprofilestop()
        suggestions = SC:GetSuggestions(wordToType)
        local tSugEnd = debugprofilestop()
        suggestionsTime = tSugEnd - tSugStart
        
        if #suggestions > 0 then
            local tYStart = debugprofilestop()
            SC.YALLM:RecordImplicitCorrection(wordToType, suggestions[1].value, suggestions)
            local tYEnd = debugprofilestop()
            YALLMTime = tYEnd - tYStart
        end
    end
    
    return {
        word = wordToType,
        correct = isCorrect,
        keystrokes = #wordToType,
        tAuto = totalAutoCompleteTime,
        tCheck = (tCheckEnd - tCheckStart),
        tSug = suggestionsTime,
        tYALLM = YALLMTime,
        suggs = suggestions,
        topIdx = foundInTopIdx,
        anyIdx = foundInAnyIdx,
    }
end

print("\n[Simulation] Typist Simulator Engaging...")
local wordsToTest = {
    "Katze",       -- Common short word
    "Schmetterling", -- Longer standard word
    "Donaudampfschifffahrt", -- Complex compound
    "Schmeterling", -- Typo (missing t)
    "Vaser",       -- Typo of Wasser (testing phonetic substitution W->V, etc.)
    "aeußerst",    -- Typo/Variant testing umlaut expansion
}

print(string.format("%-25s | %-12s | %-10s | %-10s | %-10s | %-7s | %-7s", 
    "Word", "Status", "Auto(ms)", "Check(ms)", "Suggs(ms)", "TopIdx", "AnyIdx"))
print(string.rep("-", 95))

for _, w in ipairs(wordsToTest) do
    local res = SimulateTyping(w)
    local status = res.correct and "Correct" or "Mispelled"
    print(string.format("%-25s | %-12s | %-10.2f | %-10.2f | %-10.2f | %-7s | %-7s", 
        w, status, res.tAuto, res.tCheck, res.tSug, 
        tostring(res.topIdx or "-"), tostring(res.anyIdx or "-")))
        
    if not res.correct and #res.suggs > 0 then
        local top = {}
        for i=1, math.min(3, #res.suggs) do 
            local sug = res.suggs[i]
            local score = sug.score or 0
            table.insert(top, sug.value .. string.format("(%.1f)", score)) 
        end
        print("  -> " .. table.concat(top, ", "))
    end
end

print(string.rep("=", 75))
print("Test complete.")
