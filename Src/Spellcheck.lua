--[[
    Spellcheck.lua
    Lightweight spellcheck for the overlay editbox.

    Uses packaged dictionary tables registered at load time.
]]

local _, YapperTable = ...

local Spellcheck = {}
YapperTable.Spellcheck = Spellcheck
local Utils = YapperTable.Utils

-- Localise Lua globals for performance (avoids table lookups in hot loops)
local math_min   = math.min
local math_max   = math.max
local math_abs   = math.abs
local table_remove = table.remove
local table_sort = table.sort
local pcall = pcall
local string_sub = string.sub
local string_byte = string.byte
local string_lower = string.lower
local string_gsub = string.gsub
local string_char = string.char
local type = type
local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local tonumber = tonumber
local select = select

local function IsDebugEnabled()
    return YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG
end

Spellcheck.Dictionaries    = {}
Spellcheck.LanguageEngines = {} -- [familyId] = engine table
Spellcheck.KnownLocales = {
    "enUS",
    "enGB",
    "enAU",
    "deDE",
}
-- LOD addon names for each locale. enBase is the shared English base that
-- both enGB and enUS depend on; it is pre-loaded whenever the user's locale
-- is any English variant. Non-English addon names are left empty for now
-- and will be populated as those addons are written.
Spellcheck.LocaleAddons = {
    enBase = "Yapper_Dict_en",
    enGB   = "Yapper_Dict_enGB",
    enUS   = "Yapper_Dict_enUS",
    enAU   = "Yapper_Dict_enAU",
    deDE   = "Yapper_Dict_deDE",
}
Spellcheck.EditBox = nil
Spellcheck.Overlay = nil
Spellcheck.MeasureFS = nil
Spellcheck.SuggestionFrame = nil
Spellcheck.SuggestionRows = {}
Spellcheck.ActiveSuggestions = nil
Spellcheck.ActiveIndex = 1
Spellcheck.ActiveWord = nil
Spellcheck.ActiveRange = nil
Spellcheck.HintFrame = nil
Spellcheck._hintOffsetX = 0
Spellcheck._hintOffsetY = -2
Spellcheck._suggestOffsetX = 0
Spellcheck._suggestOffsetY = 4
Spellcheck._debounceTimer = nil
Spellcheck.UserDictCache = {}
Spellcheck._pendingLocaleLoads = {}
Spellcheck._failedLocaleLoads = {}
Spellcheck.DictionaryBuilders = {}
-- Reusable buffers for EditDistance to avoid per-call allocations
Spellcheck._ed_prev = {}
Spellcheck._ed_cur = {}
Spellcheck._ed_prev_prev = {}

local MAX_SUGGESTION_ROWS = 6
local SCORE_WEIGHTS = {
    lenDiff       = 3.0,
    longerPenalty = 2.0,
    prefix        = 1.5,
    letterBag     = 1.0,
    bigram        = 1.5,
    kbProximity   = 1.0, -- Multiplier for adjacency bonus
    firstCharBias = 1.5, -- New weight for first-character anchor
    vowelBonus    = 2.5, -- New weight for vowel-neutral similarity
}

local RAID_ICONS = {
    "{Star}", "{Circle}", "{Diamond}", "{Triangle}",
    "{Moon}", "{Square}", "{Cross}", "{X}", "{Skull}", "{Coin}"
}

-- ---------------------------------------------------------------------------
-- Language helpers (engine delegates + neutral fallbacks)
-- ---------------------------------------------------------------------------
-- Every language-affecting helper below dispatches to the ACTIVE locale's
-- registered engine.  The fallbacks exist solely for the window before a
-- dictionary addon loads, when spellcheck is inert anyway.  There is no
-- silent English fallback for a registered family: if a family has no
-- engine, its dictionaries cannot register at all.

local function NormaliseWord(word)
    if type(word) ~= "string" then return "" end
    return string_lower(word)
end

-- Best-effort fallback for the no-engine window only.
local function NormaliseVowels(word)
    if type(word) ~= "string" then return "" end
    return string_gsub(string_lower(word), "[aeiouy]", "*")
end

--- Engine-delegating canonicaliser for the active locale (dot-call).
Spellcheck.NormaliseWord = function(word)
    local e = Spellcheck:GetActiveEngine()
    if e then return e.NormaliseWord(word) end
    return NormaliseWord(word)
end

--- Engine-delegating vowel normaliser for the active locale (dot-call).
Spellcheck.NormaliseVowels = function(word)
    local e = Spellcheck:GetActiveEngine()
    if e then return e.NormaliseVowels(word) end
    return NormaliseVowels(word)
end

--- Engine-delegating phonetic hash for the active locale (dot-call).
--- Returns "" when no engine is active or the engine call fails.
Spellcheck.GetPhoneticHash = function(word)
    local e = Spellcheck:GetActiveEngine()
    if not e then return "" end
    local r = Spellcheck:_SafeEngineCall(e, "GetPhoneticHash", false, word)
    return type(r) == "string" and r or ""
end

-- Neutral word-byte fallback sets (used only when no engine is active).
-- Language-specific tokenisation is owned by engine.WordBytes /
-- engine.WordStartBytes; '{' (123) is always a start byte regardless of
-- engine, since raid-icon tokens are a Yapper feature.
local FALLBACK_WORD_BYTES = {}
local FALLBACK_WORD_START = {}
for b = 65, 90 do
    FALLBACK_WORD_BYTES[b] = true
    FALLBACK_WORD_START[b] = true
end
for b = 97, 122 do
    FALLBACK_WORD_BYTES[b] = true
    FALLBACK_WORD_START[b] = true
end
for b = 128, 255 do FALLBACK_WORD_BYTES[b] = true end
FALLBACK_WORD_BYTES[39] = true -- apostrophe
FALLBACK_WORD_START[123] = true -- '{'

local function WordBytesFor(engine)
    return (engine and engine.WordBytes) or FALLBACK_WORD_BYTES
end

local function WordStartBytesFor(engine)
    return (engine and engine.WordStartBytes) or FALLBACK_WORD_START
end

