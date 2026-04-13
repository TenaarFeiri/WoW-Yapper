-- =========================================================================
-- YAPPER GOLD MASTER VALIDATION: THE 1,000-WORD SWEEP
-- =========================================================================
-- Final statistical certification of the 1.2.5 engine.
-- =========================================================================

math.randomseed(42)

-- 1. WOW ENVIRONMENT MOCK LAYER (Synchronous for Benchmark)
-- =========================================================================
_G = _G or {}
C_Timer = {
    After = function(sec, func) func() end, 
    NewTicker = function(sec, func) return { Cancel = function() end } end
}

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
    SetPoint = function() end, SetAlpha = function() end,
    ClearAllPoints = function() end, GetLeft = function() return 0 end, 
    GetTop = function() return 0 end, GetBottom = function() return 0 end,
} end

local function load_module(path) assert(loadfile(path))(nil, YapperTable) end

print("--- Initializing Gold Master Engine (Synchronous) ---")
load_module("Src/Spellcheck.lua")
local Spellcheck = YapperTable.Spellcheck
Spellcheck.EditBox, Spellcheck.Overlay, Spellcheck.MeasureFS = CreateFrame(), CreateFrame(), CreateFrame()
load_module("Src/Spellcheck/Dicts/enBase.lua")
load_module("Src/Spellcheck/Dicts/enUS.lua")

-- Use the production loader to ensure correct inheritance and structure
Spellcheck:LoadDictionary("enUS")

-- 2. GOLD MASTER INDEX BUILDER (Tiered 500/2500)
-- =========================================================================
local function NormaliseVowels(word) return word:lower():gsub("[aeiouy]", "*") end

-- HELPER: Metatable-aware iterator for dictionary words
local function GetAllWords(dict)
    local all = {}
    -- 1. Get words from base if it exists
    if dict.extends then
        local base = Spellcheck.Dictionaries[dict.extends]
        if base then
            for i, w in ipairs(base.words) do all[i] = w end
        end
    end
    -- 2. Overlay delta words
    for i, w in ipairs(dict.words) do all[i] = w end
    return all
end

