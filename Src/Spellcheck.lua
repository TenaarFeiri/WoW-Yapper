--[[
    Spellcheck.lua
    Lightweight spellcheck for the overlay editbox.

    Uses packaged dictionary tables registered at load time.
]]

local _, YapperTable = ...

local Spellcheck = {}
YapperTable.Spellcheck = Spellcheck

-- Localize Lua globals for performance (avoids table lookups in hot loops)
local math_abs = math.abs
local math_min = math.min
local math_max = math.max
local math_huge = math.huge
local table_insert = table.insert
local table_sort = table.sort
local table_remove = table.remove
local table_concat = table.concat
local string_sub = string.sub
local string_byte = string.byte
local string_lower = string.lower
local string_gsub = string.gsub
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
Spellcheck._debugLoadedLocales = {}
Spellcheck.DictionaryBuilders = {}
-- Reusable buffers for EditDistance to avoid per-call allocations
Spellcheck._ed_prev = {}
Spellcheck._ed_cur = {}
Spellcheck._ed_prev_prev = {}

local MAX_SUGGESTION_ROWS = 6
local SCORE_WEIGHTS = {
    lenDiff = 0.25,
    prefix = 0.15,
    letterBag = 0.20,
    bigram = 0.16,
    longerPenalty = 0.12,
    kbProximity = 0.35,
}

-- Keyboard layout coordinate maps for proximity scoring.
-- Row stagger offsets (configurable): each row is shifted right by this
-- fraction of a key width relative to the row above it.
local KB_ROW_STAGGER = { 0, 0.25, 0.75 }

-- Coordinates: { x, y } where x is column (with stagger) and y is row.
-- Only lowercase a-z; digits/punctuation excluded since ShouldCheckWord
-- already filters words containing them.
local KB_LAYOUTS = {
    QWERTY = {
        q={0,0},       w={1,0},       e={2,0},       r={3,0},       t={4,0},
        y={5,0},       u={6,0},       i={7,0},       o={8,0},       p={9,0},
        a={0.25,1},    s={1.25,1},    d={2.25,1},    f={3.25,1},    g={4.25,1},
        h={5.25,1},    j={6.25,1},    k={7.25,1},    l={8.25,1},
        z={0.75,2},    x={1.75,2},    c={2.75,2},    v={3.75,2},    b={4.75,2},
        n={5.75,2},    m={6.75,2},
    },
    QWERTZ = {
        q={0,0},       w={1,0},       e={2,0},       r={3,0},       t={4,0},
        z={5,0},       u={6,0},       i={7,0},       o={8,0},       p={9,0},
        a={0.25,1},    s={1.25,1},    d={2.25,1},    f={3.25,1},    g={4.25,1},
        h={5.25,1},    j={6.25,1},    k={7.25,1},    l={8.25,1},
        y={0.75,2},    x={1.75,2},    c={2.75,2},    v={3.75,2},    b={4.75,2},
        n={5.75,2},    m={6.75,2},
    },
    AZERTY = {
        a={0,0},       z={1,0},       e={2,0},       r={3,0},       t={4,0},
        y={5,0},       u={6,0},       i={7,0},       o={8,0},       p={9,0},
        q={0.25,1},    s={1.25,1},    d={2.25,1},    f={3.25,1},    g={4.25,1},
        h={5.25,1},    j={6.25,1},    k={7.25,1},    l={8.25,1},    m={9.25,1},
        w={0.75,2},    x={1.75,2},    c={2.75,2},    v={3.75,2},    b={4.75,2},
        n={5.75,2},
    },
}

-- Build a flat 676-entry distance lookup indexed by (b1-97)*26 + (b2-97) + 1
-- where b1,b2 are byte values of lowercase a-z. Called once per layout change.
local function BuildKBDistTable(layoutName)
    local coords = KB_LAYOUTS[layoutName] or KB_LAYOUTS.QWERTY
    local tbl = {}
    -- Pre-fill with a large sentinel so missing keys return high distance
    for i = 1, 676 do tbl[i] = 99 end
    for ch1 = 97, 122 do
        local c1 = coords[string.char(ch1)]
        if c1 then
            for ch2 = 97, 122 do
                local c2 = coords[string.char(ch2)]
                if c2 then
                    local dx = c1[1] - c2[1]
                    local dy = c1[2] - c2[2]
                    -- Euclidean distance (sqrt avoided at query time by
                    -- comparing squared distances would be cheaper, but the
                    -- table is built once so sqrt here is fine)
                    local d = (dx*dx + dy*dy) ^ 0.5
                    tbl[(ch1-97)*26 + (ch2-97) + 1] = d
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

local function NormalizeWord(word)
    if type(word) ~= "string" then return "" end
    return string_lower(word)
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
    return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)
end

-- Number of words to process per frame tick during async dictionary loading.
-- Configurable for devs; higher = faster loading but more per-frame cost.
local DICT_CHUNK_SIZE = 2000

function Spellcheck:LoadDictionary(locale)
    -- Don't start a new load if it's already in memory OR currently loading.
    if self.Dictionaries and self.Dictionaries[locale] then return end
    if self._asyncLoaders and self._asyncLoaders[locale] then return end

    if self.DictionaryBuilders and self.DictionaryBuilders[locale] then
        local builder = self.DictionaryBuilders[locale]
        
        -- Use pcall to prevent bad dicts from destroying spellcheck permanently
        local success, data = pcall(builder)
        if success and data then
            self:RegisterDictionary(locale, data)
        else
            if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
                self:Notify("Spellcheck failed to load dictionary for " .. tostring(locale))
            end
        end
    end
end