--- Dot-call byte predicates kept for external/UI callers.  Hot paths use the
--- engine's byte sets directly via IterWords.
Spellcheck.IsWordByte = function(byte)
    return WordBytesFor(Spellcheck:GetActiveEngine())[byte] == true
end

Spellcheck.IsWordStartByte = function(byte)
    return WordStartBytesFor(Spellcheck:GetActiveEngine())[byte] == true
end

-- ---------------------------------------------------------------------------
-- Keyboard layout distance tables
-- ---------------------------------------------------------------------------
-- Layouts are engine data (KBLayouts + DefaultLayout); core only builds and
-- caches the distance mechanics.  The cache is bounded and wiped whenever an
-- engine is (re)registered or purged.
local _kbDistCache = {}
local KB_DIST_CACHE_CAP = 16

-- Build a flat 676-entry distance lookup indexed by (b1-97)*26 + (b2-97) + 1
-- where b1,b2 are byte values of lowercase a-z. Called once per layout change.
local function BuildKBDistTable(coords)
    local tbl = {}
    -- Pre-fill with a large sentinel so missing keys return high distance
    for i = 1, 676 do tbl[i] = 99 end
    for ch1 = 97, 122 do
        local c1 = coords[string_char(ch1)]
        if c1 then
            for ch2 = 97, 122 do
                local c2 = coords[string_char(ch2)]
                if c2 then
                    local dx = c1[1] - c2[1]
                    local dy = c1[2] - c2[2]
                    -- Euclidean distance; table is built once so sqrt here
                    -- is fine.
                    local d = (dx * dx + dy * dy) ^ 0.5
                    tbl[(ch1 - 97) * 26 + (ch2 - 97) + 1] = d
                end
            end
        end
    end
    return tbl
end

function Spellcheck:Init()
    -- Ensure distance buffers are pre-allocated to avoid first-run stalls/nils
    if not self._ed_prev then self._ed_prev = {} end
    if not self._ed_cur then self._ed_cur = {} end
    if not self._ed_prev_prev then self._ed_prev_prev = {} end

    -- Ensure YAS is initialized and hooks its SavedVariables
    if self.YAS and self.YAS.Init then
        self.YAS:Init()
    end

    self:ApplyState()
end

-- ---------------------------------------------------------------------------
-- Language Engine Registry
-- ---------------------------------------------------------------------------
-- Core owns mechanics only: edit-distance scoring, suggestion ranking,
-- caching, YAS feedback and dictionary lifecycle.  All language judgement is
-- owned by the registered engine contract:
--
--   REQUIRED
--     GetPhoneticHash(word) -> string   phonetic index key; "" = unmappable
--     NormaliseWord(word)   -> string   canonical lookup form; MUST be
--                                     idempotent (f(f(w)) == f(w))
--     NormaliseVowels(word) -> string   vowel-neutral form; vowels -> "*"
--     HashWord(word)        -> number   uint32 blocklist hash
--     BlockedHashes         table       [hash] = true; mandatory security data
--     WordBytes             table       [byte] = true; word-continuation bytes
--     WordStartBytes        table       [byte] = true; word-start bytes
--
--   OPTIONAL
--     StripAffixes(engine, word, dict) -> string|nil
--     ShouldCheckWord(word, minLen)    -> boolean
--     MatchCase(input, suggestion)     -> string   casing mirror for results
--     IsSaneWord(word)                 -> boolean  extra YAS learning veto
--     HasVariantRules + VariantRules   { {from, to}, ... } spelling variants
--     ScoreWeights                     subset of SCORE_WEIGHTS keys, numeric
--     KBLayouts + DefaultLayout        { NAME = { char = {x, y} } }
--     Locales                          { "enUS", ... } served by this family
--     DisplayName                      string
--     Autocorrect                      { SplitCompounds?, ConfusionPairs?,
--                                        AutocorrectVeto?, MaxConfidence? }
--                                      language-specific knowledge for the
--                                      (future) autocorrect tier; validated
--                                      now so a malformed table fails fast
--
-- Strict contract: unknown top-level keys, wrong types, failed probes or
-- over-limit tables are all rejected at registration.  A runtime error inside
-- engine code purges the engine AND every dictionary bound to its family.

local ENGINE_LIMITS = {
    MaxVariantRules   = 64,
    MaxRuleLength     = 32,
    MaxKBLayouts      = 16,
    MaxKBLayoutKeys   = 256,
    MaxKBCoord        = 64,
    MaxBlockedHashes  = 250000,
    MaxLocales        = 64,
    MaxDisplayNameLen = 64,
    MaxWordLength     = 256,
    MaxPhoneticLen    = 128,
    MaxConfusionPairs = 256,
    MaxSplitParts     = 8,
}

local ENGINE_REQUIRED = {
    GetPhoneticHash = "function",
    NormaliseWord   = "function",
    NormaliseVowels = "function",
    HashWord        = "function",
    BlockedHashes   = "table",
    WordBytes       = "table",
    WordStartBytes  = "table",
}

local ENGINE_OPTIONAL = {
    StripAffixes    = "function",
    ShouldCheckWord = "function",
    MatchCase       = "function",
    IsSaneWord      = "function",
    HasVariantRules = "boolean",
    VariantRules    = "table",
    ScoreWeights    = "table",
    KBLayouts       = "table",
    DefaultLayout   = "string",
    Locales         = "table",
    DisplayName     = "string",
    Autocorrect     = "table",
}

-- Whitelist for engine.Autocorrect sub-fields (all optional).
local ENGINE_AUTOCORRECT_FIELDS = {
    SplitCompounds   = "function",  -- word -> {w1, w2, ...}|nil (compound split)
    ConfusionPairs   = "table",     -- { ["a>b"] = count, ... } seeds errProfile.conf
    AutocorrectVeto  = "function",  -- (word, suggestion) -> boolean
    MaxConfidence    = "number",    -- 0..1 ceiling on endorsed confidence
}

-- Probe inputs used to exercise engine functions at registration time.
local ENGINE_PROBES = { "hello", "Don't", "Straße", "a" }