local function BuildGoldMasterIndex(dict)
    local words = GetAllWords(dict)
    local idx2, idx3 = {}, {}
    print("Indexing " .. #words .. " words (Full metatable stack)...")
    for id, word in ipairs(words) do
        local norm = NormaliseVowels(word)
        if #norm >= 2 then
            for i = 1, (#norm - 2 + 1) do
                local key = norm:sub(i, i + 1)
                idx2[key] = idx2[key] or {}
                if #idx2[key] < 500 then table.insert(idx2[key], id) end
            end
        end
        if #norm >= 3 then
            for i = 1, (#norm - 3 + 1) do
                local key = norm:sub(i, i + 2)
                idx3[key] = idx3[key] or {}
                if #idx3[key] < 2500 then table.insert(idx3[key], id) end
            end
        end
    end
    print("Indexing Complete.")
    return idx2, idx3, words
end

local dict = Spellcheck.Dictionaries["enUS"]
local idx2, idx3, FULL_WORDS = BuildGoldMasterIndex(dict)

-- 3. VALIDATION STRATEGY (Production Parity)
-- =========================================================================
local function GetGoldMasterStrategy(idx2, idx3, words)
    return function(word)
        local lowerLen = #word
        local n = lowerLen < 5 and 2 or 3
        local norm = NormaliseVowels(word)
        local candidates, seen = {}, {}; local dict = Spellcheck.Dictionaries["enUS"]
        local targetIdx = (n == 2) and idx2 or idx3
        
        local count = 0
        for i = 1, (#norm - n + 1) do
            local key = norm:sub(i, i + n - 1)
            local ids = targetIdx[key]
            if ids then 
                for _, id in ipairs(ids) do
                    local w = words[id]
                    if w and not seen[w] then
                        seen[w] = true; table.insert(candidates, w)
                        count = count + 1
                        if count >= 500 then break end
                    end
                end 
            end
            if count >= 500 then break end
        end
        
        local first, out = word:sub(1, 1):lower(), {}
        for _, cand in ipairs(candidates) do
            local d = Spellcheck:EditDistance(word:lower(), cand:lower(), (lowerLen < 5 and 2.5 or 3.5))
            if d then
                local score = d
                if cand:sub(1, 1):lower() == first then score = score - 1.5 end
                if NormaliseVowels(cand) == norm then score = score - 2.5 end
                table.insert(out, { word = cand, score = score })
            end
        end
        table.sort(out, function(a, b) return a.score < b.score end)
        local final = {}; for i = 1, math.min(4, #out) do final[i] = { kind = "word", value = out[i].word } end
        return final
    end
end

local strategy = GetGoldMasterStrategy(idx2, idx3, FULL_WORDS)

-- 4. TYPO GENERATION (Multi-Level)
-- =========================================================================
local function GenerateTypo(word, level)
    local mutations, chars = 0, {}
    for i = 1, #word do chars[i] = word:sub(i, i) end
    for _ = 1, level do
        local mode = math.random(1, 4)
        if mode == 1 then -- Swap
            local i = math.random(1, #chars - 1)
            chars[i], chars[i+1] = chars[i+1], chars[i]; mutations = mutations + 1
        elseif mode == 2 and #chars > 3 then -- Delete
            table.remove(chars, math.random(1, #chars)); mutations = mutations + 1
        elseif mode == 3 then -- Add
            table.insert(chars, math.random(1, #chars), string.char(math.random(97, 122))); mutations = mutations + 1
        elseif mode == 4 then -- Vowel Swap
            local vIdxs = {}
            for i = 1, #chars do if chars[i]:match("[aeiouy]") then table.insert(vIdxs, i) end end
            if #vIdxs > 0 then
                chars[vIdxs[math.random(1, #vIdxs)]] = string.sub("aeiouy", math.random(1,6), math.random(1,6)); mutations = mutations + 1
            end
        end
    end
    return table.concat(chars)
end

-- 5. VALIDATION SWEEP
-- =========================================================================
local TARGET_WORDS = {}
for i = 1, 1000 do table.insert(TARGET_WORDS, FULL_WORDS[math.random(1, #FULL_WORDS)]) end

print("\n" .. string.rep("=", 95))
print("YAPPER GOLD MASTER VALIDATION: 1,000-WORD STOCHASTIC SWEEP")
print(string.rep("=", 95))
print(string.format("%-25s | %-10s | %-10s | %-10s | %-10s", "TYPO LEVEL", "REL. (%)", "SCORE (%)", "P99(ms)", "MAX(ms)"))
print(string.rep("-", 95))

for level = 1, 3 do
    local totalWeighted, successesAt4 = 0, 0
    local timings = {}

    for _, groundTruth in ipairs(TARGET_WORDS) do
        local mangled = GenerateTypo(groundTruth, level)
        local start = os.clock()
        local suggestions = strategy(mangled)
        local cpu_ms = (os.clock() - start) * 1000
        table.insert(timings, cpu_ms)
        
        local rank = 0
        for r = 1, #suggestions do
            if string.lower(suggestions[r].value) == string.lower(groundTruth) then
                rank = r; break
            end
        end
        
        local weights = { [1] = 1.0, [2] = 0.75, [3] = 0.50, [4] = 0.25 }
        totalWeighted = totalWeighted + (weights[rank] or 0)
        if rank > 0 then successesAt4 = successesAt4 + 1 end
    end

    table.sort(timings)
    local p99 = timings[math.floor(#timings * 0.99)]
    local max = timings[#timings]
    
    print(string.format("Level %d (%-10s)    | %-10.1f | %-10.1f | %-10.2f | %-10.2f", 
        level, level == 1 and "Mutation" or level == 2 and "Fat-Finger" or "Rage-Type",
        (successesAt4 / 1000) * 100, (totalWeighted / 1000) * 100, p99, max))
end

print(string.rep("=", 95))
