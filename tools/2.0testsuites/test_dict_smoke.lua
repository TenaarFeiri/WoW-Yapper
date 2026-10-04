#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_dict_smoke.lua  --  real-dictionary smoke tests (GATING)
-- Run from the repo root:  lua tools/2.0testsuites/test_dict_smoke.lua
--
-- Loads each shipped dictionary + language engine through the real
-- registration path (Src/Spellcheck/Dictionary.lua + Engine.lua) and asserts:
--
--   1. Presence: a small set of high-frequency words MUST be in each dict.
--      This catches upstream-source holes like the "alive" gap, which sat in
--      no shipped locale until an audit found it (Hunspell derives it via
--      affix flags; the source wordlists never listed it).
--   2. Correctness path: IsWordCorrect resolves flat words, affix-stripped
--      forms, and rejects garbage — through the real engine contract.
--   3. Suggestion pipeline: known typos produce their expected corrections.
--      The reshuffle-starvation regression ("doign" never yielding "doing")
--      survived because no gating test drove GetSuggestions against a real
--      dictionary; these cases close that hole.
--
-- The mock SC layer mirrors tools/bench_suggestions.lua, which is verified
-- end-to-end against the same real data.
-- ---------------------------------------------------------------------------

local PASS, FAILURES = "PASS", 0

local function check(label, condition)
    if condition then
        print("  [" .. PASS .. "] " .. label)
    else
        FAILURES = FAILURES + 1
        print("  [FAIL] " .. label)
    end
end

-- ---------------------------------------------------------------------------
-- Harness: mock SC + WoW globals, load engine + dict files, register for real.
-- ---------------------------------------------------------------------------