local function _IsByteSet(tbl)
    if type(tbl) ~= "table" then return false, "not a table" end
    for k, v in pairs(tbl) do
        if type(k) ~= "number" or k < 0 or k > 255 or k % 1 ~= 0 then
            return false, "non-byte key " .. tostring(k)
        end
        if v ~= true then
            return false, "non-boolean value for byte " .. tostring(k)
        end
    end
    return true
end

--- Validate an engine table against the contract.
--- @return boolean ok, string|nil err
function Spellcheck:_ValidateEngineContract(familyId, engine)
    -- 1. Whitelist + type check.
    for key, value in pairs(engine) do
        if type(key) == "string" and (key:sub(1, 2) == "X_" or key:sub(1, 1) == "_") then
            -- X_ = vendor-extension prefix; _ = core-internal bookkeeping
            -- (registration stamps _localesSet onto the live engine table)
        else
            local want = ENGINE_REQUIRED[key] or ENGINE_OPTIONAL[key]
            if not want then
                return false, "unknown contract field '" .. tostring(key) .. "'"
            end
            if type(value) ~= want then
                return false, "field '" .. key .. "' must be " .. want .. ", got " .. type(value)
            end
        end
    end

    -- 2. Required fields present.
    for key, want in pairs(ENGINE_REQUIRED) do
        if type(engine[key]) ~= want then
            if key == "BlockedHashes" or key == "HashWord" then
                return false, "missing mandatory security data (" .. key .. ")"
            end
            return false, "missing required field '" .. key .. "'"
        end
    end

    -- 3. Function probes: required functions must not error and must return
    --    sane types on representative inputs.
    for _, w in ipairs(ENGINE_PROBES) do
        local ok, r = pcall(engine.NormaliseWord, w)
        if not ok then return false, "NormaliseWord errored: " .. tostring(r) end
        if type(r) ~= "string" then return false, "NormaliseWord returned " .. type(r) end
        if #r > ENGINE_LIMITS.MaxWordLength then return false, "NormaliseWord output exceeds cap" end
        local ok2, r2 = pcall(engine.NormaliseWord, r)
        if not ok2 or r2 ~= r then
            return false, "NormaliseWord is not idempotent on '" .. w .. "'"
        end

        ok, r = pcall(engine.NormaliseVowels, w)
        if not ok then return false, "NormaliseVowels errored: " .. tostring(r) end
        if type(r) ~= "string" or #r > ENGINE_LIMITS.MaxWordLength then
            return false, "NormaliseVowels returned bad value"
        end

        ok, r = pcall(engine.GetPhoneticHash, w)
        if not ok then return false, "GetPhoneticHash errored: " .. tostring(r) end
        if type(r) ~= "string" or #r > ENGINE_LIMITS.MaxPhoneticLen then
            return false, "GetPhoneticHash returned bad value"
        end

        ok, r = pcall(engine.HashWord, w)
        if not ok then return false, "HashWord errored: " .. tostring(r) end
        if type(r) ~= "number" or r < 0 or r >= 4294967296 or r % 1 ~= 0 then
            return false, "HashWord must return a uint32 integer"
        end
    end

    -- 4. BlockedHashes: numeric keys only, bounded.
    local count = 0
    for k in pairs(engine.BlockedHashes) do
        if type(k) ~= "number" then
            return false, "BlockedHashes key " .. tostring(k) .. " is not a number"
        end
        count = count + 1
        if count > ENGINE_LIMITS.MaxBlockedHashes then
            return false, "BlockedHashes exceeds cap (" .. ENGINE_LIMITS.MaxBlockedHashes .. ")"
        end
    end

    -- 5. Tokenisation byte sets.
    local ok, err = _IsByteSet(engine.WordBytes)
    if not ok then return false, "WordBytes: " .. err end
    ok, err = _IsByteSet(engine.WordStartBytes)
    if not ok then return false, "WordStartBytes: " .. err end

    -- 6. Optional fields.
    if engine.VariantRules then
        if engine.HasVariantRules ~= true then
            return false, "VariantRules present but HasVariantRules is not true"
        end
        if #engine.VariantRules > ENGINE_LIMITS.MaxVariantRules then
            return false, "VariantRules exceeds cap (" .. ENGINE_LIMITS.MaxVariantRules .. ")"
        end
        for i, rule in ipairs(engine.VariantRules) do
            if type(rule) ~= "table" or type(rule[1]) ~= "string" or type(rule[2]) ~= "string"
                or rule[1] == "" or rule[1] == rule[2]
                or #rule[1] > ENGINE_LIMITS.MaxRuleLength
                or #rule[2] > ENGINE_LIMITS.MaxRuleLength then
                return false, "VariantRules[" .. i .. "] malformed"
            end
        end
    end

    if engine.ScoreWeights then
        for k, v in pairs(engine.ScoreWeights) do
            if type(SCORE_WEIGHTS[k]) ~= "number" then
                return false, "ScoreWeights key '" .. tostring(k) .. "' is not a known weight"
            end
            if type(v) ~= "number" or v ~= v or math_abs(v) > 1000 then
                return false, "ScoreWeights['" .. tostring(k) .. "'] must be a finite number |v|<=1000"
            end
        end
    end

    if engine.KBLayouts then
        local layoutCount = 0
        for name, layout in pairs(engine.KBLayouts) do
            layoutCount = layoutCount + 1
            if layoutCount > ENGINE_LIMITS.MaxKBLayouts then
                return false, "KBLayouts exceeds cap (" .. ENGINE_LIMITS.MaxKBLayouts .. ")"
            end
            if type(name) ~= "string" or name == "" or #name > 32 then
                return false, "KBLayouts has a malformed layout name"
            end
            if type(layout) ~= "table" then
                return false, "KBLayouts['" .. name .. "'] is not a table"
            end
            local keyCount = 0
            for ch, coord in pairs(layout) do
                keyCount = keyCount + 1
                if keyCount > ENGINE_LIMITS.MaxKBLayoutKeys then
                    return false, "KBLayouts['" .. name .. "'] exceeds key cap"
                end
                if type(ch) ~= "string" or #ch == 0 or #ch > 4 then
                    return false, "KBLayouts['" .. name .. "'] has a malformed key"
                end
                if type(coord) ~= "table" or type(coord[1]) ~= "number" or type(coord[2]) ~= "number"
                    or math_abs(coord[1]) > ENGINE_LIMITS.MaxKBCoord
                    or math_abs(coord[2]) > ENGINE_LIMITS.MaxKBCoord then
                    return false, "KBLayouts['" .. name .. "']['" .. ch .. "'] must be {x, y} numbers"
                end
            end
        end
        if engine.DefaultLayout ~= nil and type(engine.KBLayouts[engine.DefaultLayout]) ~= "table" then
            return false, "DefaultLayout '" .. tostring(engine.DefaultLayout) .. "' is not in KBLayouts"
        end
    elseif engine.DefaultLayout ~= nil then
        return false, "DefaultLayout declared without KBLayouts"
    end

    if engine.Locales then
        if #engine.Locales > ENGINE_LIMITS.MaxLocales then
            return false, "Locales exceeds cap (" .. ENGINE_LIMITS.MaxLocales .. ")"
        end
        for _, l in ipairs(engine.Locales) do
            if type(l) ~= "string" or l == "" or #l > 32 then
                return false, "Locales contains a malformed locale id"
            end
        end
    end

    if engine.DisplayName and #engine.DisplayName > ENGINE_LIMITS.MaxDisplayNameLen then
        return false, "DisplayName exceeds cap"
    end

    if engine.Autocorrect then
        local ac = engine.Autocorrect
        for k, v in pairs(ac) do
            local want = ENGINE_AUTOCORRECT_FIELDS[k]
            if not want then
                return false, "Autocorrect: unknown field '" .. tostring(k) .. "'"
            end
            if type(v) ~= want then
                return false, "Autocorrect." .. k .. " must be " .. want .. ", got " .. type(v)
            end
        end
        if ac.MaxConfidence ~= nil then
            if ac.MaxConfidence ~= ac.MaxConfidence
                or ac.MaxConfidence < 0 or ac.MaxConfidence > 1 then
                return false, "Autocorrect.MaxConfidence must be in [0, 1]"
            end
        end
        if ac.ConfusionPairs then
            local n = 0
            for k, v in pairs(ac.ConfusionPairs) do
                n = n + 1
                if n > ENGINE_LIMITS.MaxConfusionPairs then
                    return false, "Autocorrect.ConfusionPairs exceeds cap"
                end
                if type(k) ~= "string" or #k ~= 3 or k:sub(2, 2) ~= ">" then
                    return false, "Autocorrect.ConfusionPairs key '" .. tostring(k)
                        .. "' must look like 'a>b'"
                end
                if type(v) ~= "number" or v ~= v or v < 0 or v > 10000 then
                    return false, "Autocorrect.ConfusionPairs['" .. tostring(k) .. "'] bad count"
                end
            end
        end
        if ac.SplitCompounds then
            local ok, r = pcall(ac.SplitCompounds, "testword")
            if not ok then
                return false, "Autocorrect.SplitCompounds errored on probe: " .. tostring(r)
            end
            if r ~= nil then
                if type(r) ~= "table" or #r < 2 or #r > ENGINE_LIMITS.MaxSplitParts then
                    return false, "Autocorrect.SplitCompounds must return nil or 2-"
                        .. ENGINE_LIMITS.MaxSplitParts .. " strings"
                end
                for i, w in ipairs(r) do
                    if type(w) ~= "string" or w == "" or #w > ENGINE_LIMITS.MaxWordLength then
                        return false, "Autocorrect.SplitCompounds returned bad part #" .. i
                    end
                end
            end
        end
        if ac.AutocorrectVeto then
            local ok, r = pcall(ac.AutocorrectVeto, "test", "tests")
            if not ok or type(r) ~= "boolean" then
                return false, "Autocorrect.AutocorrectVeto must return a boolean"
            end
        end
    end

    -- 7. Optional function probes.
    if engine.StripAffixes then
        local fakeDict = { set = {}, Contains = function() return false end }
        local ok, r = pcall(engine.StripAffixes, engine, "testing", fakeDict)
        if not ok then return false, "StripAffixes errored on probe: " .. tostring(r) end
        if r ~= nil and type(r) ~= "string" then
            return false, "StripAffixes must return string or nil"
        end
    end
    if engine.ShouldCheckWord then
        local ok, r = pcall(engine.ShouldCheckWord, "test", 2)
        if not ok or type(r) ~= "boolean" then
            return false, "ShouldCheckWord must return a boolean"
        end
    end
    if engine.MatchCase then
        local ok, r = pcall(engine.MatchCase, "Test", "case")
        if not ok or type(r) ~= "string" then
            return false, "MatchCase must return a string"
        end
    end
    if engine.IsSaneWord then
        local ok, r = pcall(engine.IsSaneWord, "test")
        if not ok or type(r) ~= "boolean" then
            return false, "IsSaneWord must return a boolean"
        end
    end

    return true
