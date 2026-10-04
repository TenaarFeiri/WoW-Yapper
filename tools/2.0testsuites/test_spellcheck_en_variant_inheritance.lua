--[[
    Regression test: English variant inheritance and purge behavior.
]]

local function newHarness()
    _G.C_Timer = {}
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

    local YapperName = "Yapper"
    local YapperTable = {
        Config = { Spellcheck = { Enabled = true, Locale = "enUS" } },
        Utils = { Print = function() end, DebugPrint = function() end },
        Spellcheck = {
            Dictionaries = {},
            DictionaryBuilders = {},
            LocaleAddons = {
                enBase = "Yapper_Dict_en",
                enUS = "Yapper_Dict_enUS",
                enGB = "Yapper_Dict_enGB",
                enAU = "Yapper_Dict_enAU",
                deDE = "Yapper_Dict_deDE",
            },
            KnownLocales = { "enBase", "enUS", "enGB", "enAU", "deDE" },
            _asyncLoaders = {},
            _pendingBuilders = {},
            _pendingLocaleLoads = {},
            _DICT_CHUNK_SIZE = 1000,
            _ed_prev = {},
            _ed_cur = {},
            _ed_prev_prev = {},
            _ed_aBytes = {},
            _ed_bBytes = {},
            Clamp = function(v, min, max) return math.min(max, math.max(min, v)) end,
            NormaliseWord = function(s) return (s or ""):lower():gsub("[%p%c%s]", "") end,
            NormaliseVowels = function(s) return (s or ""):lower():gsub("[aeiouy]", "*") end,
            IsWordStartByte = function(b) return (b >= 97 and b <= 122) or (b >= 65 and b <= 90) or b > 127 end,
            Notify = function() end,
            IsDebugEnabled = function() return false end,
            IsEnabled = function() return true end,
            ScheduleRefresh = function() end,
            ClearSuggestionCache = function() end,
            _NormForLocale = function(_, w) return (w or ""):lower() end,
            _SafeEngineCall = function(_, engine, name, passSelf, ...)
                local fn = engine and engine[name]
                if type(fn) ~= "function" then return nil end
                if passSelf then return fn(engine, ...) end
                return fn(...)
            end,
            ClearUnderlines = function() end,
            GetConfig = function(self) return self._testConfig or { Locale = "enUS" } end,
            GetNgramN = function() return 2 end,
            GetNgramMaxPosting = function() return 500 end,
            GetEngine = function()
                -- Minimal contract-shaped engine: the loader binds
                -- NormaliseWord/NormaliseVowels/WordStartBytes from the
                -- registered family engine, never the active-locale one.
                local bytes = {}
                for b = 65, 90 do bytes[b] = true end
                for b = 97, 122 do bytes[b] = true end
                for b = 128, 255 do bytes[b] = true end
                return {
                    BlockedHashes = {},
                    NormaliseWord = function(w) return (w or ""):lower() end,
                    NormaliseVowels = function(w) return (w or ""):lower():gsub("[aeiouy]", "*") end,
                    WordStartBytes = bytes,
                }
            end,
            _RegisterLanguageEngine = function() end,
            UserDictCache = {},
            SuggestionFrame = nil,
            HintFrame = nil,
        },
    }

    local SC = YapperTable.Spellcheck
    local addonLoaders = {}
    local loadCalls = {}

    _G.C_AddOns = {
        GetAddOnInfo = function(addon) return addon, nil, nil, true, "DEMAND_LOADED" end,
        IsAddOnLoaded = function() return false end,
        LoadAddOn = function(addon)
            loadCalls[#loadCalls + 1] = addon
            local loader = addonLoaders[addon]
            if loader then loader() end
            return true
        end
    }

    -- Runnable from the repo root OR the suite dir (the gating runner cds
    -- into tools/2.0testsuites).
    local function LoadFile(path)
        local f = assert(loadfile(path) or loadfile("../../" .. path))
        f(YapperName, YapperTable)
    end

    LoadFile("Src/Spellcheck/Dictionary.lua")
    LoadFile("Src/Spellcheck/UI.lua")

    return SC, addonLoaders, loadCalls
end

local failures = 0
local function check(name, cond)
    if cond then
        print("[PASS] " .. name)
    else
        print("[FAIL] " .. name)
        failures = failures + 1
    end
end

do
    local SC, addonLoaders, loadCalls = newHarness()
    addonLoaders["Yapper_Dict_en"] = function()
        SC:RegisterDictionary("enBase", { words = { "hello", "world" }, languageFamily = "en", engine = {} })
    end

    SC:RegisterDictionary("enUS", { words = { "color" }, languageFamily = "en", extends = "enBase", isDelta = true })
    local base = SC.Dictionaries["enBase"]
    local us = SC.Dictionaries["enUS"]
    local mt = us and getmetatable(us.set)

    check("Fix 1: EnsureLocale demand-loads the enBase LOD addon", base ~= nil)
    check("Fix 1: enUS set inherits base membership via metatable", mt and mt.__index == base.set)
    check("Fix 1: base words resolve through inherited set", us and us.set["hello"] == true)
    check("Fix 1: enBase addon load was attempted", #loadCalls >= 1 and loadCalls[1] == "Yapper_Dict_en")
end

do
    local SC = newHarness()
    SC:RegisterDictionary("enBase", { words = { "cat" }, languageFamily = "en", engine = {} })
    local basePosting = SC.Dictionaries.enBase.ngramIndex2["*t"]

    SC:RegisterDictionary("enUS", { words = { "dat" }, languageFamily = "en", extends = "enBase", isDelta = true })
    local deltaPosting = SC.Dictionaries.enUS.ngramIndex2["*t"]

    check("N-gram delta posting is local", deltaPosting ~= basePosting and #deltaPosting == 1)
    check("N-gram base posting is not mutated", #basePosting == 1)
end

do
    local SC = newHarness()
    SC._SCORE_WEIGHTS = {
        prefix = 1, lenDiff = 1, longerPenalty = 1, firstCharBias = 1,
        letterBag = 1, bigram = 1, vowelBonus = 1, kbProximity = 1,
    }
    SC._RAID_ICONS = {}
    SC.GetDictionary = function(self) return self.Dictionaries.enUS end
    SC.GetLocale = function() return "enUS" end
    SC.GetMaxSuggestions = function() return 4 end
    SC.GetMaxCandidates = function() return 100 end
    SC.GetMaxWrongLetters = function() return 4 end
    SC.GetMinWordLength = function() return 2 end
    SC.GetReshuffleAttempts = function() return 0 end
    SC.GetNgramTopCandidates = function() return 500 end
    SC.GetSuggestionCacheSize = function() return 500 end
    SC.GetIgnoredRanges = function() return {} end
    SC.GetUserDict = function() return { AddedWords = {} } end
    SC.GetUserSets = function() return {}, {} end
    SC.GetBlockData = function() return nil, nil, nil, nil end
    SC.GetMeta = function(_, _, word)
        local bag = {}
        for i = 1, #word do
            local byte = string.byte(word, i)
            bag[byte] = (bag[byte] or 0) + 1
        end
        return { bag = bag, bigrams = {} }
    end
    SC.GetActiveEngine = function()
        return {
            GetPhoneticHash = function() return "" end,
            NormaliseWord = function(w) return (w or ""):lower() end,
            NormaliseVowels = function(word) return word:gsub("[aeiouy]", "*") end,
        }
    end

    local runtime = {
        Config = { Spellcheck = { UseNgramIndex = true } },
        Spellcheck = SC,
        Utils = { Print = function() end },
    }
    local engineFile = assert(loadfile("Src/Spellcheck/Engine.lua") or loadfile("../../Src/Spellcheck/Engine.lua"))
    engineFile("Yapper", runtime)

    SC:RegisterDictionary("enBase", { words = { "cat" }, languageFamily = "en", engine = {} })
    SC:RegisterDictionary("enUS", { words = { "dat" }, languageFamily = "en", extends = "enBase", isDelta = true })

    local suggestions = SC:GetSuggestions("bat")
    local foundBase = false
    for _, suggestion in ipairs(suggestions) do
        if suggestion.kind == "word" and suggestion.value == "cat" then
            foundBase = true
            break
        end
    end
    check("N-gram suggestions retain base candidates", foundBase)
end

do
    -- Phonetic-index contract: delta postings are LOCAL indices into the
    -- delta's own words array, and a hash shared with the base must union
    -- both layers' postings (not shadow them).
    local SC = newHarness()
    SC._SCORE_WEIGHTS = {
        prefix = 1, lenDiff = 1, longerPenalty = 1, firstCharBias = 1,
        letterBag = 1, bigram = 1, vowelBonus = 1, kbProximity = 1,
    }
    SC._RAID_ICONS = {}
    SC.GetDictionary = function(self) return self.Dictionaries.enUS end
    SC.GetLocale = function() return "enUS" end
    SC.GetMaxSuggestions = function() return 4 end
    SC.GetMaxCandidates = function() return 100 end
    SC.GetMaxWrongLetters = function() return 4 end
    SC.GetMinWordLength = function() return 2 end
    SC.GetReshuffleAttempts = function() return 0 end
    SC.GetNgramTopCandidates = function() return 500 end
    SC.GetSuggestionCacheSize = function() return 500 end
    SC.GetIgnoredRanges = function() return {} end
    SC.GetUserDict = function() return { AddedWords = {} } end
    SC.GetUserSets = function() return {}, {} end
    SC.GetBlockData = function() return nil, nil, nil, nil end
    SC.GetMeta = function(_, _, word)
        local bag = {}
        for i = 1, #word do
            local byte = string.byte(word, i)
            bag[byte] = (bag[byte] or 0) + 1
        end
        return { bag = bag, bigrams = {} }
    end
    -- Phonetic stub: "cat", "dat", "kat" all collapse to hash "H".
    SC.GetActiveEngine = function()
        return {
            GetPhoneticHash = function(w)
                if w == "cat" or w == "dat" or w == "kat" then return "H" end
                return ""
            end,
            NormaliseVowels = function(word) return word:gsub("[aeiouy]", "*") end,
            NormaliseWord = function(w) return (w or ""):lower() end,
        }
    end

    local runtime = {
        Config = { Spellcheck = {} },
        Spellcheck = SC,
        Utils = { Print = function() end },
    }
    assert(loadfile("Src/Spellcheck/Engine.lua") or loadfile("../../Src/Spellcheck/Engine.lua"))("Yapper", runtime)

    SC:RegisterDictionary("enBase", {
        words = { "cat" }, phonetics = { H = { 1 } },
        languageFamily = "en", engine = {},
    })
    SC:RegisterDictionary("enUS", {
        words = { "dat" }, phonetics = { H = { 1 } }, -- local id 1 = "dat"
        languageFamily = "en", extends = "enBase", isDelta = true,
    })

    -- Delta posting id 1 must resolve to the delta's own word, not the base's.
    local us = SC.Dictionaries.enUS
    check("Phonetic: delta posting resolves locally", rawget(us.words, 1) == "dat")

    local suggestions = SC:GetSuggestions("kat")
    local foundCat, foundDat = false, false
    for _, suggestion in ipairs(suggestions) do
        if suggestion.kind == "word" then
            if suggestion.value == "cat" then foundCat = true end
            if suggestion.value == "dat" then foundDat = true end
        end
    end
    check("Phonetic: delta phonetic candidate found", foundDat)
    check("Phonetic: shared hash unions base candidates", foundCat)
end

do
    -- Contract: out-of-range / non-integer / non-array phonetic postings
    -- reject the dictionary outright rather than silently degrading.
    local SC = newHarness()
    SC:RegisterDictionary("enBase", {
        words = { "cat" }, phonetics = { H = { 2 } }, -- only 1 word exists
        languageFamily = "en", engine = {},
    })
    check("Phonetic: out-of-range posting rejects dict", SC.Dictionaries.enBase == nil)

    SC:RegisterDictionary("enBase", {
        words = { "cat" }, phonetics = { H = { 1.5 } },
        languageFamily = "en", engine = {},
    })
    check("Phonetic: non-integer posting rejects dict", SC.Dictionaries.enBase == nil)

    SC:RegisterDictionary("enBase", {
        words = { "cat" }, phonetics = { H = "cat" },
        languageFamily = "en", engine = {},
    })
    check("Phonetic: non-array posting rejects dict", SC.Dictionaries.enBase == nil)

    SC:RegisterDictionary("enBase", {
        words = { "cat" }, phonetics = { H = { 1 } },
        languageFamily = "en", engine = {},
    })
    check("Phonetic: in-range posting registers", SC.Dictionaries.enBase ~= nil)
end

do
    -- Regression: the reshuffle budget used to cap ALL generated variants,
    -- so for "doign" only the first three transpositions (odign, diogn,
    -- dogin) were tried and "doing" (swap at position 4) never existed.
    -- Mechanical slips (all transposes + all deletions) are bounded by
    -- word length and must always be covered; the configured budget
    -- applies to the substitution sweep on top.
    local SC = newHarness()
    SC._SCORE_WEIGHTS = {
        prefix = 1, lenDiff = 1, longerPenalty = 1, firstCharBias = 1,
        letterBag = 1, bigram = 1, vowelBonus = 1, kbProximity = 1,
    }
    SC._RAID_ICONS = {}
    SC.GetDictionary = function(self) return self.Dictionaries.enUS end
    SC.GetLocale = function() return "enUS" end
    SC.GetMaxSuggestions = function() return 10 end
    SC.GetMaxCandidates = function() return 100 end
    SC.GetMaxWrongLetters = function() return 4 end
    SC.GetMinWordLength = function() return 2 end
    SC.GetReshuffleAttempts = function() return 3 end
    SC.GetNgramTopCandidates = function() return 500 end
    SC.GetSuggestionCacheSize = function() return 500 end
    SC.GetIgnoredRanges = function() return {} end
    SC.GetUserDict = function() return { AddedWords = {} } end
    SC.GetUserSets = function() return {}, {} end
    SC.GetBlockData = function() return nil, nil, nil, nil end
    SC.GetMeta = function(_, _, word)
        local bag = {}
        for i = 1, #word do
            local byte = string.byte(word, i)
            bag[byte] = (bag[byte] or 0) + 1
        end
        return { bag = bag, bigrams = {} }
    end
    SC.GetActiveEngine = function()
        return {
            GetPhoneticHash = function() return "" end,
            NormaliseWord = function(w) return (w or ""):lower() end,
            NormaliseVowels = function(word) return word:gsub("[aeiouy]", "*") end,
        }
    end

    local runtime = {
        Config = { Spellcheck = { UseNgramIndex = true } },
        Spellcheck = SC,
        Utils = { Print = function() end },
    }
    local engineFile = assert(loadfile("Src/Spellcheck/Engine.lua") or loadfile("../../Src/Spellcheck/Engine.lua"))
    engineFile("Yapper", runtime)

    SC:RegisterDictionary("enUS", {
        words = { "doing", "deign", "dog", "dig", "don", "dozing" },
        languageFamily = "en", engine = {},
    })

    local suggestions = SC:GetSuggestions("doign")
    local foundDoing = false
    for _, suggestion in ipairs(suggestions) do
        if suggestion.kind == "word" and suggestion.value == "doing" then
            foundDoing = true
            break
        end
    end
    check("Reshuffle: late transposition candidate generated", foundDoing)
end

do
    -- Regression: YAS bias targets are stored Clean()ed (punctuation
    -- stripped), so a learned correction "i'm" resurfaces as "im", and
    -- non-dictionary corrections can linger in db.bias.  Emitting those
    -- verbatim produced suggestions that still flagged once applied —
    -- the user picked "the option underneath the split" and had to add
    -- the word manually.  Learned candidates must clear IsWordCorrect
    -- before entering the pool.
    local SC = newHarness()
    SC._SCORE_WEIGHTS = {
        prefix = 1, lenDiff = 1, longerPenalty = 1, firstCharBias = 1,
        letterBag = 1, bigram = 1, vowelBonus = 1, kbProximity = 1,
    }
    SC._RAID_ICONS = {}
    SC.GetDictionary = function(self) return self.Dictionaries.enUS end
    SC.GetLocale = function() return "enUS" end
    SC.GetMaxSuggestions = function() return 10 end
    SC.GetMaxCandidates = function() return 100 end
    SC.GetMaxWrongLetters = function() return 4 end
    SC.GetMinWordLength = function() return 2 end
    SC.GetReshuffleAttempts = function() return 0 end
    SC.GetNgramTopCandidates = function() return 500 end
    SC.GetSuggestionCacheSize = function() return 500 end
    SC.GetIgnoredRanges = function() return {} end
    SC.GetUserDict = function() return { AddedWords = {} } end
    SC.GetUserSets = function() return {}, {} end
    SC.GetBlockData = function() return nil, nil, nil, nil end
    SC.IsWordBlocked = function() return false end
    SC.GetMeta = function(_, _, word)
        local bag = {}
        for i = 1, #word do
            local byte = string.byte(word, i)
            bag[byte] = (bag[byte] or 0) + 1
        end
        return { bag = bag, bigrams = {} }
    end
    SC.GetActiveEngine = function()
        return {
            GetPhoneticHash = function() return "" end,
            NormaliseWord = function(w) return (w or ""):lower() end,
            NormaliseVowels = function(word) return word:gsub("[aeiouy]", "*") end,
        }
    end
    -- Bias targets: "im" is the Cleaned husk of a learned "i'm" (not in
    -- the set); "cat" is a real dictionary word.
    SC.YAS = {
        GetBiasTargets = function() return { "im", "cat" } end,
        GetLocaleDB = function() return nil end,
    }

    local runtime = {
        Config = { Spellcheck = {} },
        Spellcheck = SC,
        Utils = { Print = function() end },
    }
    assert(loadfile("Src/Spellcheck/Engine.lua") or loadfile("../../Src/Spellcheck/Engine.lua"))("Yapper", runtime)

    SC:RegisterDictionary("enUS", {
        words = { "cat", "cta", "i'm", "tired" },
        languageFamily = "en", engine = {},
    })

    local suggestions = SC:GetSuggestions("cta")
    local foundCat, foundIm = false, false
    for _, s in ipairs(suggestions) do
        if s.kind == "word" then
            if s.value == "cat" then foundCat = true end
            if s.value == "im" then foundIm = true end
        end
    end
    check("Learned: dictionary target still suggested", foundCat)
    check("Learned: unrecognised Cleaned target filtered", not foundIm)

    -- Invariant: every emitted word suggestion must pass IsWordCorrect —
    -- a suggestion that still flags after application is worse than none.
    local allCorrect = true
    for _, s in ipairs(suggestions) do
        if s.kind == "word" and not SC:IsWordCorrect(s.value) then
            allCorrect = false
        end
    end
    check("Learned: every word suggestion passes IsWordCorrect", allCorrect)

    -- User scenario: split entry above, the flagged word itself offered
    -- underneath (a stale phBias/bias target matching the input).  Picking
    -- it changed nothing and still flagged.  "cattired" splits into
    -- "cat tired"; "cattired" also arrives as a learned target.
    SC.YAS.GetBiasTargets = function() return { "im", "cattired" } end
    suggestions = SC:GetSuggestions("cattired")
    local foundSplit, foundSelf = false, false
    for _, s in ipairs(suggestions) do
        if s.kind == "split" and s.value == "cat tired" then foundSplit = true end
        if s.kind == "word" and s.value == "cattired" then foundSelf = true end
        if s.kind == "word" and s.value == "im" then foundIm = true end
    end
    check("Learned: split suggestion emitted above words", foundSplit)
    check("Learned: flagged word not re-offered as its own correction", not foundSelf)
    check("Learned: Cleaned husk still filtered under split", not foundIm)
end

if failures > 0 then
    print(("FAILED: %d checks failed"):format(failures))
    os.exit(1)
end
print("SUCCESS: all regression checks passed")
