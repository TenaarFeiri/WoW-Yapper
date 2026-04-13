-- =========================================================================
-- YAPPER DIAGNOSTIC: THE LIMS MYSTERY
-- =========================================================================
-- Deep-diving into why "lims" fails to find "limbs".
-- =========================================================================

math.randomseed(42)

-- 1. WOW ENVIRONMENT MOCK LAYER
_G = _G or {}
YapperTable = {
    Config = { Spellcheck = { Enabled = true, MinWordLength = 3, MaxSuggestions = 5, UseNgramIndex = true } },
    Dictionaries = {}
}
local function load_module(path) assert(loadfile(path))(nil, YapperTable) end
load_module("Src/Spellcheck.lua")
local Spellcheck = YapperTable.Spellcheck
load_module("Src/Spellcheck/Dicts/enBase.lua")
load_module("Src/Spellcheck/Dicts/enUS.lua")
Spellcheck:LoadDictionary("enUS")
while #Spellcheck._asyncLoaders > 0 do -- wait for load
    for k, v in pairs(Spellcheck._asyncLoaders) do v.cancelled = true; Spellcheck._asyncLoaders[k] = nil end
end
-- Synchronous load for diagnostic
Spellcheck:RegisterDictionary("enUS", YapperTable.Dictionaries["enUS"])

-- 2. TRACING GETSUGGESTIONS
-- =========================================================================
local input = "lims"
local target = "limbs"

print("--- Diagnostic: Searching for '" .. target .. "' starting from '" .. input .. "' ---")

local dict = Spellcheck.Dictionaries["enUS"]
local normInput = input:lower():gsub("[aeiouy]", "*")
local n = #input < 5 and 2 or 3
local idx = dict["ngramIndex" .. n]

print("Input Len:", #input, "N:", n, "Vowel-Neutral:", normInput)

-- Check N-gram Index
local foundInNgram = false
for i = 1, (#normInput - n + 1) do
    local g = normInput:sub(i, i + n - 1)
    local posting = idx[g]
    print("N-gram [" .. g .. "]:", posting and (#posting .. " ids") or "MISS")
    if posting then
        for _, id in ipairs(posting) do
            if dict.words[id] == target then
                foundInNgram = true; break
            end
        end
    end
end
print("Found in N-gram candidates:", foundInNgram)

-- Check GetSuggestions result
local sugs = Spellcheck:GetSuggestions(input, 10)
print("\nFinal Suggestions for '" .. input .. "':")
for i, s in ipairs(sugs) do
    print(i .. ". " .. s.value .. " (Distance logic check required)")
end