end

--- Internal: register a language engine for a given family id.
--- Called by API:RegisterLanguageEngine (the public surface) and by
--- RegisterDictionary when a data bundle carries an embedded engine.
--- @param familyId string e.g. "en", "de"
--- @param engine   table  the engine contract table
--- @param owner    string|nil  addon folder that registered it (owner lock)
--- @return boolean true if accepted
function Spellcheck:_RegisterLanguageEngine(familyId, engine, owner)
    if type(familyId) ~= "string" or familyId == "" then return false end
    if type(engine) ~= "table" then return false end

    self.LanguageEngines = self.LanguageEngines or {}
    self._engineOwners   = self._engineOwners or {}
    self._engineFamily   = self._engineFamily or {}
    self._failedEngines  = self._failedEngines or {}

    -- Owner lock: a family belongs to the addon that first registered it.
    -- Unknown-owner registrations (internal paths, test rigs) are always
    -- allowed; a known different owner is rejected.
    local existing = self._engineOwners[familyId]
    if existing and owner and existing ~= owner then
        self:Notify("|cffff0000Yapper Error:|r Language engine '" .. familyId ..
            "' is owned by " .. tostring(existing) .. "; registration from " ..
            tostring(owner) .. " rejected.")
        return false
    end

    -- Strip submitted `_`-prefixed fields: the validator tolerates them so a
    -- previously-registered engine re-validates, but a submission must never
    -- forge internal bookkeeping (e.g. a fake _localesSet would hijack
    -- locale→family resolution).
    for k in pairs(engine) do
        if type(k) == "string" and k:sub(1, 1) == "_" then
            engine[k] = nil
        end
    end

    local ok, err = self:_ValidateEngineContract(familyId, engine)
    if not ok then
        self._failedEngines[familyId] = err
        self:Notify("|cffff0000Yapper Error:|r Language engine '" .. familyId ..
            "' failed contract validation: " .. tostring(err))
        return false
    end

    -- '{' is always a word-start byte: raid-icon tokens are a Yapper
    -- feature, not language judgement.
    engine.WordStartBytes[123] = true

    if type(engine.Locales) == "table" then
        local set = {}
        for _, l in ipairs(engine.Locales) do set[l] = true end
        engine._localesSet = set
    end

    self.LanguageEngines[familyId] = engine
    self._engineFamily[engine]     = familyId
    if owner then self._engineOwners[familyId] = owner end
    self._failedEngines[familyId] = nil

    -- Engine semantics may have changed: purge everything derived from the
    -- previous engine for this family.
    self:_PurgeEngineCaches(familyId)
    return true
