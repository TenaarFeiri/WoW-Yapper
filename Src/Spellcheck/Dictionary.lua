--[[
    Spellcheck/Dictionary.lua
    Async dictionary loading, registration, locale availability checking,
    dictionary inheritance, and memory management.
]]

local _, YapperTable = ...
local Spellcheck     = YapperTable.Spellcheck

-- Re-localise shared helpers from hub.
local Clamp           = Spellcheck.Clamp
local NormaliseWord   = Spellcheck.NormaliseWord
local NormaliseVowels = Spellcheck.NormaliseVowels
local IsWordStartByte = Spellcheck.IsWordStartByte

-- Re-localise Lua globals.
local type       = type
local pairs      = pairs
local ipairs     = ipairs
local tostring   = tostring
local tonumber   = tonumber
local math_huge    = math.huge
local math_min     = math.min
local string_byte  = string.byte
local string_sub   = string.sub
local string_lower = string.lower
local string_format = string.format
local table_insert  = table.insert
local table_sort    = table.sort

-- Chunk size for async loading (from hub).
local DICT_CHUNK_SIZE = Spellcheck._DICT_CHUNK_SIZE

function Spellcheck:LoadDictionary(locale)
    -- Don't start a new load if it's already in memory, currently loading, or pending.
    if self.Dictionaries and self.Dictionaries[locale] then return end
    if self._asyncLoaders and self._asyncLoaders[locale] then return end
    if self._pendingBuilders and self._pendingBuilders[locale] then return end

    if self.DictionaryBuilders and self.DictionaryBuilders[locale] then
        -- Mark as pending immediately so recursive/repeated calls don't double-fire.
        self._pendingBuilders = self._pendingBuilders or {}
        self._pendingBuilders[locale] = true

        local builder = self.DictionaryBuilders[locale]
        -- The builder only assembles raw word/phonetic tables — this is cheap.
        -- The heavy per-word indexing is handled asynchronously inside RegisterDictionary.
        local success, data = pcall(builder)
        self._pendingBuilders[locale] = nil

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

    -- If the data bundle includes an engine registration, wire it up now so
    -- that GetActiveEngine() returns the correct engine even before the dict
    -- is fully indexed (important for async loading of large base dicts).
    if type(data.engine) == "table" and type(data.languageFamily) == "string" then
        self:_RegisterLanguageEngine(data.languageFamily, data.engine)
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
    local outWords = (existing and existing.words) or (not data.extends and words) or {}
    local ngramIndex2 = existing and existing.ngramIndex2 or {}
    local ngramIndex3 = existing and existing.ngramIndex3 or {}
    local phonetics = data.phonetics or (existing and existing.phonetics) or {}

    local cfg = YapperTable and YapperTable.Config and YapperTable.Config.Spellcheck or {}
    local ngramKeyCapSize = (cfg.NgramKeyCapSize ~= nil) and tonumber(cfg.NgramKeyCapSize) or 0
    if ngramKeyCapSize == 0 then ngramKeyCapSize = math_huge end

    -- Handle Inheritance (Base + Delta)
    if data.extends then
        local base = self.Dictionaries[data.extends]
        if not base then
            -- Base is not yet loaded — use EnsureLocale so the LOD addon
            -- containing the base builder is actually loaded first.
            -- A plain LoadDictionary call can no-op when the addon has not
            -- registered DictionaryBuilders[data.extends] yet.
            self:EnsureLocale(data.extends)
            base = self.Dictionaries[data.extends]
        end
        if base then
            -- Membership: safe O(1) metatable inheritance
            setmetatable(set, { __index = base.set })
            -- Words + Phonetics: safe because the Python generator offsets delta
            -- indices past the base word count, preventing index collision.
            setmetatable(phonetics, { __index = base.phonetics })
            setmetatable(outWords, { __index = base.words })
        elseif YapperTable.Utils and YapperTable.Utils.Print then
            YapperTable.Utils:Print("error", "Base dictionary " .. tostring(data.extends) .. " not found for " .. locale)
        end
    end

    -- Make the dictionary available immediately (even if empty/partial),
    -- so CollectMisspellings can start using words as they arrive.
    if not existing then
        self.Dictionaries[locale] = {
            locale         = locale,
            languageFamily = data.languageFamily or nil,
            words          = outWords,
            set            = set,
            index          = index,
            ngramIndex2    = ngramIndex2,
            ngramIndex3    = ngramIndex3,
            phonetics      = phonetics,
            isDelta        = data.extends and true or false,
            extends        = data.extends,
            _metaCache     = {},
            _metaUsageTimer = 0,
            _metaCacheSize  = 0,
        }
    end

    local dict = self.Dictionaries[locale]
    local indexedCount = 0

    -- If the data already contains a pre-built set and index, we can skip processing.
    if data.isPreBuilt then
        self:_OnDictRegistrationComplete(locale)
        return
    end

    -- Core word processing: adds a word to set, index, and ngramIndex.
    -- Returns true if the word was newly added.
    local function processWord(word, originalId)
        if type(word) ~= "string" or word == "" then return false end
        local w = NormaliseWord(word)
        if w == "" then return false end
        local b = string_byte(w, 1)
        if not b or not IsWordStartByte(b) then return false end

        -- Check set (including the base dictionary via metatable)
        if set[w] then return false end

        set[w] = true
        indexedCount = indexedCount + 1

        -- Only append to outWords if the builder didn't already pre-fill it.
        -- This prevents the "Doubling Dictionary" bug where memory usage
        -- could balloon to 2x the required size during reload.
        local finalId = originalId
        if outWords ~= words then
            outWords[#outWords + 1] = word
            finalId = #outWords
        end

        local key = string_sub(w, 1, 1)
        if key ~= "" then
            index[key] = index[key] or {}
            index[key][#index[key] + 1] = w
        end

        -- Build n-gram postings inline using vowel-neutral normalisation
        local norm = NormaliseVowels(w)
        local n2, n3 = 2, 3

        -- Bigram Index (N=2)
        if #norm >= n2 then
            dict.ngramIndex2 = dict.ngramIndex2 or {}
            for i = 1, (#norm - n2 + 1) do
                local g = string_sub(norm, i, i + n2 - 1)
                dict.ngramIndex2[g] = dict.ngramIndex2[g] or {}
                local posting = dict.ngramIndex2[g]
                if #posting < 500 then -- TIERED CAP N2: 500
                    posting[#posting + 1] = finalId
                end
            end
        end

        -- Trigram Index (N=3)
        if #norm >= n3 then
            dict.ngramIndex3 = dict.ngramIndex3 or {}
            for i = 1, (#norm - n3 + 1) do
                local g = string_sub(norm, i, i + n3 - 1)
                dict.ngramIndex3[g] = dict.ngramIndex3[g] or {}
                local posting = dict.ngramIndex3[g]
                if #posting < 2500 then -- TIERED CAP N3: 2500
                    posting[#posting + 1] = finalId
                end
            end
        end
        return true
    end

    local totalWords = #words

    -- If dict is pre-processed or extends another, outWords might not match words.
    -- But if words matches outWords (synchronous load), we can skip ONLY IF the index is already populated.
    local hasIndex = false
    for k, v in pairs(index) do
        hasIndex = true; break
    end

    if words == outWords and #outWords > 0 and not data.isDelta and hasIndex then
        -- Already populated via builder/cache
        self:_OnDictRegistrationComplete(locale)
        return
    end

    -- For small dictionaries, process synchronously (no overhead)
    if totalWords <= DICT_CHUNK_SIZE then
        for i, word in ipairs(words) do
            processWord(word, i)
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

    -- Show a one-time loading message when the async path kicks off
    if self:IsEnabled() and not existing then
        self:Notify("Yapper: loading " .. tostring(locale) .. " dictionary (" .. tostring(totalWords) .. " words)...")
    end

    local function processChunk()
        -- On cancellation: nil all large upvalue references so this closure
        -- doesn't pin the old tables for an extra GC cycle after cancel.
        if loader.cancelled then
            words        = nil
            outWords     = nil
            set          = nil
            index        = nil
            ngramIndex2  = nil
            ngramIndex3  = nil
            phonetics    = nil
            processWord  = nil
            return
        end

        local endIdx = math_min(loader.cursor + DICT_CHUNK_SIZE - 1, totalWords)
        for i = loader.cursor, endIdx do
            processWord(words[i], i)
        end
        loader.cursor = endIdx + 1

        if loader.cursor > totalWords then
            -- Finished: release the raw builder words array — the processed
            -- data lives in outWords/ngramIndex/set; the flat array is now waste.
            data.words = nil
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
                data.words = nil
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

    -- Only notify the user about their active locale. Base dictionaries load
    -- silently in the background; the user doesn't need to know about them.
    local cfg = self:GetConfig()
    local isActiveLocale = cfg and cfg.Locale == locale
    if isActiveLocale then
        -- Handle Metatable inheritance for count (show the user the unified total)
        local totalCount = count
        if dict and dict.extends then
            local base = self.Dictionaries[dict.extends]
            if base and base.words then
                totalCount = totalCount + #base.words
            end
        end

        if YapperTable.Utils and YapperTable.Utils.Print then
            YapperTable.Utils:Print("info", "Dictionary loaded:", locale, ("(%s words)"):format(tostring(totalCount)))
        else
            self:Notify("Yapper: " .. tostring(locale) .. " dictionary loaded (" .. tostring(totalCount) .. " words).")
        end
    end

    if isActiveLocale and self:IsEnabled() then
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
    table_sort(out)
    return out
end

function Spellcheck:GetLocaleAddon(locale)
    if type(locale) ~= "string" then return nil end
    return (self.LocaleAddons and self.LocaleAddons[locale]) or nil
end

function Spellcheck:HasLocaleAddon(locale)
    local addon = self:GetLocaleAddon(locale)
    if not addon then return false end

    local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if getInfo then
        -- Blizzard's GetAddOnInfo echoes the queried name back even when
        -- the addon isn't on disk; the authoritative signals are `loadable`
        -- and `reason`. An uninstalled addon reports reason="MISSING".
        local name, _, _, loadable, reason = getInfo(addon)
        if not name then return false end
        if reason == "MISSING" or reason == "MISSING_DEPENDENCY" then
            return false
        end
        -- DISABLED / INSECURE / DEMAND_LOADED / BANNED / INTERFACE_VERSION
        -- all still mean the addon is on disk; treat them as "present"
        -- except BANNED (which the client will refuse to load).
        if reason == "BANNED" then return false end
        return loadable == true
            or reason == "DISABLED"
            or reason == "INSECURE"
            or reason == "DEMAND_LOADED"
            or reason == nil
    end

    -- Pre-Dragonflight fallback (very old clients).
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded and isLoaded(addon) then return true end
    return false
end

function Spellcheck:HasAnyDictionary()
    if self.Dictionaries and next(self.Dictionaries) then return true end
    if self.KnownLocales then
        for _, locale in ipairs(self.KnownLocales) do
            if self:HasLocaleAddon(locale) then
                return true
            end
        end
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
    
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded and isLoaded(addon) then
        return true
    end
    
    -- If it's not loaded, we can still load it if the addon exists on disk.
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

    -- Addon expected but not on disk: fail quietly. Callers upstream
    -- already treat a false return as "locale unavailable"; we must not
    -- call LoadAddOn here because it will surface a MISSING error every
    -- time GetDictionary() is reached (e.g. on login when the user's
    -- saved locale points at an LOD addon they haven't installed).
    if addon and not self:HasLocaleAddon(locale) then
        return false
    end

    if addon then
        if C_AddOns and C_AddOns.LoadAddOn then
            local isLoaded = C_AddOns.IsAddOnLoaded(addon)
            local loaded, reason = C_AddOns.LoadAddOn(addon)
            if loaded == false then
                -- Only notify on real failures (corrupt, banned, etc.).
                -- MISSING is handled by the early-return above.
                if reason ~= "MISSING" and self.Notify then
                    self:Notify("Yapper: failed to load " .. addon .. " (" .. tostring(reason) .. ").")
                end
                return false
            elseif isLoaded and not self:IsLocaleAvailable(locale) then
                return false
            end
        elseif LoadAddOn then
            local isLoaded = IsAddOnLoaded(addon)
            local loaded = LoadAddOn(addon)
            if loaded == false then return false end
            if isLoaded and not self:IsLocaleAvailable(locale) then
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
