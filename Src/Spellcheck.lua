--[[
    Spellcheck.lua
    Lightweight spellcheck for the overlay editbox.

    Uses packaged dictionary tables registered at load time.
]]

local _, YapperTable = ...

local Spellcheck = {}
YapperTable.Spellcheck = Spellcheck

-- Localise Lua globals for performance (avoids table lookups in hot loops)
local math_abs   = math.abs
local math_min   = math.min
local math_max   = math.max
local math_floor = math.floor
local math_huge  = math.huge
local table_insert = table.insert
local table_sort = table.sort
local table_remove = table.remove
local string_sub = string.sub
local string_byte = string.byte
local string_lower = string.lower
local string_gsub = string.gsub
local string_upper = string.upper
local string_match = string.match
local string_char = string.char
local string_format = string.format
local type = type
local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local tonumber = tonumber
local select = select

Spellcheck.Dictionaries = {}
Spellcheck.KnownLocales = {
    "enUS",
    "enGB",
}
Spellcheck.LocaleAddons = {}
Spellcheck.EditBox = nil
Spellcheck.Overlay = nil
Spellcheck.MeasureFS = nil
Spellcheck.UnderlinePool = {}
Spellcheck.Underlines = {}
Spellcheck.SuggestionFrame = nil
Spellcheck.SuggestionRows = {}
Spellcheck.ActiveSuggestions = nil
Spellcheck.ActiveIndex = 1
Spellcheck.ActiveWord = nil
Spellcheck.ActiveRange = nil
Spellcheck.HintFrame = nil
Spellcheck._debounceTimer = nil
Spellcheck.UserDictCache = {}
Spellcheck._pendingLocaleLoads = {}
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

-- Coordinates: { x, y } where x is column (with stagger) and y is row.
-- Only lowercase a-z; digits/punctuation excluded since ShouldCheckWord
-- already filters words containing them.
local KB_LAYOUTS = {
    QWERTY = {
        q = { 0, 0 },
        w = { 1, 0 },
        e = { 2, 0 },
        r = { 3, 0 },
        t = { 4, 0 },
        y = { 5, 0 },
        u = { 6, 0 },
        i = { 7, 0 },
        o = { 8, 0 },
        p = { 9, 0 },
        a = { 0.25, 1 },
        s = { 1.25, 1 },
        d = { 2.25, 1 },
        f = { 3.25, 1 },
        g = { 4.25, 1 },
        h = { 5.25, 1 },
        j = { 6.25, 1 },
        k = { 7.25, 1 },
        l = { 8.25, 1 },
        z = { 0.75, 2 },
        x = { 1.75, 2 },
        c = { 2.75, 2 },
        v = { 3.75, 2 },
        b = { 4.75, 2 },
        n = { 5.75, 2 },
        m = { 6.75, 2 },
    },
    QWERTZ = {
        q = { 0, 0 },
        w = { 1, 0 },
        e = { 2, 0 },
        r = { 3, 0 },
        t = { 4, 0 },
        z = { 5, 0 },
        u = { 6, 0 },
        i = { 7, 0 },
        o = { 8, 0 },
        p = { 9, 0 },
        a = { 0.25, 1 },
        s = { 1.25, 1 },
        d = { 2.25, 1 },
        f = { 3.25, 1 },
        g = { 4.25, 1 },
        h = { 5.25, 1 },
        j = { 6.25, 1 },
        k = { 7.25, 1 },
        l = { 8.25, 1 },
        y = { 0.75, 2 },
        x = { 1.75, 2 },
        c = { 2.75, 2 },
        v = { 3.75, 2 },
        b = { 4.75, 2 },
        n = { 5.75, 2 },
        m = { 6.75, 2 },
    },
    AZERTY = {
        a = { 0, 0 },
        z = { 1, 0 },
        e = { 2, 0 },
        r = { 3, 0 },
        t = { 4, 0 },
        y = { 5, 0 },
        u = { 6, 0 },
        i = { 7, 0 },
        o = { 8, 0 },
        p = { 9, 0 },
        q = { 0.25, 1 },
        s = { 1.25, 1 },
        d = { 2.25, 1 },
        f = { 3.25, 1 },
        g = { 4.25, 1 },
        h = { 5.25, 1 },
        j = { 6.25, 1 },
        k = { 7.25, 1 },
        l = { 8.25, 1 },
        m = { 9.25, 1 },
        w = { 0.75, 2 },
        x = { 1.75, 2 },
        c = { 2.75, 2 },
        v = { 3.75, 2 },
        b = { 4.75, 2 },
        n = { 5.75, 2 },
    },
}

-- Build a flat 676-entry distance lookup indexed by (b1-97)*26 + (b2-97) + 1
-- where b1,b2 are byte values of lowercase a-z. Called once per layout change.

function Spellcheck:Init(threads)
    -- Ensure distance buffers are pre-allocated to avoid first-run stalls/nils
    if not self._ed_prev then self._ed_prev = {} end
    if not self._ed_cur then self._ed_cur = {} end
    if not self._ed_prev_prev then self._ed_prev_prev = {} end

    -- Ensure YALLM is initialized and hooks its SavedVariables
    if self.YALLM and self.YALLM.Init then
        self.YALLM:Init()
    end

    -- Apply initial state based on current config
    self:ApplyState()