end

--- Wipe every cache whose contents depend on a family's engine semantics
--- (suggestion scores, KB distance tables, user-word normalised sets, and
--- per-dictionary metadata).  The dictionaries themselves are left alone.
function Spellcheck:_PurgeEngineCaches(familyId)
    self:ClearSuggestionCache()
    _kbDistCache = {}
    if self.UserDictCache then
        for locale in pairs(self.UserDictCache) do
            local fam = self:_FamilyForLocale(locale)
            if not familyId or fam == familyId or not fam then
                self.UserDictCache[locale] = nil
            end
        end
    end
    for _, d in pairs(self.Dictionaries or {}) do
        if not familyId or d.languageFamily == familyId then
            d._metaCache     = {}
            d._metaCacheSize = 0
        end
    end
end

--- Remove a failed engine and everything bound to it: the registration, the
--- owner lock, every dictionary of that family, and all derived caches.
--- Called on contract-violating runtime errors so a broken dictionary addon
--- cannot keep spamming errors or leaking memory.
function Spellcheck:_PurgeEngine(familyId, reason)
    if type(familyId) ~= "string" or familyId == "" then return end
    self._failedEngines = self._failedEngines or {}
    self._failedEngines[familyId] = reason or "purged"

    local engine = self.LanguageEngines and self.LanguageEngines[familyId]
    if engine and self._engineFamily then
        self._engineFamily[engine] = nil
    end
    if self.LanguageEngines then self.LanguageEngines[familyId] = nil end
    if self._engineOwners then self._engineOwners[familyId] = nil end

    for locale, d in pairs(self.Dictionaries or {}) do
        if (d.languageFamily or self:_FamilyForLocale(locale)) == familyId then
            self.Dictionaries[locale] = nil
            if self.UserDictCache then self.UserDictCache[locale] = nil end
            self._failedLocaleLoads = self._failedLocaleLoads or {}
            self._failedLocaleLoads[locale] = "ENGINE_PURGED"
        end
    end

    self:_PurgeEngineCaches(familyId)
    self:Notify("|cffff0000Yapper Error:|r Language engine '" .. familyId ..
        "' was purged (" .. tostring(reason) .. ").")
end

--- Protected engine call.  On a Lua error inside engine code the engine is
--- purged and nil is returned; callers treat nil as "no result".
--- @param passSelf boolean  true for colon-style entries (StripAffixes)
function Spellcheck:_SafeEngineCall(engine, key, passSelf, a1, a2, a3)
    local fn = engine and engine[key]
    if type(fn) ~= "function" then return nil end
    local ok, r1, r2
    if passSelf then
        ok, r1, r2 = pcall(fn, engine, a1, a2, a3)
    else
        ok, r1, r2 = pcall(fn, a1, a2, a3)
    end
    if ok then return r1, r2 end
    local family = self._engineFamily and self._engineFamily[engine]
    self:_PurgeEngine(family, "engine." .. key .. " error: " .. tostring(r1))
    return nil
end

--- Resolve the language family serving a locale: the dictionary's declared
--- family first, then any registered engine's advertised Locales list.
function Spellcheck:_FamilyForLocale(locale)
    local dict = self.Dictionaries and self.Dictionaries[locale]
    if dict and dict.languageFamily then return dict.languageFamily end
    for fid, e in pairs(self.LanguageEngines or {}) do
        if e._localesSet and e._localesSet[locale] then return fid end
    end
    return nil
end

--- Engine + family for an explicit locale, or nil.
function Spellcheck:_EngineForLocale(locale)
    local family = self:_FamilyForLocale(locale)
    if not family then return nil, nil end
    return (self.LanguageEngines or {})[family], family
end

--- Locale-scoped NormaliseWord: returns the engine's canonicaliser for the
--- given locale's family, or the neutral lowercase fallback.
function Spellcheck:_NormForLocale(locale)
    local engine = self:_EngineForLocale(locale)
    return (engine and engine.NormaliseWord) or NormaliseWord
end

--- Return the language engine registered for the current locale's family,
--- or nil when no engine is registered (spellcheck stays inert without one).
function Spellcheck:GetActiveEngine()
    local locale = self:GetLocale()
    return self:_EngineForLocale(locale)
end

--- Return the engine for an explicit family id, or nil.
function Spellcheck:GetEngine(familyId)
    if type(familyId) ~= "string" then return nil end
    return (self.LanguageEngines and self.LanguageEngines[familyId]) or nil
end

local function Clamp(val, minVal, maxVal)
    if val < minVal then return minVal end
    if val > maxVal then return maxVal end
    return val
end

local function SuggestionKey(entry)
    if type(entry) == "string" then
        return "word:" .. entry
    end
    if type(entry) == "table" then
        local kind = entry.kind or "word"
        local value = entry.value or entry.word or ""
        return kind .. ":" .. value
    end
    return tostring(entry)
end