function Spellcheck:RegisterDictionary(locale, data)
    if type(locale) ~= "string" or locale == "" then
        return
    end

    if type(data) == "function" then
        self.DictionaryBuilders = self.DictionaryBuilders or {}
        self.DictionaryBuilders[locale] = data
        return
    end

    if type(data) ~= "table" then
        return
    end

    local words = data.words or {}

    -- Cancel any in-progress async load for this locale (e.g. locale switch)
    if self._asyncLoaders and self._asyncLoaders[locale] then
        self._asyncLoaders[locale].cancelled = true
        self._asyncLoaders[locale] = nil
    end

    local existing = self.Dictionaries[locale]
    local set = existing and existing.set or {}
    local index = existing and existing.index or {}
    local outWords = existing and existing.words or {}
    local ngramIndex = existing and existing.ngramIndex or {}
    local ngramN = (YapperTable and YapperTable.Config and YapperTable.Config.Spellcheck and YapperTable.Config.Spellcheck.NgramN) or 2
    local ngramMaxPosting = (YapperTable and YapperTable.Config and YapperTable.Config.Spellcheck and YapperTable.Config.Spellcheck.NgramMaxPosting) or 200

    -- Make the dictionary available immediately (even if empty/partial),
    -- so CollectMisspellings can start using words as they arrive.
    if not existing then
        self.Dictionaries[locale] = {
            locale = locale,
            words = outWords,
            set = set,
            index = index,
            ngramIndex = ngramIndex,
            _metaCache = {},
            _metaUsageTimer = 0,
            _metaCacheSize = 0,
        }
    end

    -- Core word processing: adds a word to set, index, and ngramIndex.
    -- Returns true if the word was newly added.
    local function processWord(word)
        if type(word) ~= "string" or word == "" then return false end
        local w = NormalizeWord(word)
        if w == "" then return false end
        local b = string_byte(w, 1)
        if not b or not IsWordStartByte(b) then return false end
        if set[w] then return false end

        set[w] = true
        outWords[#outWords + 1] = word
        local key = string_sub(w, 1, 1)
        if key ~= "" then
            index[key] = index[key] or {}
            index[key][#index[key] + 1] = w
        end

        -- Build n-gram postings inline
        local id = #outWords
        if #w >= ngramN then
            for i = 1, (#w - ngramN + 1) do
                local g = string_sub(w, i, i + ngramN - 1)
                ngramIndex[g] = ngramIndex[g] or {}
                local posting = ngramIndex[g]
                if #posting < ngramMaxPosting then
                    posting[#posting + 1] = id
                end
            end
        end
        return true
    end

    local totalWords = #words

    -- For small dictionaries, process synchronously (no overhead)
    if totalWords <= DICT_CHUNK_SIZE then
        for _, word in ipairs(words) do
            processWord(word)
        end
        self:_OnDictRegistrationComplete(locale)
        return
    end

    -- Async path: time-slice across frames for large dictionaries
    if not self._asyncLoaders then self._asyncLoaders = {} end

    local loader = {
        cancelled = false,
        cursor = 1,
        total = totalWords,
    }
    self._asyncLoaders[locale] = loader

    -- Notify user that loading has started (only if spellcheck is enabled)
    if self:IsEnabled() then
        self:Notify("Yapper: loading " .. tostring(locale) .. " dictionary (" .. tostring(totalWords) .. " words)...")
    end

    local function processChunk()
        if loader.cancelled then return end

        local endIdx = math_min(loader.cursor + DICT_CHUNK_SIZE - 1, totalWords)
        for i = loader.cursor, endIdx do
            processWord(words[i])
        end
        loader.cursor = endIdx + 1

        if loader.cursor > totalWords then
            -- Finished loading
            if self._asyncLoaders then
                self._asyncLoaders[locale] = nil
            end
            self:_OnDictRegistrationComplete(locale)
        else
            -- Schedule next chunk on the next frame
            if C_Timer and C_Timer.After then
                C_Timer.After(0, processChunk)
            else
                -- Fallback: process remaining synchronously
                for i = loader.cursor, totalWords do
                    processWord(words[i])
                end
                if self._asyncLoaders then
                    self._asyncLoaders[locale] = nil
                end
                self:_OnDictRegistrationComplete(locale)
            end
        end
    end

    -- Kick off the first chunk immediately (synchronous for the first batch)
    processChunk()
end

function Spellcheck:_OnDictRegistrationComplete(locale)
    local dict = self.Dictionaries[locale]
    local count = dict and dict.words and #dict.words or 0

    if YapperTable.Utils and YapperTable.Utils.Print then
        YapperTable.Utils:Print("info", "Dictionary loaded:", locale, ("(%s words)"):format(tostring(count)))
    else
        self:Notify("Yapper: " .. tostring(locale) .. " dictionary loaded (" .. tostring(count) .. " words).")
    end

    local cfg = self:GetConfig()
    if cfg and cfg.Locale == locale and self:IsEnabled() then
        -- Coalesce multiple rapid registrations for the same locale
        -- (chunked dictionaries) so we don't schedule a rebuild for
        -- every chunk. Schedule a single short-timer refresh instead.
        self._pendingLocaleRefreshTimers = self._pendingLocaleRefreshTimers or {}
        if C_Timer and C_Timer.NewTimer then
            if not self._pendingLocaleRefreshTimers[locale] then
                self._pendingLocaleRefreshTimers[locale] = C_Timer.NewTimer(0.08, function()
                    self._pendingLocaleRefreshTimers[locale] = nil
                    if self:IsEnabled() then
                        self:ScheduleRefresh()
                    end
                end)
            end
        else
            self:ScheduleRefresh()
        end
    end
end


function Spellcheck:GetAvailableLocales()
    local out = {}
    for locale in pairs(self.Dictionaries) do
        out[#out + 1] = locale
    end
    table.sort(out)
    return out
end

function Spellcheck:GetLocaleAddon(locale)
    if type(locale) ~= "string" then return nil end
    return (self.LocaleAddons and self.LocaleAddons[locale]) or nil
end

function Spellcheck:HasLocaleAddon(locale)
    local addon = self:GetLocaleAddon(locale)
    if not addon then return false end
    if IsAddOnLoaded and IsAddOnLoaded(addon) then return true end
    if GetAddOnInfo then
        local name = GetAddOnInfo(addon)
        return name ~= nil
    end
    return false
end

function Spellcheck:IsLocaleAvailable(locale)
    if type(locale) ~= "string" or locale == "" then return false end
    if self.Dictionaries and self.Dictionaries[locale] then return true end
    -- If the locale is known and we don't require an external addon, consider it available.
    for _, l in ipairs(self.KnownLocales or {}) do
        if l == locale then
            if not (self.LocaleAddons and self.LocaleAddons[locale]) then
                return true
            end
        end
    end
    return false
end

function Spellcheck:CanLoadLocale(locale)
    local addon = self:GetLocaleAddon(locale)
    if not addon then
        return self:IsLocaleAvailable(locale)
    end
    if IsAddOnLoaded and IsAddOnLoaded(addon) then
        return true
    end
    return self:HasLocaleAddon(locale)
end

function Spellcheck:Notify(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
end

function Spellcheck:EnsureLocale(locale)
    self:LoadDictionary(locale)
    if self:IsLocaleAvailable(locale) then
        return true
    end

    local addon = self:GetLocaleAddon(locale)
    if addon and not self:HasLocaleAddon(locale) then
        return false
    end
    if addon then
        if C_AddOns and C_AddOns.LoadAddOn then
            local loaded, reason = C_AddOns.LoadAddOn(addon)
            if loaded == false then
                if self.Notify then
                    self:Notify("Yapper: failed to load " .. addon .. " (" .. tostring(reason) .. ").")
                end
                return false
            end
        elseif LoadAddOn then
            local loaded = LoadAddOn(addon)
            if loaded == false then
                return false
            end
        end
    end

    -- If the addon exists and load was attempted, allow the locale
    -- to remain selected and rely on dictionary registration to follow.
    if addon then
        self:ScheduleLocaleRefresh(locale)
        return true
    end
    return self:IsLocaleAvailable(locale)
end

function Spellcheck:ScheduleLocaleRefresh(locale)
    if self._pendingLocaleLoads[locale] then return end
    self._pendingLocaleLoads[locale] = true
    if C_Timer and C_Timer.NewTicker then
        local tries = 0
        C_Timer.NewTicker(0.2, function(ticker)
            tries = tries + 1
            if self:IsLocaleAvailable(locale) then
                self._pendingLocaleLoads[locale] = nil
                ticker:Cancel()
                if self:IsEnabled() then
                    self:ScheduleRefresh()
                end
                return
            end
            if tries >= 10 then
                self._pendingLocaleLoads[locale] = nil
                ticker:Cancel()
            end
        end)
    else
        self._pendingLocaleLoads[locale] = nil
    end
end

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
            local g = string_sub(word, i, i+1)
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
    local keys = {}
    for w, entry in pairs(dict._metaCache) do
        keys[#keys + 1] = { word = w, lastUsed = (entry and entry.lastUsed) or 0 }
    end
    if #keys == 0 then return end
    table_sort(keys, function(a, b) return a.lastUsed < b.lastUsed end)
    local removed = 0
    for i = 1, math_min(count, #keys) do
        local w = keys[i].word
        if dict._metaCache[w] then
            dict._metaCache[w] = nil
            removed = removed + 1
        end
    end
    dict._metaCacheSize = math_max(0, (dict._metaCacheSize or 0) - removed)
end

function Spellcheck:GetUserDictStore()
    if type(_G.YapperDB) ~= "table" then return nil end
    if type(_G.YapperDB.Spellcheck) ~= "table" then _G.YapperDB.Spellcheck = {} end
    if type(_G.YapperDB.Spellcheck.Dict) ~= "table" then _G.YapperDB.Spellcheck.Dict = {} end
    return _G.YapperDB.Spellcheck.Dict
end

-- Persist/restore a single cached dictionary (active locale) to SavedVariables
function Spellcheck:GetCachedDictStore()
    if type(_G.YapperDB) ~= "table" then return nil end
    if type(_G.YapperDB.Spellcheck) ~= "table" then _G.YapperDB.Spellcheck = {} end
    if type(_G.YapperDB.Spellcheck.Cache) ~= "table" then _G.YapperDB.Spellcheck.Cache = {} end
    return _G.YapperDB.Spellcheck.Cache
end

function Spellcheck:LoadCachedDictionary(locale)
    if type(locale) ~= "string" or locale == "" then return nil end
    local store = self:GetCachedDictStore()
    if not store or type(store[locale]) ~= "table" then return nil end
    -- Use cached structure directly (words, set, index, ngramIndex)
    self.Dictionaries[locale] = store[locale]
    return self.Dictionaries[locale]
end

function Spellcheck:SaveActiveDictionaryToDB(locale)
    if type(locale) ~= "string" or locale == "" then return end
    local dict = self.Dictionaries[locale]
    if type(dict) ~= "table" then return end
    local store = self:GetCachedDictStore()
    if not store then return end
    -- Only write once if cache missing or size changed to avoid repeated SavedVariable churn
    local existing = store[locale]
    if existing and type(existing.words) == "table" and #existing.words == #dict.words then
        return
    end
    local dump = {
        locale = dict.locale,
        words = dict.words,
        set = dict.set,
        index = dict.index,
        ngramIndex = dict.ngramIndex,
    }
    store[locale] = dump
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
            local norm = NormalizeWord(w)
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
    local norm = NormalizeWord(word)
    for _, w in ipairs(dict.AddedWords) do
        if NormalizeWord(w) == norm then
            return
        end
    end
    dict.AddedWords[#dict.AddedWords + 1] = word
    for i = #dict.IgnoredWords, 1, -1 do
        if NormalizeWord(dict.IgnoredWords[i]) == norm then
            table.remove(dict.IgnoredWords, i)
        end
    end
    self:TouchUserDict(dict)
    self:ApplyUserAddedWords(locale)
end

function Spellcheck:IgnoreWord(locale, word)
    if type(word) ~= "string" or word == "" then return end
    local dict = self:GetUserDict(locale)
    if not dict then return end
    local norm = NormalizeWord(word)
    for _, w in ipairs(dict.IgnoredWords) do
        if NormalizeWord(w) == norm then
            return
        end
    end
    dict.IgnoredWords[#dict.IgnoredWords + 1] = word
    for i = #dict.AddedWords, 1, -1 do
        if NormalizeWord(dict.AddedWords[i]) == norm then
            table.remove(dict.AddedWords, i)
        end
    end
    self:TouchUserDict(dict)
end

function Spellcheck:ApplyUserAddedWords(locale)
    -- User-added words are handled via user sets (added/ignored).
    -- Avoid mutating the base dictionary sets so manual edits can
    -- remove words cleanly without stale entries.
    self:GetUserSets(locale)
end

function Spellcheck:GetMaxSuggestions()
    local cfg = self:GetConfig()
    return Clamp(tonumber(cfg.MaxSuggestions) or 4, 1, 4)
end

function Spellcheck:GetMaxCandidates()
    local cfg = self:GetConfig()
    return Clamp(tonumber(cfg.MaxCandidates) or 800, 50, 5000)
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

function Spellcheck:Bind(editBox, overlay)
    self.EditBox = editBox
    self.Overlay = overlay
    self:EnsureMeasureFontString()
    self:EnsureSuggestionFrame()
    self:EnsureHintFrame()
    self:ScheduleRefresh()
    -- Support right-click on the editbox to open/cycle suggestions.
    if editBox and editBox.HookScript then
        editBox:HookScript("OnMouseUp", function(box, button)
            if button == "RightButton" then
                self:UpdateActiveWord()
                if self:IsSuggestionEligible() then
                    self:OpenOrCycleSuggestions()
                end
            end
        end)
    end
    -- Make hint frame clickable to open suggestions as well.
    if self.HintFrame then
        self.HintFrame:EnableMouse(true)
        self.HintFrame:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" and self:IsSuggestionEligible() then
                self:OpenOrCycleSuggestions()
            end
        end)
    end
end

function Spellcheck:PurgeOtherDictionaries(keepLocale)
    if self.Dictionaries then
        for locale, dict in pairs(self.Dictionaries) do
            if locale ~= keepLocale then
                -- Scrub internal tables first to reduce capacity before nil-ing
                dict.words = {"."}
                dict.set = {}
                dict.index = {}
                dict.ngramIndex = {}

                self.Dictionaries[locale] = nil
                self._debugLoadedLocales[locale] = nil
            end
        end
    end
    if self._asyncLoaders then
        for locale, loader in pairs(self._asyncLoaders) do
            if locale ~= keepLocale then
                loader.cancelled = true
                self._asyncLoaders[locale] = nil
            end
        end
    end
end

function Spellcheck:ApplyState(enabled, locale)
    if enabled == nil then enabled = self:IsEnabled() end
    if locale == nil then locale = self:GetLocale() end

    if enabled then
        self:PurgeOtherDictionaries(locale)
        if not self:EnsureLocale(locale) then
            return false
        end
    end
    self:ScheduleRefresh()
    return true
end

function Spellcheck:OnConfigChanged()
    self:ApplyState()
end

function Spellcheck:OnTextChanged(editBox, isUserInput)
    if editBox ~= self.EditBox then return end
    if isUserInput then
        -- Mark that the text changed due to user input so suggestion
        -- selection can run once for this change (not on caret moves).
        self._textChangedFlag = true
    end
    self:ScheduleRefresh()
end

function Spellcheck:OnCursorChanged(editBox, x, y, w, h)
    if editBox ~= self.EditBox then return end
    if self._suppressCursorUpdate and self:IsSuggestionOpen() then
        return
    end

    -- Capture the visual cursor X that Blizzard gives us.
    -- We use this to derive the editbox's internal horizontal scroll.
    if type(x) == "number" then
        self._lastCursorVisX = x
    end

    self:UpdateActiveWord()
    self:UpdateHint()

    -- Defer underline refresh to the next frame so we don't interfere
    -- with the EditBox's native cursor rendering during this callback.
    if not self._cursorRefreshPending then
        self._cursorRefreshPending = true
        C_Timer.After(0, function()
            self._cursorRefreshPending = nil
            self:UpdateUnderlines()
        end)
    end
end

function Spellcheck:OnOverlayHide()
    self:HideSuggestions()
    self:ClearUnderlines()
    self:HideHint()
end

function Spellcheck:ScheduleRefresh()
    if not self:IsEnabled() then
        self:HideSuggestions()
        self:ClearUnderlines()
        self:HideHint()
        return
    end

    if self._debounceTimer and self._debounceTimer.Cancel then
        self._debounceTimer:Cancel()
    end

    if C_Timer and C_Timer.NewTimer then
        self._debounceTimer = C_Timer.NewTimer(0.12, function()
            self:Rebuild()
        end)
    else
        self:Rebuild()
    end
end

function Spellcheck:Rebuild()
    if not self.EditBox then return end
    if not self:IsEnabled() then
        self:HideSuggestions()
        self:ClearUnderlines()
        self:HideHint()
        return
    end

    self:UpdateUnderlines()
    self:UpdateActiveWord()
    self:UpdateHint()
end

function Spellcheck:EnsureMeasureFontString()
    if self.MeasureFS or not self.Overlay then return end
    local fs = self.Overlay:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    fs:Hide()
    self.MeasureFS = fs
end

function Spellcheck:EnsureSuggestionFrame()
    if self.SuggestionFrame or not self.Overlay then return end

    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetFrameStrata("TOOLTIP")
    catcher:SetAllPoints(UIParent)
    catcher:RegisterForClicks("AnyUp", "AnyDown")
    catcher:SetScript("OnClick", function()
        self:HideSuggestions()
    end)
    catcher:Hide()
    self.SuggestionClickCatcher = catcher

    local frame = CreateFrame("Frame", nil, self.Overlay, "BackdropTemplate")
    frame:SetFrameStrata("TOOLTIP")
    frame:EnableMouse(true)
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    frame:SetBackdropBorderColor(0.9, 0.75, 0.2, 1)
    frame:Hide()

    local rows = {}
    for i = 1, MAX_SUGGESTION_ROWS do
        local btn = CreateFrame("Button", nil, frame)
        btn:SetSize(160, 18)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6 - ((i - 1) * 18))
        btn:EnableMouse(true)

        -- Highlight frame under the row to indicate selection. Use a
        -- small child frame with its own texture so it can be shown
        -- above the suggestion background reliably.
        local hlFrame = CreateFrame("Frame", nil, frame)
        hlFrame:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        hlFrame:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        hlFrame:SetFrameLevel(btn:GetFrameLevel() + 5)
        local hlTex = hlFrame:CreateTexture(nil, "ARTWORK")
        hlTex:SetAllPoints(hlFrame)
        hlTex:SetColorTexture(1, 1, 1, 0.08)
        hlFrame:Hide()

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", btn, "LEFT", 2, 0)
        fs:SetText("-")

        btn._fs = fs
        btn._hl = hlFrame
        btn._index = i
        local idx = i
        btn:SetScript("OnEnter", function()
            self.ActiveIndex = idx
            self:RefreshSuggestionSelection()
        end)
        btn:SetScript("OnClick", function()
            self:ApplySuggestion(idx)
        end)

        rows[i] = btn
    end

    self.SuggestionFrame = frame
    self.SuggestionRows = rows
end

function Spellcheck:SuggestionsEqual(a, b)
    if a == b then return true end
    if not a or not b then return false end
    if #a ~= #b then return false end
    for i = 1, #a do
        if SuggestionKey(a[i]) ~= SuggestionKey(b[i]) then return false end
    end
    return true
end

function Spellcheck:EnsureHintFrame()
    if self.HintFrame or not self.Overlay then return end
    local frame = CreateFrame("Frame", nil, self.Overlay, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    frame:SetBackdropBorderColor(0.9, 0.75, 0.2, 1)
    frame:Hide()

    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", frame, "LEFT", 6, 0)
    fs:SetTextColor(0.8, 0.8, 0.8, 1)
    fs:SetText("Shift+Tab: spell suggestions")

    frame._fs = fs
    self.HintFrame = frame
end

function Spellcheck:CancelHintTimer()
    if self._hintTimer and self._hintTimer.Cancel then
        self._hintTimer:Cancel()
    end
    self._hintTimer = nil
    self._pendingHintWord = nil
    self._pendingHintCursor = nil
end

-- Delay (seconds) before showing the hint after user stops typing.
Spellcheck.HintDelay = 0.25

function Spellcheck:ScheduleHintShow()
    if not self.HintFrame or not self.EditBox then return end
    local cursor = self.EditBox.GetCursorPosition and (self.EditBox:GetCursorPosition() or 0) or 0
    local word = self.ActiveWord
    -- If we already have a timer scheduled for the same word+cursor, leave it.
    if self._hintTimer and self._pendingHintWord == word and self._pendingHintCursor == cursor then
        return
    end
    self:CancelHintTimer()
    self._pendingHintWord = word
    self._pendingHintCursor = cursor
    if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        self:Notify("Spellcheck:ScheduleHintShow word='" .. tostring(word) .. "' cursor=" .. tostring(cursor))
    end
    if C_Timer and C_Timer.NewTimer then
        self._hintTimer = C_Timer.NewTimer(self.HintDelay, function()
            -- If caret or word moved, abort showing.
            if not self.EditBox then return end
            local curCursor = self.EditBox.GetCursorPosition and (self.EditBox:GetCursorPosition() or 0) or 0
            if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
                self:Notify("Spellcheck:HintTimer fired; curCursor=" .. tostring(curCursor) .. " pending=" .. tostring(self._pendingHintCursor))
            end
            if curCursor ~= self._pendingHintCursor then
                if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
                    self:Notify("Spellcheck:HintTimer abort due to cursor move")
                end
                return
            end
            if self.ActiveWord ~= self._pendingHintWord then
                if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
                    self:Notify("Spellcheck:HintTimer abort due to word change")
                end
                return
            end
            self:ShowHint()
            if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
                self:Notify("Spellcheck:HintTimer showing hint")
            end
            self._lastHintWord = self._pendingHintWord
            self._lastHintCursor = self._pendingHintCursor
            self._pendingHintWord = nil
            self._pendingHintCursor = nil
            self._hintTimer = nil
        end)
    else
        -- Fallback: immediate show
        if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
            self:Notify("Spellcheck:ScheduleHintShow immediate fallback show")
        end
        self:ShowHint()
        self._lastHintWord = self._pendingHintWord
        self._lastHintCursor = self._pendingHintCursor
        self._pendingHintWord = nil
        self._pendingHintCursor = nil
    end
end

function Spellcheck:ShowHint()
    if not self.HintFrame or not self.EditBox then return end
    
    local fontSize = self:ApplyOverlayFont(self.HintFrame._fs, 22)
    local hintHeight = math_max(20, fontSize + 8)
    local hintWidth = self.HintFrame._fs:GetStringWidth() + 12
    self.HintFrame:SetSize(hintWidth, hintHeight)

    -- Avoid re-showing (and retriggering fade) if already visible.
    if self.HintFrame:IsShown() then return end
    self.HintFrame:ClearAllPoints()
    self.HintFrame:SetPoint("TOPLEFT", self.EditBox, "BOTTOMLEFT", 0, -2)
    self.HintFrame:SetAlpha(0)
    self.HintFrame:Show()
    if UIFrameFadeIn then
        UIFrameFadeIn(self.HintFrame, 0.12, 0, 1)
    else
        self.HintFrame:SetAlpha(1)
    end
end

function Spellcheck:HideHint()
    if not self.HintFrame then return end
    self.HintFrame:Hide()
end

function Spellcheck:UpdateHint()
    if not self.EditBox then return end

    -- Only show the hint when a suggestion is eligible and the caret/word
    -- has changed since the last hint state. This reduces flicker caused by
    -- frequent OnUpdate/OnTextChanged refreshes.
    local cursor = self.EditBox.GetCursorPosition and (self.EditBox:GetCursorPosition() or 0) or 0
    local word = self.ActiveWord

    if self:IsSuggestionEligible() then
        if self._lastHintWord ~= word or self._lastHintCursor ~= cursor then
            -- Schedule a delayed hint show so it doesn't flash while typing.
            self:ScheduleHintShow()
        end
    else
        if self.HintFrame and self.HintFrame:IsShown() then
            self:HideHint()
            self._lastHintWord = nil
            self._lastHintCursor = nil
        end
    end
end

function Spellcheck:IsSuggestionOpen()
    return self.SuggestionFrame and self.SuggestionFrame:IsShown()
end

function Spellcheck:IsSuggestionEligible()
    if not self:IsEnabled() then return false end
    if not self.ActiveWord then return false end
    return true
end

function Spellcheck:HandleKeyDown(key)
    if not self:IsEnabled() then return false end
    -- Use Shift+Tab to open or cycle suggestions when eligible.
    if key == "TAB" and IsShiftKeyDown() then
        if self:IsSuggestionEligible() then
            self:OpenOrCycleSuggestions()
            return true
        end
        return false
    end

    if self:IsSuggestionOpen() then
        if key == "UP" then
            self._suppressCursorUpdate = true
            if C_Timer and C_Timer.NewTimer then
                C_Timer.NewTimer(0, function()
                    self._suppressCursorUpdate = nil
                end)
            end
            self:MoveSelection(-1)
            return true
        end
        if key == "DOWN" then
            self._suppressCursorUpdate = true
            if C_Timer and C_Timer.NewTimer then
                C_Timer.NewTimer(0, function()
                    self._suppressCursorUpdate = nil
                end)
            end
            self:MoveSelection(1)
            return true
        end
        if key == "ENTER" or key == "NUMPADENTER" then
            -- Accept currently selected suggestion and prevent the enter
            -- from being handled as a send.
            local idx = self.ActiveIndex or 1
            self:ApplySuggestion(idx)
            return true
        end
        if key == "1" or key == "2" or key == "3" or key == "4" or key == "5" or key == "6" then
            -- Set suppression before applying so OnChar won't append the digit.
            self._suppressNextChar = true
            self._suppressChar = key
            -- For non-replacement actions (add/ignore), keep the current
            -- text/cursor as the expected state so OnChar can restore it.
            if self.EditBox then
                self._expectedText = self.EditBox:GetText() or ""
                self._expectedCursor = self.EditBox:GetCursorPosition()
            end
            self:ApplySuggestion(tonumber(key))
            return true
        end
    end

    return false
end

function Spellcheck:MoveSelection(delta)
    local count = #self.ActiveSuggestions
    if count == 0 then return end
    local nextIdx = self.ActiveIndex + delta
    if nextIdx < 1 then nextIdx = count end
    if nextIdx > count then nextIdx = 1 end
    self.ActiveIndex = nextIdx
    self:RefreshSuggestionSelection()
end

function Spellcheck:RefreshSuggestionSelection()
    if not self.ActiveSuggestions then return end
    local count = #self.ActiveSuggestions
    if count == 0 then
        for _, row in ipairs(self.SuggestionRows) do row._hl:Hide() end
        return
    end
    if not self.ActiveIndex or self.ActiveIndex < 1 then self.ActiveIndex = 1 end
    if self.ActiveIndex > count then self.ActiveIndex = count end
    for i, row in ipairs(self.SuggestionRows) do
        if i == self.ActiveIndex then
            row._hl:Show()
        else
            row._hl:Hide()
        end
    end
end

function Spellcheck:OpenOrCycleSuggestions()
    if not self:IsSuggestionEligible() then
        self:HideSuggestions()
        return
    end

    if self:IsSuggestionOpen() then
        self:MoveSelection(1)
        return
    end

    local suggestions = self:GetSuggestions(self.ActiveWord)
    if type(suggestions) ~= "table" then suggestions = {} end
    local sugCount = #suggestions
    if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        self:Notify("Spellcheck:OpenOrCycleSuggestions word='" .. tostring(self.ActiveWord) .. "' suggestions=" .. tostring(sugCount))
    end
    if sugCount == 0 then
        self:HideSuggestions()
        return
    end

    self.ActiveSuggestions = suggestions
    self.ActiveIndex = 1
    self:ShowSuggestions()
end

function Spellcheck:ShowSuggestions()
    if not self.SuggestionFrame then return end
    if not self.ActiveSuggestions then return end

    -- If the suggestion frame is already visible and the suggestions
    -- haven't changed, skip updating to avoid per-frame work and debug spam.
    if self.SuggestionFrame:IsShown() and self._lastShownSuggestions and self:SuggestionsEqual(self.ActiveSuggestions, self._lastShownSuggestions) then
        return
    end

    local editBox = self.EditBox
    local x = self:GetCaretXOffset()
    self.SuggestionFrame:ClearAllPoints()
    -- Anchor above the editbox so the suggestions appear on top of the overlay.
    self.SuggestionFrame:SetPoint("BOTTOMLEFT", editBox, "TOPLEFT", x, 4)

    local fontSize = 10
    local editBox = self.EditBox
    if editBox and editBox.GetFont then
        local _, sz = editBox:GetFont()
        if sz then fontSize = sz end
    end
    local rowHeight = math_max(18, fontSize + 4)

    local maxWidth = 160
    for i = 1, #self.SuggestionRows do
        local row = self.SuggestionRows[i]
        self:ApplyOverlayFont(row._fs)
        
        row:ClearAllPoints()
        row:SetSize(maxWidth, rowHeight)
        row:SetPoint("TOPLEFT", self.SuggestionFrame, "TOPLEFT", 6, -6 - ((i - 1) * rowHeight))
        
        local entry = self.ActiveSuggestions[i]
        if entry then
            row._fs:SetText(self:FormatSuggestionLabel(entry, i))
            row:Show()
            local w = row._fs:GetStringWidth() + 30
            if w > maxWidth then maxWidth = w end
        else
            row:Hide()
        end
    end

    for i = 1, #self.SuggestionRows do
        self.SuggestionRows[i]:SetWidth(maxWidth)
    end

    local visibleCount = math_min(#self.ActiveSuggestions, #self.SuggestionRows)
    self.SuggestionFrame:SetSize(maxWidth + 10, (visibleCount * rowHeight) + 12)
    self:RefreshSuggestionSelection()
    if self.SuggestionClickCatcher then
        self.SuggestionClickCatcher:Show()
    end
    self.SuggestionFrame:Show()
    self._lastShownSuggestions = self.ActiveSuggestions
end

function Spellcheck:HideSuggestions()
    if self.SuggestionFrame then
        self.SuggestionFrame:Hide()
    end
    if self.SuggestionClickCatcher then
        self.SuggestionClickCatcher:Hide()
    end
    self.ActiveSuggestions = nil
    self.ActiveIndex = 1
    self._lastShownSuggestions = nil
end

function Spellcheck:ApplySuggestion(index)
    if not self.ActiveSuggestions or not self.ActiveRange then return end
    local entry = self.ActiveSuggestions[index]
    if not entry then return end

    -- Mark that a suggestion was just applied so higher-level Enter
    -- handlers can swallow the following Enter (applied via keyboard).
    self._justAppliedSuggestion = true
    if C_Timer and C_Timer.NewTimer then
        C_Timer.NewTimer(0.05, function()
            self._justAppliedSuggestion = nil
        end)
    end

    if type(entry) == "table" and entry.kind == "add" then
        local locale = self:GetLocale()
        self:AddUserWord(locale, entry.value or self.ActiveWord)
        if self.EditBox then
            self._expectedText = self.EditBox:GetText() or ""
            self._expectedCursor = self.EditBox:GetCursorPosition()
        end
        self:HideSuggestions()
        self._textChangedFlag = true
        -- Invalidate underline cache — user sets changed, not the text.
        self._lastUnderlinesText = nil
        self:ScheduleRefresh()
        return
    elseif type(entry) == "table" and entry.kind == "ignore" then
        local locale = self:GetLocale()
        self:IgnoreWord(locale, entry.value or self.ActiveWord)
        if self.EditBox then
            self._expectedText = self.EditBox:GetText() or ""
            self._expectedCursor = self.EditBox:GetCursorPosition()
        end
        self:HideSuggestions()
        self._textChangedFlag = true
        -- Invalidate underline cache — user sets changed, not the text.
        self._lastUnderlinesText = nil
        self:ScheduleRefresh()
        return
    end

    local replacement = (type(entry) == "table") and (entry.value or entry.word) or entry
    if not replacement then return end

    local text = self.EditBox and self.EditBox:GetText() or ""
    local startPos = self.ActiveRange.startPos
    local endPos = self.ActiveRange.endPos
    if not startPos or not endPos then return end

    local before = text:sub(1, startPos - 1)
    local after = text:sub(endPos + 1)
    local newText = before .. replacement .. after

    -- Snapshot the pre-replacement text so we can seamlessly Undo (Ctrl+Z) 
    -- spellchecker corrections even if the new word is the same length.
    if YapperTable and YapperTable.History and self.EditBox then
        YapperTable.History:AddSnapshot(self.EditBox, true)
    end

    self.EditBox:SetText(newText)
    local cursorPos = #before + #replacement
    self.EditBox:SetCursorPosition(cursorPos)
    -- Prevent the following character insertion (numeric hotkey) from
    -- being appended to the editbox; EditBox.OnTextChanged will remove it.
    self._suppressNextChar = true
    self._suppressChar = tostring(index)
    self._expectedText = newText
    self._expectedCursor = cursorPos
    self:HideSuggestions()
    self._textChangedFlag = true
    self:ScheduleRefresh()
end

function Spellcheck:GetCaretXOffset()
    local editBox = self.EditBox
    local text = editBox and editBox:GetText() or ""
    local cursor = editBox and editBox:GetCursorPosition() or #text
    local prefix = text:sub(1, cursor)
    local leftInset = 0
    if editBox and editBox.GetTextInsets then
        leftInset = select(1, editBox:GetTextInsets()) or 0
    end
    local width = self:MeasureText(prefix)
    return leftInset + width
end

function Spellcheck:ApplyOverlayFont(fontString, maxSize)
    local editBox = self.EditBox
    if not editBox or not editBox.GetFont then return 10 end
    local face, size, flags = editBox:GetFont()
    if face and size then
        if maxSize and size > maxSize then size = maxSize end
        local curFace, curSize, curFlags = fontString:GetFont()
        if curFace ~= face or curSize ~= size or curFlags ~= flags then
            fontString:SetFont(face, size, flags or "")
        end
    end
    return size or 10
end

function Spellcheck:MeasureText(text)
    if not self.MeasureFS then return 0 end
    local editBox = self.EditBox
    if editBox and editBox.GetFont then
        local face, size, flags = editBox:GetFont()
        if face and size then
            local curFace, curSize, curFlags = self.MeasureFS:GetFont()
            if curFace ~= face or curSize ~= size or curFlags ~= flags then
                self.MeasureFS:SetFont(face, size, flags or "")
            end
        end
    end
    self.MeasureFS:SetText(text or "")
    return self.MeasureFS:GetStringWidth() or 0
end

-- Derive the horizontal scroll offset of a single-line EditBox.
-- WoW doesn't expose GetHorizontalScroll() for EditBoxes; we use the
-- visual cursor X that Blizzard passes to OnCursorChanged instead.
function Spellcheck:GetScrollOffset()
    if not self.EditBox or not self._lastCursorVisX then return 0 end
    local cursor = self.EditBox:GetCursorPosition() or 0
    if cursor == 0 then return 0 end
    local text = self.EditBox:GetText() or ""
    local prefix = text:sub(1, cursor)
    local absoluteX = self:MeasureText(prefix)
    local leftInset = 0
    if self.EditBox.GetTextInsets then
        leftInset = select(1, self.EditBox:GetTextInsets()) or 0
    end
    local offset = (leftInset + absoluteX) - self._lastCursorVisX
    return offset > 0 and offset or 0
end

-- Maximum number of characters to scan around the cursor for misspellings.
-- Configurable for devs; larger values scan more text but cost more CPU per rebuild.
local SCAN_RADIUS = 1000

-- Re-center the scan window when the cursor is within this many characters
-- of the window edge. Prevents the user from reaching un-checked text.
local SCAN_RECENTER_MARGIN = 200

function Spellcheck:UpdateUnderlines()
    if not self.EditBox then return end

    local dict = self:GetDictionary()
    if not dict then return end

    local text = self.EditBox:GetText() or ""
    if text == "" then
        self._lastUnderlinesText = nil
        self._lastUnderlinesDict = nil
        self._lastScrollOffset = nil
        self._scanWindowStart = nil
        self._scanWindowEnd = nil
        self:ClearUnderlines()
        return
    end

    local textLen = #text
    local cursor = self.EditBox:GetCursorPosition() or textLen
    local scrollOffset = self:GetScrollOffset()

    -- For short texts, scan everything (no window overhead).
    -- The dictionary scan is cached on text+dict identity.
    -- Scroll changes only need a redraw, not a rescan.
    if textLen <= SCAN_RADIUS * 2 then
        local textSame = (self._lastUnderlinesText == text and self._lastUnderlinesDict == dict)
        local scrollSame = (self._lastScrollOffset == scrollOffset)
        if textSame and scrollSame then
            return
        end

        -- If only the scroll changed, reuse the cached misspelling list.
        if textSame and self._lastMisspellings then
            self._lastScrollOffset = scrollOffset
            self:ClearUnderlines()
            for _, item in ipairs(self._lastMisspellings) do
                self:DrawUnderline(item.startPos, item.endPos, text, scrollOffset)
            end
            return
        end

        self._lastUnderlinesText = text
        self._lastUnderlinesDict = dict
        self._lastScrollOffset = scrollOffset
        self._scanWindowStart = nil
        self._scanWindowEnd = nil
        self:ClearUnderlines()

        local words = self:CollectMisspellings(text, dict)
        self._lastMisspellings = words
        for _, item in ipairs(words) do
            self:DrawUnderline(item.startPos, item.endPos, text, scrollOffset)
        end
        return
    end

    -- Large text: use a scan window centered on the cursor.
    local needRescan = false
    if not self._scanWindowStart or not self._scanWindowEnd then
        needRescan = true
    elseif self._lastUnderlinesText ~= text or self._lastUnderlinesDict ~= dict then
        needRescan = true
    else
        if cursor - self._scanWindowStart < SCAN_RECENTER_MARGIN
           or self._scanWindowEnd - cursor < SCAN_RECENTER_MARGIN then
            needRescan = true
        end
    end

    local scrollSame = (self._lastScrollOffset == scrollOffset)

    if not needRescan and scrollSame then
        return
    end

    -- Scroll-only change with cached misspellings: just redraw.
    if not needRescan and self._lastMisspellings then
        self._lastScrollOffset = scrollOffset
        self:ClearUnderlines()
        for _, item in ipairs(self._lastMisspellings) do
            self:DrawUnderline(item.startPos, item.endPos, text, scrollOffset)
        end
        return
    end

    self._lastUnderlinesText = text
    self._lastUnderlinesDict = dict
    self._lastScrollOffset = scrollOffset

    -- Build the window centered on the cursor, clamped to text bounds
    local rawStart = math_max(1, cursor - SCAN_RADIUS)
    local rawEnd = math_min(textLen, cursor + SCAN_RADIUS)

    -- Snap start forward to the next word boundary (skip partial word)
    if rawStart > 1 then
        while rawStart <= rawEnd do
            local b = string_byte(text, rawStart)
            if not b or not IsWordByte(b) then break end
            rawStart = rawStart + 1
        end
    end

    -- Snap end backward to the previous word boundary (skip partial word)
    if rawEnd < textLen then
        while rawEnd >= rawStart do
            local b = string_byte(text, rawEnd)
            if not b or not IsWordByte(b) then break end
            rawEnd = rawEnd - 1
        end
    end

    self._scanWindowStart = rawStart
    self._scanWindowEnd = rawEnd

    self:ClearUnderlines()

    local windowText = string_sub(text, rawStart, rawEnd)
    local words = self:CollectMisspellings(windowText, dict)

    -- Convert window-local positions to full-text positions and cache.
    local fullPosWords = {}
    for _, item in ipairs(words) do
        fullPosWords[#fullPosWords + 1] = {
            startPos = item.startPos + rawStart - 1,
            endPos = item.endPos + rawStart - 1,
        }
    end
    self._lastMisspellings = fullPosWords

    for _, item in ipairs(fullPosWords) do
        self:DrawUnderline(item.startPos, item.endPos, text, scrollOffset)
    end
end

function Spellcheck:DrawUnderline(startPos, endPos, text, scrollOffset)
    if not self.EditBox or not self.Overlay then return end

    local leftInset = 0
    local rightInset = 0
    if self.EditBox.GetTextInsets then
        leftInset, rightInset = self.EditBox:GetTextInsets()
        leftInset = leftInset or 0
        rightInset = rightInset or 0
    end

    local prefix = text:sub(1, startPos - 1)
    local word = text:sub(startPos, endPos)
    local x = leftInset + self:MeasureText(prefix) - (scrollOffset or 0)
    local w = self:MeasureText(word)

    -- Clamp to the visible text area so underlines don't escape the EditBox.
    local visibleWidth = (self.EditBox:GetWidth() or 200) - leftInset - rightInset

    -- Entirely off-screen -> skip.
    if (x + w) <= 0 or x >= visibleWidth then return end

    -- Partially off the left edge -> trim.
    if x < 0 then
        w = w + x
        x = 0
    end
    -- Partially off the right edge -> trim.
    if (x + w) > visibleWidth then
        w = visibleWidth - x
    end
    if w <= 0 then return end

    -- Compute the EditBox's offset within the Overlay so we can anchor
    -- textures to the Overlay instead of the EditBox. This avoids a
    -- layout dependency that resets the EditBox's cursor blink timer.
    local ebLeft = self.EditBox:GetLeft() or 0
    local ovLeft = self.Overlay:GetLeft() or 0
    local ebBottom = self.EditBox:GetBottom() or 0
    local ovTop = self.Overlay:GetTop() or 0
    local ebTop = self.EditBox:GetTop() or 0
    local offsetX = (ebLeft - ovLeft) + x
    local offsetTopY = -(ovTop - ebTop)  -- negative because Y grows downward in SetPoint

    local tex = self:AcquireUnderline()
    local style = self:GetUnderlineStyle()

    if style == "highlight" then
        local height = (self.EditBox:GetHeight() or 20) - 6
        -- Brighter highlight for better visibility (increased alpha
        -- and slightly adjusted tint).
        tex:SetColorTexture(1, 0.18, 0.18, 0.36)
        tex:SetSize(w, height)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", self.Overlay, "TOPLEFT", offsetX, offsetTopY - 3)
    else
        local ovBottom = self.Overlay:GetBottom() or 0
        local offsetBottomY = ebBottom - ovBottom
        tex:SetColorTexture(1, 0.2, 0.2, 0.9)
        tex:SetSize(w, 2)
        tex:ClearAllPoints()
        tex:SetPoint("BOTTOMLEFT", self.Overlay, "BOTTOMLEFT", offsetX, offsetBottomY + 2)
    end

    tex:Show()
    self.Underlines[#self.Underlines + 1] = tex
end

function Spellcheck:AcquireUnderline()
    local tex = table_remove(self.UnderlinePool)
    if tex then
        return tex
    end
    tex = self.Overlay:CreateTexture(nil, "OVERLAY")
    return tex
end

function Spellcheck:ClearUnderlines()
    for i = 1, #self.Underlines do
        local tex = self.Underlines[i]
        tex:Hide()
        self.UnderlinePool[#self.UnderlinePool + 1] = tex
    end
    self.Underlines = {}
end

function Spellcheck:CollectMisspellings(text, dict)
    local out = {}
    local minLen = self:GetMinWordLength()
    local ignoreRanges = self:GetIgnoredRanges(text)
    local addedSet, ignoredSet = self:GetUserSets(self:GetLocale())

    local idx = 1
    while idx <= #text do
        local byte = text:byte(idx)
        if not byte then break end

        if IsWordStartByte(byte) then
            local s = idx
            idx = idx + 1
            while idx <= #text do
                local b = text:byte(idx)
                if not b or not IsWordByte(b) then break end
                idx = idx + 1
            end
            local e = idx - 1
            local word = text:sub(s, e)
            local norm = NormalizeWord(word)
            if not self:IsRangeIgnored(s, e, ignoreRanges)
                and self:ShouldCheckWord(word, minLen)
                and not (ignoredSet and ignoredSet[norm])
                and not (addedSet and addedSet[norm])
                and not dict.set[norm]
                and not dict.set[word] then
                out[#out + 1] = { startPos = s, endPos = e, word = word }
            end
        else
            idx = idx + 1
        end
    end

    return out
end

function Spellcheck:ShouldCheckWord(word, minLen)
    if #word < minLen then return false end
    if word:find("%d") then return false end
    if word:find("[A-Za-z]") and word == word:upper() then return false end
    return true
end

function Spellcheck:GetIgnoredRanges(text)
    local ranges = {}
    local idx = 1
    while true do
        local s, e = text:find("|H.-|h.-|h", idx)
        if not s then break end
        ranges[#ranges + 1] = { startPos = s, endPos = e }
        idx = e + 1
    end
    idx = 1
    while true do
        local s, e = text:find("|c%x%x%x%x%x%x%x%x.-|r", idx)
        if not s then break end
        ranges[#ranges + 1] = { startPos = s, endPos = e }
        idx = e + 1
    end
    idx = 1
    while true do
        local s, e = text:find("|T.-|t", idx)
        if not s then break end
        ranges[#ranges + 1] = { startPos = s, endPos = e }
        idx = e + 1
    end
    idx = 1
    while true do
        local s, e = text:find("|A.-|a", idx)
        if not s then break end
        ranges[#ranges + 1] = { startPos = s, endPos = e }
        idx = e + 1
    end
    return ranges
end

function Spellcheck:IsRangeIgnored(startPos, endPos, ranges)
    for _, range in ipairs(ranges) do
        if startPos <= range.endPos and endPos >= range.startPos then
            return true
        end
    end
    return false
end

function Spellcheck:UpdateActiveWord()
    if not self.EditBox then return end

    local text = self.EditBox:GetText() or ""
    local cursor = self.EditBox:GetCursorPosition() or #text
    local dict = self:GetDictionary()
    local prevWord = self.ActiveWord
    local prevSuggestions = self.ActiveSuggestions
    local prevIndex = self.ActiveIndex

    if not dict or text == "" then
        self.ActiveWord = nil
        self.ActiveRange = nil
        self:HideSuggestions()
        return
    end

    local wordInfo = self:GetWordAtCursor(text, cursor)
    if not wordInfo then
        self.ActiveWord = nil
        self.ActiveRange = nil
        self:HideSuggestions()
        return
    end

    local norm = NormalizeWord(wordInfo.word)
    local addedSet, ignoredSet = self:GetUserSets(self:GetLocale())
    if dict.set[norm] or dict.set[wordInfo.word] or (addedSet and addedSet[norm]) then
        self.ActiveWord = nil
        self.ActiveRange = nil
        self:HideSuggestions()
        return
    end
    if ignoredSet and ignoredSet[norm] then
        self.ActiveWord = nil
        self.ActiveRange = nil
        self:HideSuggestions()
        return
    end

    self.ActiveWord = wordInfo.word
    self.ActiveRange = { startPos = wordInfo.startPos, endPos = wordInfo.endPos }

    if self:IsSuggestionOpen() then
        local currentText = text or ""
        local locale = self:GetLocale()
        local userCache = self.UserDictCache[locale]
        local userRev = userCache and userCache._rev or nil

        local needCompute = false
        if self._textChangedFlag then
            needCompute = true
        elseif not self._lastSuggestionsText or self._lastSuggestionsText ~= currentText
            or self._lastSuggestionsLocale ~= locale
            or self._lastSuggestionsUserRev ~= userRev then
            needCompute = true
        end

        local suggestions = nil
        if needCompute then
            suggestions = self:GetSuggestions(self.ActiveWord)
            self._lastSuggestionsText = currentText
            self._lastSuggestionsLocale = locale
            self._lastSuggestionsUserRev = userRev
            self._textChangedFlag = false
        else
            suggestions = self.ActiveSuggestions or {}
        end

        if #suggestions == 0 then
            self:HideSuggestions()
        else
            self.ActiveSuggestions = suggestions
            if prevWord == self.ActiveWord and self:SuggestionsEqual(prevSuggestions, suggestions) then
                self.ActiveIndex = prevIndex or 1
            else
                self.ActiveIndex = 1
            end
            self:ShowSuggestions()
        end
    end
end

function Spellcheck:GetWordAtCursor(text, cursor)
    local caret = cursor + 1
    local ignoreRanges = self:GetIgnoredRanges(text)
    local minLen = self:GetMinWordLength()
    local idx = 1
    while idx <= #text do
        local byte = text:byte(idx)
        if not byte then break end
        if IsWordStartByte(byte) then
            local s = idx
            idx = idx + 1
            while idx <= #text do
                local b = text:byte(idx)
                if not b or not IsWordByte(b) then break end
                idx = idx + 1
            end
            local e = idx - 1
            local word = text:sub(s, e)
            if caret >= s and caret <= (e + 1)
                and not self:IsRangeIgnored(s, e, ignoreRanges)
                and self:ShouldCheckWord(word, minLen) then
                return { word = word, startPos = s, endPos = e }
            end
        else
            idx = idx + 1
        end
    end
    return nil
end

function Spellcheck:GetSuggestions(word)
    local dict = self:GetDictionary()
    if not dict then
        if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
            self:Notify("Spellcheck:GetSuggestions no dictionary for locale")
        end
        return {}
    end

    local locale = self:GetLocale()
    local userCache = self.UserDictCache[locale]
    local userRev = userCache and userCache._rev or nil

    local maxCount = self:GetMaxSuggestions()
    local lower = NormalizeWord(word)

    -- Suggestion cache: reuse recent result when the input word,
    -- dictionary and user-added/ignored lists haven't changed.
    self._suggestionCache = self._suggestionCache or {}
    local sc = self._suggestionCache
    local maxCandidates = (type(self.GetMaxCandidates) == "function") and self:GetMaxCandidates() or 200
    if sc.word == lower and sc.dict == dict and sc.userRev == userRev and sc.locale == locale and sc.maxCandidates == maxCandidates then
        return sc.result or {}
    end
    local first = lower:sub(1, 1)
    -- Build a stable candidate list copy so we can append user-added words
    local base = {}
    local srcCandidates = dict.index[first]
    if srcCandidates then
        for _, v in ipairs(srcCandidates) do base[#base+1] = v end
    end

    -- Assemble user-added words (normalized) explicitly to bypass array caps
    local addedCandidates = {}
    local userDict = self:GetUserDict(locale)
    if userDict and type(userDict.AddedWords) == "table" then
        for _, uw in ipairs(userDict.AddedWords) do
            if type(uw) == "string" and uw ~= "" then
                local norm = NormalizeWord(uw)
                if norm ~= "" then
                    addedCandidates[#addedCandidates+1] = norm
                end
            end
        end
    end

    local candidates = base
    -- N-gram (bigram) preselection: compute ranked candidate list
    local ngramCandidates = nil
    local useNgram = (YapperTable and YapperTable.Config and YapperTable.Config.Spellcheck and YapperTable.Config.Spellcheck.UseNgramIndex) or false
    local ngramN = (YapperTable and YapperTable.Config and YapperTable.Config.Spellcheck and YapperTable.Config.Spellcheck.NgramN) or 2
    local ngramTop = (YapperTable and YapperTable.Config and YapperTable.Config.Spellcheck and YapperTable.Config.Spellcheck.NgramTopCandidates) or 300
    if useNgram and dict.ngramIndex and #lower >= ngramN then
        local hits = {}
        for i = 1, (#lower - ngramN + 1) do
            local g = lower:sub(i, i + ngramN - 1)
            local posting = dict.ngramIndex[g]
            if posting then
                for _, id in ipairs(posting) do
                    hits[id] = (hits[id] or 0) + 1
                end
            end
        end
        local tmp = {}
        local lowerLen = #lower
        for id, cnt in pairs(hits) do
            local w = dict.words[id]
            if w then
                local wLen = #w
                local lenDiff = math_abs(wLen - lowerLen)
                -- Pseudo Jaccard/Dice coefficient weighting
                local score = (2 * cnt) / (lowerLen + wLen) - (lenDiff * 0.1)
                
                if string_byte(w, 1) == string_byte(lower, 1) then
                    score = score + 0.1
                end
                
                tmp[#tmp + 1] = { id = id, score = score }
            end
        end
        table_sort(tmp, function(a, b)
            if a.score == b.score then return a.id < b.id end
            return a.score > b.score
        end)
        ngramCandidates = {}
        for i = 1, math_min(#tmp, ngramTop) do
            local id = tmp[i].id
            if dict.words and dict.words[id] then
                ngramCandidates[#ngramCandidates + 1] = dict.words[id]
            end
        end
        if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
            self:Notify("Spellcheck:GetSuggestions ngramCandidates=" .. tostring(#ngramCandidates) .. " for word='" .. tostring(lower) .. "'")
        end
    end
    if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        self:Notify("Spellcheck:GetSuggestions word='" .. tostring(word) .. "' lower='" .. tostring(lower) .. "' locale='" .. tostring(locale) .. "' candidates=" .. tostring(#candidates))
    end
    local addedSet, ignoredSet = self:GetUserSets(self:GetLocale())
    local out = {}

    local maxDist = (#lower <= 4) and 2 or 3
    local maxLenDiff = maxDist + 1

    local function CommonPrefixLen(a, b)
        local len = math_min(#a, #b)
        for i = 1, len do
            if string_byte(a, i) ~= string_byte(b, i) then return i - 1 end
        end
        return len
    end

    -- Build input word metadata into reusable scratch tables to avoid allocations.
    -- Uses byte keys for the bag to match GetMeta's byte-keyed bags.
    local function buildInputMeta(lower)
        local bag = self._scratchBag
        if not bag then
            bag = {}
            self._scratchBag = bag
        end
        for k in pairs(bag) do bag[k] = nil end
        for i = 1, #lower do
            local ch = string_byte(lower, i)
            bag[ch] = (bag[ch] or 0) + 1
        end
        local bigrams = self._scratchBigrams
        if not bigrams then
            bigrams = {}
            self._scratchBigrams = bigrams
        end
        for k in pairs(bigrams) do bigrams[k] = nil end
        if #lower >= 2 then
            for i = 1, (#lower - 1) do
                local g = string_sub(lower, i, i+1)
                bigrams[g] = (bigrams[g] or 0) + 1
            end
        end
        return bag, bigrams
    end

    local inputBag, inputBigrams = buildInputMeta(lower)

    local function LetterBagScore(candidate)
        -- Lazily fetch/build per-word metadata. Lower is better.
        local meta = self:GetMeta(dict, candidate)
        if not meta or not meta.bag then return 999 end
        local score = 0
        -- sum absolute differences between candidate bag and input bag
        for ch, cnt in pairs(meta.bag) do
            local inCnt = inputBag[ch] or 0
            local d = cnt - inCnt
            if d ~= 0 then score = score + math_abs(d) end
        end
        -- also count letters present in input but not in candidate
        for ch, cnt in pairs(inputBag) do
            if not meta.bag[ch] then score = score + math_abs(cnt) end
        end
        return score
    end

    local function BigramOverlap(candidate)
        -- Use lazily-built candidate bigrams and input bigram counts.
        local meta = self:GetMeta(dict, candidate)
        if not meta or not meta.bigrams then return 0 end
        local count = 0
        for g, cnt in pairs(meta.bigrams) do
            local inCnt = inputBigrams[g] or 0
            if inCnt > 0 then
                count = count + math_min(cnt, inCnt)
            end
        end
        return count
    end

    -- Hoist config values that don't change between candidates
    local maxWrong = self:GetMaxWrongLetters() or 4
    local lowerLen = #lower

    -- Pre-compute apostrophe-stripped version of lower once
    local lHasApostrophe = lower:find("'", 1, true)
    local lFlat = lHasApostrophe and string_gsub(lower, "'", "") or lower

    -- LocaleVariantBonus: declared once outside tryAdd to avoid closure re-creation
    local isVariantLocale = (locale == "enGB" or locale == "enUS")
    local function LocaleVariantBonus(input, cand)
        if not isVariantLocale then return 0 end

        local function check(p1, p2)
            return string_gsub(input, p1, p2) == cand or string_gsub(cand, p1, p2) == input
        end

        if check("or", "our") then return 5.0 end
        if check("ize", "ise") then return 4.0 end
        if check("er", "re") then return 4.0 end
        if check("og", "ogue") then return 3.0 end
        if check("l", "ll") then return 3.0 end
        return 0
    end

    -- Pre-fetch keyboard distance table once (lazy-built, cached across calls)
    local kbDist = self:GetKBDistTable()

    -- Pre-convert input word to byte array for proximity scan (reuse buffer)
    local lowerBytes = self._kbLowerBytes
    if not lowerBytes then lowerBytes = {}; self._kbLowerBytes = lowerBytes end
    for i = 1, lowerLen do lowerBytes[i] = string_byte(lower, i) end

    local function tryAdd(candidate, dist)
        local candidateLen = #candidate
        local lenDiff = math_abs(candidateLen - lowerLen)
        local prefix = CommonPrefixLen(lower, candidate)
        local bagScore = LetterBagScore(candidate)
        local bigramScore = BigramOverlap(candidate)

        local longerPenalty = 0
        if candidateLen > lowerLen then
            local over = (candidateLen - lowerLen)
            local factor = 1 + ((bagScore / math_max(1, maxWrong)) * 0.5)
            longerPenalty = over * SCORE_WEIGHTS.longerPenalty * factor
        end

        local score = dist
            + (lenDiff * SCORE_WEIGHTS.lenDiff)
            + longerPenalty
            - (prefix * SCORE_WEIGHTS.prefix)
            + (bagScore * SCORE_WEIGHTS.letterBag)
            - (bigramScore * SCORE_WEIGHTS.bigram)

        -- Treat missing/extra apostrophes as negligible typing errors safely
        local cHasApostrophe = candidate:find("'", 1, true)
        if cHasApostrophe or lHasApostrophe then
            local cFlat = cHasApostrophe and string_gsub(candidate, "'", "") or candidate
            if cFlat == lFlat then
                score = score - 1.5
            else
                local flatDist = self:EditDistance(lFlat, cFlat, maxDist)
                if flatDist and flatDist < dist then
                    score = score - ((dist - flatDist) * 0.8)
                end
            end
        end

        -- Apply locale variant bonus
        local variantBonus = LocaleVariantBonus(lower, candidate)
        if variantBonus > 0 then
            score = score - variantBonus
        end

        -- Keyboard proximity bonus: if the edit distance is small and the
        -- words are close in length, check whether the differing characters
        -- are physically adjacent on the keyboard.  Adjacent-key typos
        -- (fat-finger errors) get a score bonus so they rank higher.
        if dist <= 2 and lenDiff <= 1 and kbDist then
            local proxScore = 0
            local proxCount = 0
            local scanLen = math_min(lowerLen, candidateLen)
            for i = 1, scanLen do
                local lb = lowerBytes[i]
                local cb = string_byte(candidate, i)
                if lb ~= cb then
                    -- Only score a-z characters (bytes 97-122)
                    if lb >= 97 and lb <= 122 and cb >= 97 and cb <= 122 then
                        local kd = kbDist[(lb - 97) * 26 + (cb - 97) + 1]
                        if kd < 1.5 then
                            -- Adjacent key: bonus inversely proportional to distance
                            proxScore = proxScore + (1.5 - kd)
                            proxCount = proxCount + 1
                        end
                    end
                end
            end
            if proxCount > 0 then
                score = score - (proxScore * SCORE_WEIGHTS.kbProximity)
            end
        end

        -- Prefer exact-length candidates when their letter-bag distance is within allowed wrong letters.
        if candidateLen == lowerLen then
            if bagScore <= maxWrong then
                score = score - (SCORE_WEIGHTS.lenDiff * 1.5)
            else
                score = score + ((bagScore - maxWrong) * 0.5)
            end
        elseif lenDiff == 1 and dist == 1 then
            -- Regional variants often differ by exactly 1 character (e.g. color/colour, traveler/traveller)
            if isVariantLocale then
                if bagScore <= (maxWrong + 1) then
                    score = score - (SCORE_WEIGHTS.lenDiff * 1.0)
                end
            end
        end
        out[#out + 1] = { word = candidate, dist = dist, score = score, bag = bagScore }
    end

    -- Prioritise candidates that share more prefix characters with the
    -- query to improve accuracy for short mistyped words (e.g. "hepl"→"help").
    -- Also allow a larger effective cap for short inputs while keeping a
    -- conservative cap for long inputs.
    local dynamicCap = maxCandidates
    if lowerLen <= 4 then
        dynamicCap = math_min(maxCandidates * 4, 5000)
    end

    local checks = 0
    local seenCandidates = {}
    local function tryCandidates(list)
        for _, candidate in ipairs(list) do
            if #out >= 60 then return true end
            if seenCandidates[candidate] then
                -- already processed this candidate via another bucket/variant
            else
                seenCandidates[candidate] = true
                checks = checks + 1
                if checks > dynamicCap then return true end
                if ignoredSet and ignoredSet[candidate] then
                    -- skip ignored
                else
                    local lenDiff = math_abs(#candidate - lowerLen)
                    local isUserWord = addedSet and addedSet[candidate]
                    local isLongPrefix = isUserWord and (#candidate > lowerLen) and (string_sub(candidate, 1, lowerLen) == lower)
                    
                    if lenDiff <= maxLenDiff or isLongPrefix then
                        local dist = isLongPrefix and lenDiff or self:EditDistance(lower, candidate, maxDist)
                        if dist and (dist <= maxDist or isLongPrefix) then
                            tryAdd(candidate, dist)
                        end
                    end
                end
            end
        end
        return false
    end

    -- Direct regional variant injection: bypass ranking cutoffs by explicitly injecting expected variants.
    local function InjectVariantFast(variantSub, candSub)
        local varWord = string_gsub(lower, variantSub, candSub)
        if varWord ~= lower and dict.set[varWord] and not seenCandidates[varWord] then
            seenCandidates[varWord] = true
            local dist = self:EditDistance(lower, varWord, maxDist)
            if dist and dist <= maxDist then
                tryAdd(varWord, dist)
            end
        end
    end

    if locale == "enGB" or locale == "enUS" then
        InjectVariantFast("or", "our")
        InjectVariantFast("our", "or")
        InjectVariantFast("ize", "ise")
        InjectVariantFast("ise", "ize")
        InjectVariantFast("er", "re")
        InjectVariantFast("re", "er")
        InjectVariantFast("og", "ogue")
        InjectVariantFast("ogue", "og")
        InjectVariantFast("l", "ll")
        InjectVariantFast("ll", "l")
    end

    -- Bucket candidates: exact 2-char prefix, 1-char prefix, others.
    local pref2 = {}
    local pref1 = {}
    local other = {}
    local p2 = string_sub(lower, 1, 2) or ""
    local p1 = string_sub(lower, 1, 1) or ""
    for _, c in ipairs(candidates) do
        if string_sub(c, 1, 2) == p2 and p2 ~= "" then
            pref2[#pref2+1] = c
        elseif string_sub(c, 1, 1) == p1 then
            pref1[#pref1+1] = c
        else
            other[#other+1] = c
        end
    end

    local function sortByProximity(a, b)
        local diffA = math_abs(#a - lowerLen)
        local diffB = math_abs(#b - lowerLen)
        if diffA == diffB then
            return a < b
        end
        return diffA < diffB
    end
    table_sort(pref2, sortByProximity)
    table_sort(pref1, sortByProximity)

    if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        self:Notify(string.format("Spellcheck:GetSuggestions buckets p2=%d p1=%d other=%d dynamicCap=%d maxDist=%d maxLenDiff=%d", #pref2, #pref1, #other, dynamicCap, maxDist, maxLenDiff))
    end

    local aborted = false

    -- Unconditionally parse custom words before array caps can trigger
    if addedCandidates and #addedCandidates > 0 then
        aborted = tryCandidates(addedCandidates)
    end

    -- If n-gram candidates were produced, try them first (pre-ranked by overlap).
    if not aborted and ngramCandidates and #ngramCandidates > 0 then
        aborted = tryCandidates(ngramCandidates)
        if aborted and YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
            self:Notify("Spellcheck:GetSuggestions aborted after ngramCandidates; checks=" .. tostring(checks) .. " out=" .. tostring(#out))
        end
    end

    if not aborted then
        aborted = tryCandidates(pref2)
        if aborted and YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
            self:Notify("Spellcheck:GetSuggestions aborted after pref2; checks=" .. tostring(checks) .. " out=" .. tostring(#out))
        end
    end
    if not aborted then
        aborted = tryCandidates(pref1)
        if aborted and YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
            self:Notify("Spellcheck:GetSuggestions aborted after pref1; checks=" .. tostring(checks) .. " out=" .. tostring(#out))
        end
    end
    if not aborted then
        tryCandidates(other)
    end

    if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
        self:Notify("Spellcheck:GetSuggestions finished checks=" .. tostring(checks) .. " candidatesFound=" .. tostring(#out))
    end

    -- If we haven't filled the suggestion list, attempt a small number
    -- of reshuffles/variants of the input to catch anagram-like typos.
    if not aborted and #out < maxCount and checks < dynamicCap then
        local attempts = self:GetReshuffleAttempts() or 0
        if attempts > 0 then
            local variants = {}
            local vseen = {}
            local maxWrong = self:GetMaxWrongLetters() or 4
            local function addVariantIfAcceptable(v)
                if not v or v == lower then return end
                if vseen[v] or #variants >= attempts then return end
                local bagScore = LetterBagScore(v)
                -- Use a conservative threshold (allow up to maxWrong*2 bag distance)
                if bagScore and bagScore <= (maxWrong * 2) then
                    vseen[v] = true
                    variants[#variants+1] = v
                end
            end

            -- Prioritise realistic typos: adjacent transpositions, single deletions, single replacements
            -- 1) adjacent transpositions (string slicing avoids table+concat GC churn)
            for i = 1, (#lower - 1) do
                if #variants >= attempts then break end
                addVariantIfAcceptable(
                    string_sub(lower, 1, i - 1)
                    .. string_sub(lower, i + 1, i + 1)
                    .. string_sub(lower, i, i)
                    .. string_sub(lower, i + 2)
                )
            end

            -- 2) single deletions
            for i = 1, #lower do
                if #variants >= attempts then break end
                addVariantIfAcceptable(
                    string_sub(lower, 1, i - 1) .. string_sub(lower, i + 1)
                )
            end

            -- 3) single replacements using likely letters (dict.first-letters + original letters)
            local alph = {}
            for k in pairs(dict.index) do alph[#alph+1] = k end
            for i = 1, #lower do alph[#alph+1] = string_sub(lower, i, i) end
            local alphSeen = {}
            local alphaList = {}
            for _, ch in ipairs(alph) do
                if not alphSeen[ch] then alphSeen[ch] = true; alphaList[#alphaList+1] = ch end
            end
            for i = 1, #lower do
                if #variants >= attempts then break end
                for _, ch in ipairs(alphaList) do
                    if #variants >= attempts then break end
                    addVariantIfAcceptable(
                        string_sub(lower, 1, i - 1) .. ch .. string_sub(lower, i + 1)
                    )
                end
            end

            if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
                self:Notify("Spellcheck:GetSuggestions trying variants=" .. tostring(#variants))
            end

            for _, var in ipairs(variants) do
                if checks > dynamicCap then break end
                if dict.set[var] and not seenCandidates[var] then
                    if YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG then
                        self:Notify("Spellcheck:GetSuggestions variant hit='" .. tostring(var) .. "'")
                    end
                    seenCandidates[var] = true
                    checks = checks + 1
                    local dist = self:EditDistance(lower, var, maxDist)
                    if dist and dist <= maxDist then
                        tryAdd(var, dist)
                    end
                end
            end
        end
    end

    table_sort(out, function(a, b)
        if a.score == b.score then
            if a.dist == b.dist then
                return a.word < b.word
            end
            return a.dist < b.dist
        end
        return a.score < b.score
    end)

    local final = {}
    for i = 1, math_min(maxCount, #out) do
        final[i] = { kind = "word", value = out[i].word }
    end

    -- Add optional actions at the end of the list.
    local addedSet, ignoredSet = self:GetUserSets(self:GetLocale())
    if word and word ~= "" then
        local norm = NormalizeWord(word)
        if not (addedSet and addedSet[norm]) then
            final[#final + 1] = { kind = "add", value = word }
        end
        if not (ignoredSet and ignoredSet[norm]) then
            final[#final + 1] = { kind = "ignore", value = word }
        end
    end

    -- Update suggestion cache
    sc.word = lower
    sc.dict = dict
    sc.userRev = userRev
    sc.locale = locale
    sc.maxCandidates = maxCandidates
    sc.result = final

    return final
end

function Spellcheck:EditDistance(a, b, maxDist)
    if a == b then return 0 end
    local lenA = #a
    local lenB = #b
    if math_abs(lenA - lenB) > (maxDist or 0) then return nil end

    -- Convert to byte arrays once to avoid string.sub in the inner loop
    local aBytes = self._ed_aBytes
    if not aBytes then aBytes = {}; self._ed_aBytes = aBytes end
    local bBytes = self._ed_bBytes
    if not bBytes then bBytes = {}; self._ed_bBytes = bBytes end
    for i = 1, lenA do aBytes[i] = string_byte(a, i) end
    for j = 1, lenB do bBytes[j] = string_byte(b, j) end

    local prev = self._ed_prev
    local cur = self._ed_cur
    local prevPrev = self._ed_prev_prev

    -- init prev row
    for j = 0, lenB do prev[j] = j end

    for i = 1, lenA do
        cur[0] = i
        local ai = aBytes[i]
        local minRow = i

        local jstart = 1
        local jend = lenB
        if maxDist then
            jstart = math_max(1, i - maxDist)
            jend = math_min(lenB, i + maxDist)
        end

        if jstart > 1 then cur[jstart - 1] = math_huge end

        for j = jstart, jend do
            local cost = (ai == bBytes[j]) and 0 or 1
            local left = (cur[j - 1] or math_huge) + 1
            local above = (prev[j] or math_huge) + 1
            local diag = (prev[j - 1] or math_huge) + cost
            local val = left
            if above < val then val = above end
            if diag < val then val = diag end
            -- transposition check
            if i > 1 and j > 1 then
                if ai == bBytes[j - 1] and aBytes[i - 1] == bBytes[j] then
                    local prevPrevVal = prevPrev[j - 2] or math_huge
                    if prevPrevVal + 1 < val then val = prevPrevVal + 1 end
                end
            end
            cur[j] = val
            if val < minRow then minRow = val end
        end

        if minRow > (maxDist or 0) then return nil end

        -- O(1) swap of buffers
        self._ed_prev_prev, self._ed_prev, self._ed_cur = self._ed_prev, self._ed_cur, self._ed_prev_prev
        prevPrev = self._ed_prev_prev
        prev = self._ed_prev
        cur = self._ed_cur
    end

    return prev[lenB]
end

function Spellcheck:FormatSuggestionLabel(entry, index)
    if type(entry) == "string" then
        return index .. ". " .. entry
    end
    if type(entry) ~= "table" then
        return index .. ". -"
    end
    if entry.kind == "add" then
        return index .. ". Add \"" .. (entry.value or "") .. "\" to dictionary"
    end
    if entry.kind == "ignore" then
        return index .. ". Ignore \"" .. (entry.value or "") .. "\""
    end
    return index .. ". " .. (entry.value or entry.word or "")
end

return Spellcheck