end

local function BuildKBDistTable(layoutName)
    local coords = KB_LAYOUTS[layoutName] or KB_LAYOUTS.QWERTY
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
                    -- Euclidean distance (sqrt avoided at query time by
                    -- comparing squared distances would be cheaper, but the
                    -- table is built once so sqrt here is fine)
                    local d = (dx * dx + dy * dy) ^ 0.5
                    tbl[(ch1 - 97) * 26 + (ch2 - 97) + 1] = d
                end
            end
        end
    end
    return tbl
end

-- Active distance table; rebuilt when layout config changes
local _kbDistTable = nil
local _kbDistLayout = nil

local function Clamp(val, minVal, maxVal)
    if val < minVal then return minVal end
    if val > maxVal then return maxVal end
    return val
end

local function NormaliseWord(word)
    if type(word) ~= "string" then return "" end
    return string_lower(word)
end

local function NormaliseVowels(word)
    if type(word) ~= "string" then return "" end
    return string_gsub(string_lower(word), "[aeiouy]", "*")
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

local function IsWordByte(byte)
    if byte >= 128 then
        return true
    end
    if byte == 39 then -- apostrophe
        return true
    end
    return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)
end

local function IsWordStartByte(byte)
    if byte >= 128 then
        return true
    end
    -- Allow standard letters, plus '{' (123) for raid icons
    return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or (byte == 123)
end

-- Exact parity with generate_phonetic_dict.py
function Spellcheck.GetPhoneticHash(word)
    local hash = string_upper(word)
    -- Strip non-alphabetic characters (including apostrophes)
    hash = string_gsub(hash, "[^%a]", "")

    -- Strip duplicate adjacent letters (e.g., "LL" -> "L")
    hash = string_gsub(hash, "(%a)%1", "%1")

    -- Silent/Variable groups
    hash = string_gsub(hash, "GHT", "T")
    hash = string_gsub(hash, "PH", "F")
    hash = string_gsub(hash, "KN", "N")
    hash = string_gsub(hash, "GN", "N")
    hash = string_gsub(hash, "WR", "R")
    hash = string_gsub(hash, "CH", "K")
    hash = string_gsub(hash, "SH", "X")
    hash = string_gsub(hash, "C", "K")
    hash = string_gsub(hash, "Q", "K")
    hash = string_gsub(hash, "X", "KS")
    hash = string_gsub(hash, "Z", "S")

    -- GH at the end of word often sounds like F (laugh, enough)
    if string_sub(hash, -2) == "GH" then
        hash = string_sub(hash, 1, -3) .. "F"
    else
        hash = string_gsub(hash, "GH", "") -- Silent GH (night, through)
    end

    if hash == "" then return "" end

    -- Keep the first letter, strip vowels from the rest
    local firstChar = string_sub(hash, 1, 1)
    local rest = string_sub(hash, 2)
    rest = string_gsub(rest, "[AEIOUY]", "")

    return firstChar .. rest
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
        local fallback = self:GetFallbackLocale()
        if cfg.Locale ~= fallback then
            cfg.Locale = fallback
        end
        return fallback
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
    dict._metaUsageTimer = dict._metaUsageTimer or 0
    dict._metaCacheSize = dict._metaCacheSize or 0
    local cache = dict._metaCache

    -- update usage counter
    dict._metaUsageTimer = dict._metaUsageTimer + 1
    local entry = cache[word]
    if entry then
        entry.lastUsed = dict._metaUsageTimer
        return entry.meta
    end

    -- build metadata (letter frequencies and bigrams)
    -- Use byte keys for the bag to avoid per-character string allocation
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

    cache[word] = { meta = meta, lastUsed = dict._metaUsageTimer }
    dict._metaCacheSize = (dict._metaCacheSize or 0) + 1

    local cfg = (YapperTable and YapperTable.Config and YapperTable.Config.Spellcheck) or {}
    local cap = tonumber(cfg.MetaCacheMax) or 20000
    if dict._metaCacheSize > cap then
        local purge = math_min(2000, cap)
        self:EvictOldestMeta(dict, purge)
    end

    return meta
end

function Spellcheck:EvictOldestMeta(dict, count)
    if type(dict) ~= "table" or type(dict._metaCache) ~= "table" then return end

    -- Fast random-ish eviction: just purge the first 'count' entries we find
    -- via pairs(). Since Lua's pairs() order is effectively random, this
    -- serves as a cheap approximation of eviction without sorting 20,000 keys.
    local removed = 0
    local cache = dict._metaCache
    for w in pairs(cache) do
        cache[w] = nil
        removed = removed + 1
        if removed >= count then break end
    end
    dict._metaCacheSize = math_max(0, (dict._metaCacheSize or 0) - removed)

    if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        self:Notify("Spellcheck:EvictOldestMeta purged " .. tostring(removed) .. " entries.")
    end
end