-- Number of words to process per frame tick during async dictionary loading.
-- Configurable for devs; higher = faster loading but more per-frame cost.
local DICT_CHUNK_SIZE = 2000


function Spellcheck:GetConfig()
    return (YapperTable.Config and YapperTable.Config.Spellcheck) or {}
end

function Spellcheck:IsEnabled()
    local cfg = self:GetConfig()
    return cfg.Enabled ~= false
end

function Spellcheck:GetLocale()
    local cfg = self:GetConfig()
    if type(cfg.Locale) == "string" and cfg.Locale ~= "" then
        if not self:IsEnabled() or self:EnsureLocale(cfg.Locale) then
            return cfg.Locale
        end
        -- Temporarily use fallback if preferred locale is missing (LOD delay)
        -- but DO NOT overwrite the user's config key yet.
        return self:GetFallbackLocale()
    end
    -- Prefer a region-based default (region 3 -> enGB) before using client locale.
    local region = GetCurrentRegion and GetCurrentRegion() or nil
    if region == 3 then
        return "enGB"
    end

    if GetLocale then
        local client = GetLocale()
        if client == "enGB" then
            if not self:IsEnabled() or self:EnsureLocale("enGB") then return "enGB" end
        elseif client == "enUS" then
            if not self:IsEnabled() or self:EnsureLocale("enUS") then return "enUS" end
        end
    end

    return self:GetFallbackLocale()
end

function Spellcheck:GetFallbackLocale()
    local region = GetCurrentRegion and GetCurrentRegion() or nil
    if region == 3 then
        return "enGB"
    end
    return "enUS"
end

function Spellcheck:GetDictionary()
    if not self:IsEnabled() then return nil end
    local locale = self:GetLocale()
    if not self.Dictionaries[locale] then
        self:LoadDictionary(locale)
        self:EnsureLocale(locale)
    end
    return self.Dictionaries[locale]
end