local function buildHarness(engineFile, dictFiles, locale)
    _G.C_Timer = {}
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

    local dictFactories, engines = {}, {}

    local YapperName = "Yapper"
    local YapperTable = {
        Config = { Spellcheck = { Enabled = true, Locale = locale, UseNgramIndex = true } },
        Utils = {
            Print = function() end,
            DebugPrint = function() end,
            Deleet = function(word)
                return (word:gsub("0", "o"):gsub("1", "i"):gsub("3", "e")
                    :gsub("4", "a"):gsub("5", "s"):gsub("7", "t")
                    :gsub("%$", "s"):gsub("!", "i"):gsub("%+", "t"))
            end,
        },
    }
    _G.YapperTable = YapperTable

    _G.YapperAPI = {
        RegisterDictionary = function(self, loc, factory)
            dictFactories[loc] = factory
            return true
        end,
        RegisterLanguageEngine = function(self, family, e)
            engines[family] = e
            return true
        end,
    }

    assert(loadfile(engineFile))()
    for _, f in ipairs(dictFiles) do assert(loadfile(f))() end

    local SC = {
        _locale = locale,
        Dictionaries = {},
        DictionaryBuilders = {},
        UserDictCache = {},
        _DICT_CHUNK_SIZE = math.huge, -- force synchronous indexing
        _SCORE_WEIGHTS = {
            prefix = 1, lenDiff = 1, longerPenalty = 1, firstCharBias = 1,
            letterBag = 1, bigram = 1, vowelBonus = 1, kbProximity = 1,
        },
        _RAID_ICONS = {},
        _ed_prev = {}, _ed_cur = {}, _ed_prev_prev = {}, _ed_aBytes = {}, _ed_bBytes = {},
        Clamp = function(v, min, max) return math.min(max, math.max(min, v)) end,
        NormaliseWord = function(s) return (s or ""):lower() end,
        NormaliseVowels = function(s) return (s or ""):lower():gsub("[aeiouy]", "*") end,
        IsWordByte = function(b) return (b >= 97 and b <= 122) or b > 127 end,
        IsWordStartByte = function(b) return (b >= 97 and b <= 122) or (b >= 65 and b <= 90) or b > 127 end,
        SuggestionKey = function(s) return s end,
        Notify = function() end,
        IsDebugEnabled = function() return false end,
        IsEnabled = function() return true end,
        ScheduleRefresh = function() end,
        ClearSuggestionCache = function() end,
        ClearUnderlines = function() end,
        GetLocale = function(self) return self._locale end,
        GetDictionary = function(self) return self.Dictionaries[self._locale] end,
        GetConfig = function(self) return { Locale = self._locale } end,
        GetMaxSuggestions = function() return 6 end,
        GetMaxCandidates = function() return 100 end,
        GetMaxWrongLetters = function() return 4 end,
        GetMinWordLength = function() return 2 end,
        GetReshuffleAttempts = function() return 20 end,
        GetNgramTopCandidates = function() return 500 end,
        GetSuggestionCacheSize = function() return 500 end,
        GetIgnoredRanges = function() return {} end,
        GetUserDict = function() return { AddedWords = {} } end,
        GetUserSets = function() return {}, {} end,
        GetNgramN = function() return 2 end,
        GetNgramMaxPosting = function() return 500 end,
        _NormForLocale = function(self)
            local e = self:_EngineForLocale(self._locale)
            return (e and e.NormaliseWord) or self.NormaliseWord
        end,
        _EngineForLocale = function(self, loc)
            local d = self.Dictionaries and self.Dictionaries[loc]
            local fam = (d and d.languageFamily)
            -- fall back to the only registered family (single-family harnesses)
            if not fam then for k in pairs(engines) do fam = k end end
            return engines[fam]
        end,
        GetEngine = function(self, family) return engines[family] end,
        GetActiveEngine = function(self) return self:_EngineForLocale(self._locale) end,
        _RegisterLanguageEngine = function() end,
        _SafeEngineCall = function(_, eng, name, passSelf, ...)
            local fn = eng and eng[name]
            if type(fn) ~= "function" then return nil end
            if passSelf then return fn(eng, ...) end
            return fn(...)
        end,
        GetBlockData = function(self)
            local e = self:GetActiveEngine()
            return nil, nil, e and e.BlockedHashes, e and e.HashWord
        end,
        IsWordBlocked = function(self, word, loc, ignoreManual)
            local w = self:_NormForLocale(loc)(word)
            local _, _, engineHashes, engineHashFn = self:GetBlockData(loc)
            if engineHashes and engineHashFn then
                if engineHashes[engineHashFn(w)] then return true end
                local dw = w:gsub("0", "o"):gsub("1", "i"):gsub("3", "e")
                    :gsub("4", "a"):gsub("5", "s"):gsub("7", "t")
                    :gsub("%$", "s"):gsub("!", "i"):gsub("%+", "t")
                if engineHashes[engineHashFn(dw)] then return true end
            end
            return false
        end,
        GetKeyboardLayout = function(self)
            local e = self:GetActiveEngine()
            return e and e.DefaultLayout or nil
        end,
        _GetKBDistFromLayouts = function(_, layouts, layoutName)
            local coords = layouts and layouts[layoutName]
            if not coords then return nil end
            local tbl = {}
            for i = 1, 676 do tbl[i] = 99 end
            for c1 = 97, 122 do
                local p1 = coords[string.char(c1)]
                if p1 then
                    for c2 = 97, 122 do
                        local p2 = coords[string.char(c2)]
                        if p2 then
                            local dx, dy = p1[1] - p2[1], p1[2] - p2[2]
                            tbl[(c1 - 97) * 26 + (c2 - 97) + 1] = (dx * dx + dy * dy) ^ 0.5
                        end
                    end
                end
            end
            return tbl
        end,
        GetMeta = function(self, dict, word)
            if type(dict) ~= "table" or type(word) ~= "string" or word == "" then return nil end
            dict._metaCache = dict._metaCache or {}
            local cached = dict._metaCache[word]
            if cached then return cached end
            local bag = {}
            for i = 1, #word do
                local ch = string.byte(word, i)
                bag[ch] = (bag[ch] or 0) + 1
            end
            local bigrams = {}
            if #word >= 2 then
                for i = 1, #word - 1 do
                    local g = word:sub(i, i + 1)
                    bigrams[g] = (bigrams[g] or 0) + 1
                end
            end
            local meta = { len = #word, bag = bag, bigrams = bigrams }
            dict._metaCache[word] = meta
            return meta
        end,
    }
    YapperTable.Spellcheck = SC

    local function LoadFile(path)
        local f = assert(loadfile(path))
        f(YapperName, YapperTable)
    end
    LoadFile("Src/Spellcheck/Dictionary.lua")
    LoadFile("Src/Spellcheck/Engine.lua")

    -- Register every captured dict through the real lifecycle (indexing,
    -- phonetic-posting validation, delta/base metatable wiring).
    for loc, factory in pairs(dictFactories) do
        SC:RegisterDictionary(loc, factory())
    end
    return SC
end

local function suggests(SC, typo)
    local s = SC:GetSuggestions(typo)
    local out = {}
    for i = 1, #s do out[#out + 1] = s[i].value end
    return out
end

local function hasSuggestion(SC, typo, expected)
    for _, v in ipairs(suggests(SC, typo)) do
        if v == expected then return true end
    end
    return false
end

-- ===========================================================================
-- English: enBase + enUS + enGB + enAU share one "en" engine.
-- ===========================================================================

print("== en (enBase/enUS/enGB/enAU) ==")
local SC = buildHarness("Dictionaries/Yapper_Dict_en/Engine.lua", {
    "Dictionaries/Yapper_Dict_en/Dict_enBase.lua",
    "Dictionaries/Yapper_Dict_enUS/Dict_enUS.lua",
    "Dictionaries/Yapper_Dict_enGB/Dict_enGB.lua",
    "Dictionaries/Yapper_Dict_enAU/Dict_enAU.lua",
}, "enUS")

-- Structural sanity: registration actually indexed the data.
local enUS = SC.Dictionaries.enUS
check("enUS dict registered with words", enUS and #enUS.words > 1000)
check("enUS set inherits enBase", enUS and enUS.set["the"] == true)

-- Presence: high-frequency words that must exist everywhere English ships.
-- ("alive" is the regression that motivated this suite — it derived only via
-- upstream affix flags and was absent from every source wordlist.)
for _, w in ipairs({
    "the", "and", "that", "have", "for", "not", "with", "you", "this",
    "but", "his", "from", "they", "say", "will", "one", "all", "would",
    "there", "their", "about", "which", "when", "make", "time", "just",
    "know", "take", "people", "into", "year", "good", "some", "could",
    "alive", "performative", "preformative",
}) do
    check("enUS knows '" .. w .. "'", SC:IsWordCorrect(w) == true)
end

-- Locale-specific spellings resolve on their own dicts.
check("enUS knows 'color'", SC:IsWordCorrect("color") == true)
SC._locale = "enGB"
check("enGB knows 'colour'", SC:IsWordCorrect("colour") == true)
SC._locale = "enAU"
check("enAU knows 'colour'", SC:IsWordCorrect("colour") == true)
SC._locale = "enUS"

-- Affix-derived forms: resolved through the engine's StripAffixes contract,
-- not the flat list (these were enAU-only until the affix rules landed).
for _, w in ipairs({ "conducive", "innovative", "coercive", "cozier",
                     "happier", "blamable", "agreeable" }) do
    check("enUS affix-resolves '" .. w .. "'", SC:IsWordCorrect(w) == true)
end

-- Rejects: plausible-looking non-words must still flag.
for _, w in ipairs({ "zxqwvbnm", "thizzzz", "goable", "teaable" }) do
    check("enUS flags '" .. w .. "'", SC:IsWordCorrect(w) == false)
end

-- Suggestion pipeline against the real dictionary. Entries are
-- { value=..., kind="word"|"split", score=... }.
check("'tihs' suggests 'this'", hasSuggestion(SC, "tihs", "this"))
check("'teh' suggests 'the'", hasSuggestion(SC, "teh", "the"))
check("'doign' suggests 'doing' (reshuffle starvation regression)",
    hasSuggestion(SC, "doign", "doing"))
check("'recieve' suggests 'receive'", hasSuggestion(SC, "recieve", "receive"))

-- Every emitted word suggestion must itself be correct (the learned-
-- candidate invariant — protects against malformed suggestions).
do
    local allCorrect = true
    for _, s in ipairs(SC:GetSuggestions("wierd")) do
        if s.kind == "word" and not SC:IsWordCorrect(s.value) then
            allCorrect = false
            break
        end
    end
    check("'wierd': every word suggestion is itself correct", allCorrect)
end

-- ===========================================================================
-- German: deDE, standalone dict, "de" engine, QWERTZ layout.
-- ===========================================================================

print("== deDE ==")
local SCde = buildHarness("Dictionaries/Yapper_Dict_deDE/Engine.lua", {
    "Dictionaries/Yapper_Dict_deDE/Dict_deDE.lua",
}, "deDE")

local de = SCde.Dictionaries.deDE
check("deDE dict registered with words", de and #de.words > 1000)

for _, w in ipairs({
    "und", "der", "die", "das", "ich", "nicht", "sie", "ist", "mit",
    "auf", "auch", "haben", "kann", "dass", "sich", "werden", "zeit",
    "wenn", "oder", "schon",
}) do
    check("deDE knows '" .. w .. "'", SCde:IsWordCorrect(w) == true)
end

check("deDE flags 'zxqwvbnm'", SCde:IsWordCorrect("zxqwvbnm") == false)

-- QWERTZ-appropriate transpose pairs exercise the reshuffle + scoring path.
check("'udn' suggests 'und'", hasSuggestion(SCde, "udn", "und"))
check("'nihct' suggests 'nicht'", hasSuggestion(SCde, "nihct", "nicht"))

-- ---------------------------------------------------------------------------

if FAILURES > 0 then
    print(("FAILED: %d checks failed"):format(FAILURES))
    os.exit(1)
end
print("SUCCESS: all dictionary smoke checks passed")