function Spellcheck:GetUserDictStore()
    if type(_G.YapperDB) ~= "table" then return nil end
    if type(_G.YapperDB.Spellcheck) ~= "table" then _G.YapperDB.Spellcheck = {} end
    if type(_G.YapperDB.Spellcheck.Dict) ~= "table" then _G.YapperDB.Spellcheck.Dict = {} end
    return _G.YapperDB.Spellcheck.Dict
end

function Spellcheck:GetUserDict(locale)
    local store = self:GetUserDictStore()
    if not store then return nil end
    if type(store[locale]) ~= "table" then
        store[locale] = { AddedWords = {}, IgnoredWords = {} }
    end
    if type(store[locale].AddedWords) ~= "table" then store[locale].AddedWords = {} end
    if type(store[locale].IgnoredWords) ~= "table" then store[locale].IgnoredWords = {} end
    return store[locale]
end

function Spellcheck:TouchUserDict(dict)
    dict._rev = (dict._rev or 0) + 1
end

function Spellcheck:BuildWordSet(list)
    local set = {}
    for _, w in ipairs(list or {}) do
        if type(w) == "string" and w ~= "" then
            local norm = NormaliseWord(w)
            set[norm] = true
        end
    end
    return set
end

function Spellcheck:GetUserSets(locale)
    local dict = self:GetUserDict(locale)
    if not dict then return nil, nil end
    local cache = self.UserDictCache[locale]
    if not cache or cache._rev ~= (dict._rev or 0) then
        self.UserDictCache[locale] = {
            added = self:BuildWordSet(dict.AddedWords),
            ignored = self:BuildWordSet(dict.IgnoredWords),
            _rev = dict._rev or 0,
        }
        cache = self.UserDictCache[locale]
    end
    return cache.added, cache.ignored
end

function Spellcheck:AddUserWord(locale, word)
    if type(word) ~= "string" or word == "" then return end
    local dict = self:GetUserDict(locale)
    if not dict then return end
    local norm = NormaliseWord(word)
    for _, w in ipairs(dict.AddedWords) do
        if NormaliseWord(w) == norm then
            return
        end
    end
    dict.AddedWords[#dict.AddedWords + 1] = word
    for i = #dict.IgnoredWords, 1, -1 do
        if NormaliseWord(dict.IgnoredWords[i]) == norm then
            table_remove(dict.IgnoredWords, i)
        end
    end
    self:TouchUserDict(dict)
    self._suggestionCache = {}
    if YapperTable.API then
        YapperTable.API:Fire("SPELLCHECK_WORD_ADDED", word, locale)
    end
end

function Spellcheck:IgnoreWord(locale, word)
    if type(word) ~= "string" or word == "" then return end
    local dict = self:GetUserDict(locale)
    if not dict then return end
    local norm = NormaliseWord(word)
    for _, w in ipairs(dict.IgnoredWords) do
        if NormaliseWord(w) == norm then
            return
        end
    end
    dict.IgnoredWords[#dict.IgnoredWords + 1] = word
    for i = #dict.AddedWords, 1, -1 do
        if NormaliseWord(dict.AddedWords[i]) == norm then
            table_remove(dict.AddedWords, i)
        end
    end
    self:TouchUserDict(dict)
    self._suggestionCache = {}
    if YapperTable.API then
        YapperTable.API:Fire("SPELLCHECK_WORD_IGNORED", word, locale)
    end
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

function Spellcheck:GetMinWordLength()
    local cfg = self:GetConfig()
    return Clamp(tonumber(cfg.MinWordLength) or 2, 1, 10)
end

function Spellcheck:GetUnderlineStyle()
    local cfg = self:GetConfig()
    if cfg.UnderlineStyle == "highlight" then
        return "highlight"
    end
    return "line"
end

function Spellcheck:GetKeyboardLayout()
    local cfg = self:GetConfig()
    local layout = cfg.KeyboardLayout
    if layout == "QWERTZ" or layout == "AZERTY" then
        return layout
    end
    return "QWERTY"
end

-- Returns the flat 676-entry distance lookup table, rebuilding only on layout change.
function Spellcheck:GetKBDistTable()
    local layout = self:GetKeyboardLayout()
    if _kbDistTable and _kbDistLayout == layout then
        return _kbDistTable
    end
    _kbDistTable = BuildKBDistTable(layout)
    _kbDistLayout = layout
    return _kbDistTable
end

-- Export shared locals for sub-files to re-localise.
Spellcheck._SCORE_WEIGHTS     = SCORE_WEIGHTS
Spellcheck._MAX_SUGGESTION_ROWS = MAX_SUGGESTION_ROWS
Spellcheck._RAID_ICONS        = RAID_ICONS
Spellcheck._KB_LAYOUTS        = KB_LAYOUTS
Spellcheck._DICT_CHUNK_SIZE   = DICT_CHUNK_SIZE or 2000
Spellcheck.Clamp              = Clamp
Spellcheck.NormaliseWord      = NormaliseWord
Spellcheck.NormaliseVowels    = NormaliseVowels
Spellcheck.SuggestionKey      = SuggestionKey
Spellcheck.IsWordByte         = IsWordByte
Spellcheck.IsWordStartByte    = IsWordStartByte
