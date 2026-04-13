-- =========================================================================
-- YAPPER PRODUCTION VALIDATION: THE FRANKENSTEIN SUITE
-- =========================================================================
-- Validating the production Spellcheck.lua against the human test cases.
-- =========================================================================

-- 1. WOW ENVIRONMENT MOCK LAYER
-- =========================================================================
_G = _G or {}
local timerQueue = {}
C_Timer = {
    After = function(sec, func) table.insert(timerQueue, func) end,
    NewTicker = function(sec, func) return { Cancel = function() end } end
}
local function DrainQueue()
    while #timerQueue > 0 do table.remove(timerQueue, 1)() end
end

YapperTable = {
    Config = {
        Spellcheck = {
            Enabled         = true,
            MinWordLength   = 3,
            MaxSuggestions  = 5,
            DistanceLimit   = 2.5,
            UseNgramIndex   = true,
        },
        System = { DEBUG = false }
    },
    Dictionaries = {}
}

LibStub = { libs = {}, NewLibrary = function(s, n) s.libs[n] = s.libs[n] or {} return s.libs[n] end, GetLibrary = function(s, n) return s.libs[n] end }
GetLocale = function() return "enUS" end
GetTime = function() return 0 end
CreateFrame = function() return { 
    SetWidth = function() end, SetText = function() end, GetStringWidth = function() return 100 end, 
    GetStringHeight = function() return 14 end, GetLineHeight = function() return 14 end, 
    CreateTexture = function() return {} end, SetScript = function() end, SetSize = function() end, 
    SetPoint = function() end, ClearAllPoints = function() end, GetLeft = function() return 0 end, 
    GetTop = function() return 0 end, GetBottom = function() return 0 end,
} end

-- Use production helper
local function load_module(path) assert(loadfile(path))(nil, YapperTable) end

print("--- Initializing Production Engine ---")
load_module("Src/Spellcheck.lua")
local Spellcheck = YapperTable.Spellcheck
Spellcheck.EditBox, Spellcheck.Overlay, Spellcheck.MeasureFS = CreateFrame(), CreateFrame(), CreateFrame()
load_module("Src/Spellcheck/Dicts/enBase.lua")
load_module("Src/Spellcheck/Dicts/enUS.lua")
Spellcheck:LoadDictionary("enUS")
DrainQueue()

-- 2. THE FRANKENSTEIN TEST CASES (Words from user input)
-- =========================================================================
local FRANKENSTEIN_TYPOS = {
    { query = "dreery",       truth = "dreary" },
    { query = "Novembar",     truth = "November" },
    { query = "acomplishment",truth = "accomplishment" },
    { query = "anxity",       truth = "anxiety" },
    { query = "allmost",      truth = "almost" },
    { query = "aggony",       truth = "agony" },
    { query = "colected",     truth = "collected" },
    { query = "instrumants",  truth = "instruments" },
    { query = "infuze",       truth = "infuse" },
    { query = "beeing",       truth = "being" },
    { query = "allready",     truth = "already" },
    { query = "morrning",     truth = "morning" },
    { query = "patered",      truth = "pattered" },
    { query = "dismaly",      truth = "dismally" },
    { query = "candel",       truth = "candle" },
    { query = "nerely",       truth = "nearly" },
    { query = "glimer",       truth = "glimmer" },
    { query = "extingushed",  truth = "extinguished" },
    { query = "yelow",        truth = "yellow" },
    { query = "creture",      truth = "creature" },
    { query = "brethed",      truth = "breathed" },
    { query = "convulsiv",    truth = "convulsive" },
    { query = "aggetated",    truth = "agitated" },
    { query = "lims",         truth = "limbs" },
    { query = "discribe",     truth = "describe" },
    { query = "emmotions",    truth = "emotions" },
    { query = "catastrofe",   truth = "catastrophe" },
    { query = "deliniate",    truth = "delineate" },
    { query = "wredch",       truth = "wretch" },
    { query = "infanite",     truth = "infinite" },
    { query = "endevored",    truth = "endeavored" },
    { query = "proporsion",   truth = "proportion" },
    { query = "fetures",      truth = "features" },
    { query = "beutiful",     truth = "beautiful" },
    { query = "scarsely",     truth = "scarcely" },
    { query = "coverd",       truth = "covered" },
    { query = "musles",       truth = "muscles" },
    { query = "artaries",     truth = "arteries" },
    { query = "beneth",       truth = "beneath" },
    { query = "lusterous",    truth = "lustrous" },
    { query = "flowwing",     truth = "flowing" },
}

-- 3. EXECUTION & REPORTING
-- =========================================================================
print("\n" .. string.rep("=", 80))
print("PRODUCTION FREEZE-TEST: FRANKENSTEIN SUITE")
print(string.rep("=", 80))
print(string.format("%-15s | %-15s | %-4s | %-20s", "TYPO", "GROUND TRUTH", "RANK", "SUGGESTIONS"))
print(string.rep("-", 80))

local successAt1, successAt4, totalCount = 0, 0, #FRANKENSTEIN_TYPOS
local results = {}

for _, test in ipairs(FRANKENSTEIN_TYPOS) do
    local suggestions = Spellcheck:GetSuggestions(test.query, 4)
    local rank = 0
    local suggestionValues = {}
    for r, sug in ipairs(suggestions) do
        table.insert(suggestionValues, sug.value)
        if string.lower(sug.value) == string.lower(test.truth) then
            rank = r
        end
    end
    
    if rank == 1 then successAt1 = successAt1 + 1 end
    if rank > 0 then successAt4 = successAt4 + 1 end
    
    local rankStr = (rank > 0) and tostring(rank) or "FAIL"
    local sugList = table.concat(suggestionValues, ", ")
    print(string.format("%-15s | %-15s | %-4s | %s", test.query, test.truth, rankStr, (sugList:sub(1, 35))))
    
    table.insert(results, { query = test.query, truth = test.truth, rank = rank, sugs = sugList })
end

print(string.rep("=", 80))
print(string.format("Discovery (S@4): %.1f%% (%d/%d)", (successAt4/totalCount)*100, successAt4, totalCount))
print(string.format("Precision (S@1): %.1f%% (%d/%d)", (successAt1/totalCount)*100, successAt1, totalCount))
print(string.rep("=", 80))

if (successAt4 / totalCount) < 0.90 then
    print("\n[WARNING] Recovery is below the 90% target for human typos!")
else
    print("\n[SUCCESS] Production logic PASSES the Frankenstein freeze-test.")
end