function Spellcheck:GetMeta(dict, word)
    if type(dict) ~= "table" or type(word) ~= "string" or word == "" then return nil end
    dict._metaCache = dict._metaCache or {}
    dict._metaCacheSize = dict._metaCacheSize or 0
    local cache = dict._metaCache

    local cached = cache[word]
    if cached then return cached end

    -- Build metadata (letter bag + bigrams); byte keys avoid per-char
    -- string allocation.
    local bag = {}
    for i = 1, #word do
        local ch = string_byte(word, i)
        bag[ch] = (bag[ch] or 0) + 1
    end
    local bigrams = {}
    if #word >= 2 then
        for i = 1, (#word - 1) do
            local g = string_sub(word, i, i + 1)
            bigrams[g] = (bigrams[g] or 0) + 1
        end
    end
    local meta = { len = #word, bag = bag, bigrams = bigrams }

    cache[word] = meta
    dict._metaCacheSize = (dict._metaCacheSize or 0) + 1

    local cfg = (YapperTable and YapperTable.Config and YapperTable.Config.Spellcheck) or {}
    local cap = tonumber(cfg.MetaCacheMax) or 20000
    if dict._metaCacheSize > cap then
        local purge = math_min(2000, cap)
        self:EvictRandomMeta(dict, purge)
    end

    return meta
end

function Spellcheck:EvictRandomMeta(dict, count)
    if type(dict) ~= "table" or type(dict._metaCache) ~= "table" then return end

    -- Cheap eviction: pairs() order is effectively random, so purging the
    -- first `count` entries approximates random eviction without sorting
    -- ~20k keys.
    local removed = 0
    local cache = dict._metaCache
    for w in pairs(cache) do
        cache[w] = nil
        removed = removed + 1
        if removed >= count then break end
    end
    dict._metaCacheSize = math_max(0, (dict._metaCacheSize or 0) - removed)

    if IsDebugEnabled() then
        self:Notify("Spellcheck:EvictRandomMeta purged " .. tostring(removed) .. " entries.")
    end
end

--- Append unique entries of `src` (array) onto `dst` (array), in order.
local function MergeWordList(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    local seen = {}
    for _, w in ipairs(dst) do seen[w] = true end
    for _, w in ipairs(src) do
        if type(w) == "string" and w ~= "" and not seen[w] then
            dst[#dst + 1] = w
            seen[w] = true
        end
    end
end

-- Partition keys that can never come from GetLocale() and therefore hold
-- stranded user words: the legacy flat migration ("_legacy"), the earlier
-- "enBASE" migration target, and the base-dict addon key "enBase".
local USER_DICT_STRANDED_KEYS = { "_legacy", "enBASE", "enBase" }

function Spellcheck:GetUserDictStore()
    if type(_G.YapperDB) ~= "table" then return nil end
    _G.YapperDB.Spellcheck = Utils:EnsureTable(_G.YapperDB.Spellcheck)
    _G.YapperDB.Spellcheck.Dict = Utils:EnsureTable(_G.YapperDB.Spellcheck.Dict)

    local store = _G.YapperDB.Spellcheck.Dict

    -- Legacy Migration: park flat AddedWords/IgnoredWords under "_legacy".
    -- They are merged into the first real locale partition by GetUserDict —
    -- the previous code moved them to "enBASE", a key GetLocale() can never
    -- produce, which orphaned every migrated word.
    if store.AddedWords or store.IgnoredWords then
        store._legacy = store._legacy or { AddedWords = {}, IgnoredWords = {} }
        MergeWordList(store._legacy.AddedWords, store.AddedWords)
        MergeWordList(store._legacy.IgnoredWords, store.IgnoredWords)
        store.AddedWords = nil
        store.IgnoredWords = nil
        store._rev = nil
    end

    return store
end

function Spellcheck:GetUserDict(locale)
    local store = self:GetUserDictStore()
    if not store then return nil end
    store[locale] = Utils:EnsureTable(store[locale])
    local dict = store[locale]
    dict.AddedWords = Utils:EnsureTable(dict.AddedWords)
    dict.IgnoredWords = Utils:EnsureTable(dict.IgnoredWords)
    dict.BlockedWords = Utils:EnsureTable(dict.BlockedWords)

    -- Fold stranded partitions into the first real locale that asks for them.
    for _, key in ipairs(USER_DICT_STRANDED_KEYS) do
        if key ~= locale then
            local src = rawget(store, key)
            if type(src) == "table" then
                MergeWordList(dict.AddedWords, src.AddedWords)
                MergeWordList(dict.IgnoredWords, src.IgnoredWords)
                MergeWordList(dict.BlockedWords, src.BlockedWords)
                store[key] = nil
                dict._rev = (dict._rev or 0) + 1
            end
        end
    end

    return dict
end

function Spellcheck:TouchUserDict(dict)
    dict._rev = (dict._rev or 0) + 1
end

--- Converts a word list into a normalized lookup set for $O(1)$ performance.
--- @param list table Array of strings
--- @param normFn function|nil Engine NormaliseWord override (defaults to the
---        neutral lowercase fallback — callers should pass _NormForLocale)
--- @return table set Normalized word set
function Spellcheck:BuildWordSet(list, normFn)
    local norm = normFn or NormaliseWord
    local set = {}
    for _, w in ipairs(list or {}) do
        if type(w) == "string" and w ~= "" then
            set[norm(w)] = true
        end
    end
    return set
end

--- Returns cached, normalized lookup sets for the user's custom dictionary (Added/Ignored/Blocked).
--- Normalisation uses the engine of the given locale's family.
--- @param locale string
--- @return table|nil added, table|nil ignored, table|nil blocked
function Spellcheck:GetUserSets(locale)
    local dict = self:GetUserDict(locale)
    if not dict then return nil, nil, nil end
    local cache = self.UserDictCache[locale]
    if not cache or cache._rev ~= (dict._rev or 0) then
        local normFn = self:_NormForLocale(locale)
        self.UserDictCache[locale] = {
            added   = self:BuildWordSet(dict.AddedWords, normFn),
            ignored = self:BuildWordSet(dict.IgnoredWords, normFn),
            blocked = self:BuildWordSet(dict.BlockedWords, normFn),
            _rev    = dict._rev or 0,
        }
        cache = self.UserDictCache[locale]
    end
    return cache.added, cache.ignored, cache.blocked
end

--- Returns the data needed to check if a word is blocked at runtime.
--- @param locale string
--- @return table|nil addedSet, table|nil userBlockedSet, table|nil engineHashes, function|nil engineHashFn
function Spellcheck:GetBlockData(locale)
    local addedSet, _, userBlockedSet = self:GetUserSets(locale)

    local dict   = self.Dictionaries and self.Dictionaries[locale]
    local family = (dict and dict.languageFamily) or self:_FamilyForLocale(locale)
    local engine = family and self.LanguageEngines and self.LanguageEngines[family]

    local engineHashes = engine and engine.BlockedHashes
    local engineHashFn = engine and engine.HashWord

    return addedSet, userBlockedSet, engineHashes, engineHashFn
end

--- Convenience function for checking a single word (e.g., during YAS learning).
--- Do not use this in inner loops (like Autocomplete); use GetBlockData and local logic instead.
--- @param word string
--- @param locale string
--- @param ignoreManual boolean? If true, ignores AddedWords override (used by YAS)
--- @return boolean
function Spellcheck:IsWordBlocked(word, locale, ignoreManual)
    local w = self:_NormForLocale(locale)(word)
    local addedSet, userBlockedSet, engineHashes, engineHashFn = self:GetBlockData(locale)
    
    if not ignoreManual and addedSet and addedSet[w] then return false end
    if userBlockedSet and userBlockedSet[w] then return true end
    
    if engineHashes and engineHashFn then
        if engineHashes[engineHashFn(w)] then return true end
        
        local dw = Utils.Deleet(w) -- leet-speak form, e.g. "h3ll0"
        if engineHashes[engineHashFn(dw)] then return true end
    end
    
    return false
end

function Spellcheck:AddUserWord(locale, word)
    if type(word) ~= "string" or word == "" then return end
    local dict = self:GetUserDict(locale)
    if not dict then return end
    local normFn = self:_NormForLocale(locale)
    local norm = normFn(word)
    for _, w in ipairs(dict.AddedWords) do
        if normFn(w) == norm then
            return
        end
    end
    dict.AddedWords[#dict.AddedWords + 1] = word
    -- Cap user dictionary: FIFO eviction of oldest additions
    local maxAdded = self:GetUserDictWordCap()
    while #dict.AddedWords > maxAdded do
        table_remove(dict.AddedWords, 1)
    end
    for i = #dict.IgnoredWords, 1, -1 do
        if normFn(dict.IgnoredWords[i]) == norm then
            table_remove(dict.IgnoredWords, i)
        end
    end
    self:TouchUserDict(dict)
    self:ClearSuggestionCache()
    if YapperTable.API then
        YapperTable.API:Fire("SPELLCHECK_WORD_ADDED", word, locale)
    end
end

function Spellcheck:IgnoreWord(locale, word)
    if type(word) ~= "string" or word == "" then return end
    local dict = self:GetUserDict(locale)
    if not dict then return end
    local normFn = self:_NormForLocale(locale)
    local norm = normFn(word)
    for _, w in ipairs(dict.IgnoredWords) do
        if normFn(w) == norm then
            return
        end
    end
    dict.IgnoredWords[#dict.IgnoredWords + 1] = word
    for i = #dict.AddedWords, 1, -1 do
        if normFn(dict.AddedWords[i]) == norm then
            table_remove(dict.AddedWords, i)
        end
    end
    self:TouchUserDict(dict)
    self:ClearSuggestionCache()
    if YapperTable.API then
        YapperTable.API:Fire("SPELLCHECK_WORD_IGNORED", word, locale)
    end
end

--- Completely invalidates the suggestion cache and resets the O(1) counter.
function Spellcheck:ClearSuggestionCache()
    self._suggestionCache = {}
    self._suggestionCacheCount = 0
end

function Spellcheck:GetMaxSuggestions()
    local cfg = self:GetConfig()
    return Clamp(tonumber(cfg.MaxSuggestions) or 4, 1, 4)
end

function Spellcheck:GetMaxCandidates()
    local cfg = self:GetConfig()
    return Clamp(tonumber(cfg.MaxCandidates) or 800, 50, 5000)
end

function Spellcheck:GetSuggestionCacheSize()
    local cfg = self:GetConfig()
    return Clamp(tonumber(cfg.SuggestionCacheSize) or 50, 0, 500)
end

function Spellcheck:GetReshuffleAttempts()
    local cfg = self:GetConfig()
    return Clamp(tonumber(cfg.ReshuffleAttempts) or 3, 0, 20)
end

function Spellcheck:GetMaxWrongLetters()
    local cfg = self:GetConfig()
    return Clamp(tonumber(cfg.MaxWrongLetters) or 4, 0, 20)
end

function Spellcheck:GetNgramN()
    local cfg = self:GetConfig()
    return Clamp(tonumber(cfg.NgramN) or 2, 2, 4)
end

function Spellcheck:GetNgramMaxPosting()
    local cfg = self:GetConfig()
    return Clamp(tonumber(cfg.NgramMaxPosting) or 500, 1, 5000)
end

function Spellcheck:GetNgramTopCandidates()
    local cfg = self:GetConfig()
    return Clamp(tonumber(cfg.NgramTopCandidates) or 500, 1, 5000)
end

function Spellcheck:GetMinWordLength()
    local cfg = self:GetConfig()
    return Clamp(tonumber(cfg.MinWordLength) or 2, 1, 10)
end

function Spellcheck:GetUserDictWordCap()
    local cfg = self:GetConfig()
    return Clamp(tonumber(cfg.UserDictWordCap) or 2000, 50, 10000)
end

--- Effective misspelling colour ({ r, g, b, a? }), defaults to magenta.
--- Used by the recolour engine via Recolour.ResolveColour.
function Spellcheck:GetMisspellingColour()
    local cfg = self:GetConfig()
    local c = cfg.MisspellingColour or cfg.UnderlineColor
    if type(c) ~= "table" then
        return { r = 1.0, g = 0.0, b = 1.0 }
    end
    return c
end

--- Sorted list of layout names provided by the active engine (or a given one).
--- @param engine table|nil  defaults to GetActiveEngine()
--- @return table array of layout-name strings (possibly empty)
function Spellcheck:GetKeyboardLayoutNames(engine)
    engine = engine or self:GetActiveEngine()
    local layouts = engine and engine.KBLayouts
    local out = {}
    if type(layouts) == "table" then
        for name in pairs(layouts) do out[#out + 1] = name end
        table_sort(out)
    end
    return out
end

--- The layout name to score against: the user's config choice when the active
--- engine provides it, else the engine's DefaultLayout, else the first
--- declared layout alphabetically.  Returns nil when no engine is active.
function Spellcheck:GetKeyboardLayout()
    local cfg    = self:GetConfig()
    local engine = self:GetActiveEngine()
    local layouts = engine and engine.KBLayouts
    if type(layouts) ~= "table" then return nil end
    local want = cfg.KeyboardLayout
    if type(want) == "string" and layouts[want] then return want end
    if type(engine.DefaultLayout) == "string" and layouts[engine.DefaultLayout] then
        return engine.DefaultLayout
    end
    return self:GetKeyboardLayoutNames(engine)[1]
end

--- Build (and cache) a KB distance table from an engine's layouts table.
--- Returns nil when the engine provides no layouts or the requested layout
--- is missing — proximity scoring is then skipped entirely.
--- @param layouts table  engine.KBLayouts: { layoutName = { char = {x,y} } }
--- @param layoutName string
--- @return table|nil  676-entry distance lookup
function Spellcheck:_GetKBDistFromLayouts(layouts, layoutName)
    if type(layouts) ~= "table" or type(layoutName) ~= "string" then return nil end
    local coords = layouts[layoutName]
    if not coords then return nil end
    local key = tostring(layouts) .. "|" .. layoutName
    if _kbDistCache[key] then
        return _kbDistCache[key]
    end
    -- Bounded: engines are capped at MaxKBLayouts each and the cache is
    -- wiped on engine (re)registration, but keep a hard ceiling anyway.
    local n = 0
    for _ in pairs(_kbDistCache) do n = n + 1 end
    if n >= KB_DIST_CACHE_CAP then _kbDistCache = {} end
    local tbl = BuildKBDistTable(coords)
    _kbDistCache[key] = tbl
    return tbl
end

-- ---------------------------------------------------------------------------
-- Shared word iterator: iterates over word boundaries in text.
-- Yields (startPos, endPos, word) for each word found.
-- Byte classification is resolved once per call from the ACTIVE engine's
-- WordBytes/WordStartBytes (neutral fallback sets when no engine is loaded).
-- ---------------------------------------------------------------------------

--- Iterate over all words in text, yielding start, end, word for each.
--- @param text string
--- @return function iterator
local function IterWords(text)
    local engine    = Spellcheck:GetActiveEngine()
    local wordByte  = WordBytesFor(engine)
    local startByte = WordStartBytesFor(engine)
    local idx = 1
    local len = #text
    return function()
        while idx <= len do
            local byte = string_byte(text, idx)
            if not byte then return nil end
            if startByte[byte] then
                local s = idx
                idx = idx + 1
                while idx <= len do
                    local b = string_byte(text, idx)
                    if not b or not wordByte[b] then break end
                    idx = idx + 1
                end
                local e = idx - 1
                return s, e, string_sub(text, s, e)
            else
                idx = idx + 1
            end
        end
        return nil
    end
end

-- Export shared locals for sub-files to re-localise.
-- NormaliseWord / NormaliseVowels / GetPhoneticHash / IsWordByte /
-- IsWordStartByte are engine-delegating closures defined above.
Spellcheck._SCORE_WEIGHTS       = SCORE_WEIGHTS
Spellcheck._MAX_SUGGESTION_ROWS = MAX_SUGGESTION_ROWS
Spellcheck._RAID_ICONS          = RAID_ICONS
Spellcheck._DICT_CHUNK_SIZE     = DICT_CHUNK_SIZE or 2000
Spellcheck.Clamp                = Clamp
Spellcheck.SuggestionKey        = SuggestionKey
Spellcheck.IsDebugEnabled       = IsDebugEnabled
Spellcheck.IterWords            = IterWords
