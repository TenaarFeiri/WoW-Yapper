--[[
    YALLM: Yapper Adaptive Language Learning Model
    Personalized ranking and vocabulary tracking for the spellcheck engine.
]]

local YapperName, YapperTable = ...
local YALLM = {}
YapperTable.Spellcheck.YALLM = YALLM -- Hook into internal table

-- Tuning Constants (used as fallbacks when config is not yet available)
local FREQ_CAP = 2000      -- Max unique words to track
local AUTO_THRESHOLD = 10  -- Times sent before auto-added to dict
local MAX_BIAS_PAIRS = 500 -- Max Typo -> Selection pairs to track
local WEIGHTS = {
    freqBonus = -2.5,      -- High usage = lower score (better)
    biasBonus = -8.0,      -- Past selection = significantly lower score (Increased from -5.0)
    phBonus = -4.0,        -- Phonetic pattern match = moderate score bonus (Increased from -3.0)
    negBias = 3.0,         -- Twice rejected (More...) = penalty (higher score)
}

-- Localise globals
local time = time
local pairs = pairs
local ipairs = ipairs
local type = type
local next = next
local math_min = math.min
local math_max = math.max
local math_abs = math.abs
local math_floor = math.floor
local table_insert = table.insert
local table_sort = table.sort
local string_format = string.format

local function IsDebugEnabled()
    return YapperTable and YapperTable.Config and YapperTable.Config.System and YapperTable.Config.System.DEBUG
end

local function VerifyFreqIndex(db)
    if not IsDebugEnabled() then return end
    if type(db) ~= "table" or type(db.freq) ~= "table" then return end
    if type(db.freqSorted) ~= "table" then
        error("YALLM freqSorted invariant failed: missing sorted index")
    end

    local seen = {}
    local count = 0
    local prev = nil
    for i = 1, #db.freqSorted do
        local w = db.freqSorted[i]
        if type(w) ~= "string" or w == "" then
            error("YALLM freqSorted invariant failed: invalid word at index " .. tostring(i))
        end
        if prev and w < prev then
            error("YALLM freqSorted invariant failed: non-monotonic order")
        end
        if not db.freq[w] then
            error("YALLM freqSorted invariant failed: index contains missing freq key '" .. tostring(w) .. "'")
        end
        if seen[w] then
            error("YALLM freqSorted invariant failed: duplicate key '" .. tostring(w) .. "'")
        end
        seen[w] = true
        prev = w
        count = count + 1
    end

    local freqCount = 0
    for word in pairs(db.freq) do
        freqCount = freqCount + 1
        if not seen[word] then
            error("YALLM freqSorted invariant failed: missing key '" .. tostring(word) .. "'")
        end
    end
    if freqCount ~= count then
        error("YALLM freqSorted invariant failed: cardinality mismatch")
    end
end

local function RebuildFreqSorted(db)
    local sorted = {}
    for word in pairs(db.freq or {}) do
        sorted[#sorted + 1] = word
    end
    table_sort(sorted)
    db.freqSorted = sorted
    db.freqSortedDirty = false
    VerifyFreqIndex(db)
    return sorted
end

local function InsertSortedWord(sorted, word)
    local lo, hi = 1, #sorted
    while lo <= hi do
        local mid = math_floor((lo + hi) / 2)
        local v = sorted[mid]
        if v == word then
            return
        elseif v < word then
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    table_insert(sorted, lo, word)
end

-- ---------------------------------------------------------------------------
-- Config-driven cap accessors
-- ---------------------------------------------------------------------------

--- Returns true if YALLM is enabled in the configuration.
function YALLM:IsEnabled()
    local cfg = YapperTable.Config and YapperTable.Config.Spellcheck
    return (cfg and cfg.YALLMEnabled ~= false)
end

function YALLM:GetFreqCap()
    local cfg = YapperTable.Config and YapperTable.Config.Spellcheck
    local v = tonumber(cfg and cfg.YALLMFreqCap) or FREQ_CAP
    return math_max(100, math_min(v, 10000))
end

function YALLM:GetBiasCap()
    local cfg = YapperTable.Config and YapperTable.Config.Spellcheck
    local v = tonumber(cfg and cfg.YALLMBiasCap) or MAX_BIAS_PAIRS
    return math_max(50, math_min(v, 5000))
end

function YALLM:GetAutoThreshold()
    local cfg = YapperTable.Config and YapperTable.Config.Spellcheck
    local v = tonumber(cfg and cfg.YALLMAutoThreshold) or AUTO_THRESHOLD
    return math_max(1, math_min(v, 200))
end

function YALLM:GetNegBiasCap()
    local cfg = YapperTable.Config and YapperTable.Config.Spellcheck
    local v = tonumber(cfg and cfg.YALLMNegBiasCap) or MAX_BIAS_PAIRS
    return math_max(100, math_min(v, 10000))
end

-- ---------------------------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------------------------

function YALLM:Init()
    if not _G.YapperDB then return end

    -- Structure: _G.YapperDB.SpellcheckLearned[locale] = { freq = {}, bias = {}, ... }
    if not _G.YapperDB.SpellcheckLearned then
        _G.YapperDB.SpellcheckLearned = {}
    end

    -- Migration: If the table itself contains 'freq', it's a legacy flat DB.
    -- Move it to 'enBASE' as a safe default.
    local legacy = _G.YapperDB.SpellcheckLearned
    if legacy.freq and type(legacy.freq) == "table" then
        local oldCopy = {}
        for k, v in pairs(legacy) do
            oldCopy[k] = v
            legacy[k] = nil -- Clear root key
        end
        legacy["enBASE"] = oldCopy
        if YapperTable.Utils then
            YapperTable.Utils:Print("info", "YALLM: Migrated legacy flat database to 'enBASE' partition.")
        end
    end

    self.db = _G.YapperDB.SpellcheckLearned
end

function YALLM:GetLocaleDB(locale)
    if not self.db then return nil end
    local loc = locale or "enBASE"
    if not self.db[loc] then
        self.db[loc] = {
            freq = {},    -- word -> { c, t }
            freqSorted = {}, -- derived sorted array of cleaned keys from freq (alphabetical order)
            freqSortedDirty = false, -- true when freq has changed and index must rebuild
            bias = {},    -- typo:correction -> { c, t, u }
            auto = {},    -- word -> { c, t }
            phBias = {},  -- PhoneticHash(typo):correction -> { c, t }
            negBias = {}, -- typo:word -> { c, t }
            total = 0,    -- total unique words tracked
        }
    end
    local db = self.db[loc]
    if type(db.freq) ~= "table" then db.freq = {} end
    if db.total == nil then
        local count = 0
        for _ in pairs(db.freq) do count = count + 1 end
        db.total = count
    end
    if db.negBiasCount == nil then
        local count = 0
        if db.negBias then
            for _ in pairs(db.negBias) do count = count + 1 end
        end
        db.negBiasCount = count
    end
    if db.freqSortedDirty == nil then
        db.freqSortedDirty = true
    end
    if db.freqSorted ~= nil and type(db.freqSorted) ~= "table" then
        db.freqSorted = nil
        db.freqSortedDirty = true
    end
    return db
end

function YALLM:EnsureFreqSorted(locale)
    local db = self:GetLocaleDB(locale)
    if not db then return nil end
    if db.freqSortedDirty or type(db.freqSorted) ~= "table" then
        return RebuildFreqSorted(db)
    end
    VerifyFreqIndex(db)
    return db.freqSorted
end

-- ---------------------------------------------------------------------------
-- Tracking Logic
-- ---------------------------------------------------------------------------

--- Standardise word for tracking
local function Clean(s)
    if not s then return "" end
    return s:lower():gsub("[%p%c%s]", "")
end

function YALLM:IsSaneWord(word, locale)
    local w = Clean(word)
    -- Length bounds check
    if #w < 2 or #w > 40 then return false end

    -- 1. Linguistic Cluster Check (7+ consecutive consonants)
    -- Lua patterns don't support {n,} quantifiers, so we use repetition.
    if w:match("[^aeiouy][^aeiouy][^aeiouy][^aeiouy][^aeiouy][^aeiouy][^aeiouy]") then return false end

    -- 2. Keyboard Smash Check (3+ identical consecutive characters)
    if w:match("(.)%1%1") then return false end

    -- 3. N-Gram Anchor (Sanity Verification)
    -- Note: the base dictionary loads asynchronously over several frames after
    -- login, so ngramIndex2 may not be populated yet when RecordUsage first fires.
    -- This is intentionally safe: the guard below simply skips the check when the
    -- index isn't ready, causing valid words to pass on the first few messages.
    -- False-negatives here are harmless (a word is silently not recorded once);
    -- false-positives from the other two checks above are the real concern.
    local sc = YapperTable.Spellcheck
    local dict = sc and sc:GetDictionary()
    if dict and dict.ngramIndex2 then
        local norm = w:gsub("[aeiouy]", "*")
        local foundValidBigram = false
        for i = 1, #norm - 1 do
            local g = norm:sub(i, i + 1)
            if dict.ngramIndex2[g] then
                foundValidBigram = true
                break
            end
        end
        if not foundValidBigram then return false end
    end

    return true
end

--- Record usage frequency of words in a message
function YALLM:RecordUsage(text, locale)
    if not self:IsEnabled() then return end
    local db = self:GetLocaleDB(locale)
    if not db then return end
    local now = time()

    -- Fast-split into words (alphanumeric only)
    for word in text:gmatch("[%w']+") do
        if self:IsSaneWord(word, locale) then
            local w = Clean(word)
            if not db.freq[w] then
                -- Handle Capacity (Weighted LRU Eviction)
                if db.total >= self:GetFreqCap() then
                    self:Prune("freq", self:GetFreqCap(), locale)
                end
                db.freq[w] = { c = 1, t = now }
                db.total = db.total + 1
                if not db.freqSortedDirty then
                    if type(db.freqSorted) ~= "table" then
                        db.freqSorted = {}
                    end
                    InsertSortedWord(db.freqSorted, w)
                    VerifyFreqIndex(db)
                end
            else
                local entry = db.freq[w]
                entry.c = entry.c + 1
                entry.t = now
            end
        end
    end
end

--- Record when a user picks a specific suggestion for a typo.
function YALLM:RecordSelection(typo, correction, utilityGain, locale)
    if not self:IsEnabled() then return end
    local db = self:GetLocaleDB(locale)
    if not db then return end
    local c = Clean(correction)
    local t = Clean(typo)

    -- Data Scrubbing: Don't learn from empty symbols or punctuation-only corrections.
    if c == "" or t == "" then return end

    -- Normalise utilityGain: boolean -> number for backward-compat
    local gain
    if type(utilityGain) == "number" then
        gain = utilityGain
    elseif utilityGain then
        gain = 0.5
    else
        gain = 0
    end

    if IsDebugEnabled() then
        YapperTable.Utils:Print("debug", string.format("YALLM: RecordSelection typo='%s' corr='%s' gain=%.2f", typo, correction, gain))
    end

    local now = time()

    -- 1. Exact Bias
    local key = t .. ":" .. c
    if not db.bias[key] then
        -- Handle Capacity
        db.biasCount = (db.biasCount or 0) + 1
        if db.biasCount >= self:GetBiasCap() then
            self:Prune("bias", self:GetBiasCap(), locale)
            -- Recalculate count after pruning
            local count = 0
            for _ in pairs(db.bias) do count = count + 1 end
            db.biasCount = count
        end
        db.bias[key] = { c = 1, t = now, u = 1 + gain }
    else
        local entry = db.bias[key]
        entry.c = entry.c + 1
        entry.t = now
        if gain > 0 then entry.u = math_min((entry.u or 1) + gain, 5.0) end
    end

    -- Bump revision so the suggestion cache knows to recompute scores.
    db._rev = (db._rev or 0) + 1

    -- 2. Phonetic Pattern Bias (Generalized Learning)
    local sc = YapperTable.Spellcheck
    if sc and sc.GetPhoneticHash then
        local ph = sc.GetPhoneticHash(t)
        if ph and ph ~= "" then
            local phKey = ph .. ":" .. c
            if not db.phBias[phKey] then
                -- Handle Capacity (Shared cap with bias for now)
                db.phBiasCount = (db.phBiasCount or 0) + 1
                if db.phBiasCount >= self:GetBiasCap() then
                    self:Prune("phBias", self:GetBiasCap(), locale)
                    local count = 0
                    for _ in pairs(db.phBias) do count = count + 1 end
                    db.phBiasCount = count
                end
                db.phBias[phKey] = { c = 1, t = now, u = 1 + gain }
            else
                local entry = db.phBias[phKey]
                entry.c = entry.c + 1
                entry.t = now
                if gain > 0 then entry.u = math_min((entry.u or 1) + gain, 5.0) end
            end
        end
    end
end

--- Record a correction that was made by the user manually retyping (implicit backtrack).
--- Determines the appropriate learning strength based on whether the correction was
--- already a known candidate and how phonetically/textually close it is to the typo.
function YALLM:RecordImplicitCorrection(typo, correction, candidates, locale)
    if not self:IsEnabled() then return end
    local db = self:GetLocaleDB(locale)
    if not db then return end


    local t = Clean(typo)
    local c = Clean(correction)
    if t == "" or c == "" then return end

    -- 1. Was the correction already in the shown candidate list?
    local inCandidates = false
    if type(candidates) == "table" then
        for _, cand in ipairs(candidates) do
            local w = type(cand) == "table" and (cand.value or cand.word) or cand
            if w and Clean(w) == c then
                inCandidates = true
                break
            end
        end
    end

    local utilityGain

    if inCandidates then
        -- The user typed out a word that was already our suggestion: treat as a
        -- full explicit selection — strongest signal.
        utilityGain = 0.5
    else
        -- Not a candidate.  Gate by phonetic and edit-distance similarity so that
        -- completely unrelated corrections (e.g. the user deleted the word and
        -- started a new sentence) don't pollute the bias table.
        local sc = YapperTable.Spellcheck
        local typoHash = sc and sc.GetPhoneticHash and sc.GetPhoneticHash(t) or ""
        local corrHash = sc and sc.GetPhoneticHash and sc.GetPhoneticHash(c) or ""

        if typoHash ~= "" and typoHash == corrHash then
            -- Same phonetic fingerprint despite different spelling: clear correction.
            utilityGain = 0.3
        else
            -- Fall back to similarity heuristics.
            -- Use a slightly higher maxDist for learning (3) so we capture more manual corrections.
            local sc = YapperTable.Spellcheck
            local dist = (sc and type(sc.EditDistance) == "function") and sc:EditDistance(t, c, 3) or 4
            
            if dist <= 1 then
                -- Direct transposition or single char edit: very strong signal.
                utilityGain = 0.5
            elseif dist <= 2 then
                -- Close edit: strong signal.
                utilityGain = 0.35
            elseif dist <= 3 then
                -- Moderate edit.
                utilityGain = 0.2
            else
                -- Not a close edit, check shared prefix/suffix as a last resort.
                local maxLen = math_max(#t, #c)
                local shared = 0
                -- Shared Prefix
                for i = 1, math_min(#t, #c) do
                    if t:sub(i, i) ~= c:sub(i, i) then break end
                    shared = shared + 1
                end
                -- Shared Suffix
                for i = 0, math_min(#t, #c) - 1 do
                    if i >= shared then -- Don't double count if they overlap
                        if t:sub(#t - i, #t - i) ~= c:sub(#c - i, #c - i) then break end
                        shared = shared + 1
                    end
                end

                local similarity = shared / maxLen
                if similarity >= 0.4 then
                    utilityGain = 0.15
                elseif similarity >= 0.2 then
                    utilityGain = 0.05
                else
                    return
                end
            end
        end
    end

    self:RecordSelection(typo, correction, utilityGain, locale)

    -- Only penalise shown candidates if the correction wasn't among them,
    -- so we don't double-penalise words the user actually wanted.
    if not inCandidates and type(candidates) == "table" then
        self:RecordRejection(typo, candidates, locale)
    end
end

--- Record when a user rejects a list of suggestions by clicking "More"
function YALLM:RecordRejection(typo, candidates, locale)
    if not self:IsEnabled() then return end
    local db = self:GetLocaleDB(locale)
    if not db or not typo or type(candidates) ~= "table" then return end

    local t = Clean(typo)
    local now = time()

    for _, candObj in ipairs(candidates) do
        local word = type(candObj) == "table" and (candObj.word or candObj.value) or candObj
        if word then
            -- Clean the candidate word before key construction to ensure consistent matching
            local key = t .. ":" .. Clean(word)
            if not db.negBias[key] then
                -- Handle Capacity
                db.negBiasCount = (db.negBiasCount or 0) + 1
                if db.negBiasCount >= self:GetNegBiasCap() then
                    self:Prune("negBias", self:GetNegBiasCap(), locale)
                    local count = 0
                    for _ in pairs(db.negBias) do count = count + 1 end
                    db.negBiasCount = count
                end
                db.negBias[key] = { c = 1, t = now, u = 1.0 }
            else
                local entry = db.negBias[key]
                entry.c = entry.c + 1
                entry.t = now
                entry.u = math_min((entry.u or 1.0) + 0.2, 5.0)
            end
        end
    end
end

--- Record high-repetition typos for auto-learning
function YALLM:RecordIgnored(word, locale)
    if not self:IsEnabled() then return end
    local db = self:GetLocaleDB(locale)
    if not db then return end
    if not self:IsSaneWord(word, locale) then return end

    local w = Clean(word)
    local now = time()
    if not db.auto[w] then
        db.auto[w] = { c = 1, t = now }
    else
        local entry = db.auto[w]
        entry.c = entry.c + 1
        entry.t = now
    end

    if db.auto[w].c >= self:GetAutoThreshold() then
        -- Auto-promote to user dictionary
        local Spellcheck = YapperTable.Spellcheck
        if Spellcheck and Spellcheck.AddUserWord then
            local loc = locale or Spellcheck:GetLocale()
            Spellcheck:AddUserWord(loc, word)
            db.auto[w] = nil -- Reset now that it's in the dict
            if YapperTable.Utils and YapperTable.Utils.VerbosePrint then
                YapperTable.Utils:VerbosePrint("info",
                    "YALLM: Learned new word '" .. word .. "' (" .. (loc or "Shared") .. ") after persistent usage.")
            end
            -- Notify external addons about the auto-learned word.
            if YapperTable.API then
                YapperTable.API:Fire("YALLM_WORD_LEARNED", word, loc)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Scoring Logic
-- ---------------------------------------------------------------------------

--- Return the combined score bonus for a candidate using a pre-computed phonetic hash.
function YALLM:GetBonus(cand, typo, typoPhHash, locale)
    if not self:IsEnabled() then return 0 end
    local db = self:GetLocaleDB(locale)
    if not db then return 0 end
    local c = Clean(cand)
    local t = Clean(typo)
    local bonus = 0

    -- 1. Frequency Bonus
    -- If cand comes from dictionary, it is already clean. If from user word, it might not be.
    -- However, most callers provide a normalised candidate.
    local freqEntry = db.freq[cand] or db.freq[c]
    if freqEntry and freqEntry.c > 2 then
        -- Use logarithmic scaling so common words get a better proportional boost
        local logBonus = math_min(math.log(freqEntry.c) / 2, 3.0)
        bonus = bonus + (WEIGHTS.freqBonus * logBonus)
    end

    -- 2. Bias Bonus
    local key = t .. ":" .. c
    local biasEntry = db.bias[key]
    if biasEntry then
        -- Factor in the utility (certainty) of the correction.
        -- If the user explicitly chose this, the utility is higher (up to 5.0).
        local utility = math_max(biasEntry.u or 1.0, 1.0)
        local cappedBias = math_min(biasEntry.c, 3) -- Slightly higher cap for count
        bonus = bonus + (WEIGHTS.biasBonus * cappedBias * utility)
    end
    
    -- 3. Phonetic Pattern Bonus (Optimized: use passed-down hash)
    if typoPhHash and db.phBias then
        local phKey = typoPhHash .. ":" .. c
        local phEntry = db.phBias[phKey]
        if phEntry then
            -- Generalized phonetic learning
            local utility = math_max(phEntry.u or 1.0, 1.0)
            local cappedPh = math_min(phEntry.c, 2)
            bonus = bonus + (WEIGHTS.phBonus * cappedPh * utility)
        end
    end

    -- 4. Rejection Penalty
    if db.negBias then
        local negEntry = db.negBias[key]
        if negEntry then
            bonus = bonus + (WEIGHTS.negBias * math_min(negEntry.c, 5))
        end
    end

    return bonus
end

--- Returns a list of candidate words that have been learned as corrections for the given typo.
function YALLM:GetBiasTargets(typo, locale)
    if not self:IsEnabled() then return nil end
    local db = self:GetLocaleDB(locale)
    if not db or not db.bias then return nil end
    local t = Clean(typo)
    if t == "" then return nil end

    local targets = {}
    -- Pattern match for "typo:*" in the bias table.
    -- While iterating the whole bias table is O(N), N is capped at 500, so it's very fast.
    local prefix = t .. ":"
    local prefixLen = #prefix
    for key, _ in pairs(db.bias) do
        -- Use string.find(..., 1, true) to avoid substring allocation during prefix check.
        if string.find(key, prefix, 1, true) == 1 then
            local correction = string.sub(key, prefixLen + 1)
            if correction ~= "" then
                targets[#targets + 1] = correction
            end
        end
    end

    -- Also check phonetic bias targets
    local sc = YapperTable.Spellcheck
    local ph = sc and sc.GetPhoneticHash and sc.GetPhoneticHash(t)
    if ph and ph ~= "" and db.phBias then
        local phPrefix = ph .. ":"
        local phPrefixLen = #phPrefix
        for key, _ in pairs(db.phBias) do
            if string.find(key, phPrefix, 1, true) == 1 then
                local correction = string.sub(key, phPrefixLen + 1)
                if correction ~= "" then
                    targets[#targets + 1] = correction
                end
            end
        end
    end

    return #targets > 0 and targets or nil
end

-- ---------------------------------------------------------------------------
-- Maintenance
-- ---------------------------------------------------------------------------

--- Systematic pruning of a learning table
function YALLM:Prune(tableName, limit, locale)
    local db = self:GetLocaleDB(locale)
    if not db then
        -- Throw error if db is nil, because what???
        -- Note to future self: If you remove this check then
        -- it is possible for dbId top beyond nils. 
        -- In which case, also remove linter suppression for need-check-nil.
        YapperTable.Error:Throw("UNKNOWN", "YALLM:Prune", "Could not obtain local db")
    end

    -- Explicitly verify for linter that db is not nil
    local tbl = db and db[tableName]
    if not tbl then return end


    local keys = {}
    for k in pairs(tbl) do table_insert(keys, k) end
    if #keys <= limit then return end

    -- Sort by relevance: Score = Count * Utility * RecencyFactor
    -- Items used a long time ago have lower recency factors.
    local now = time()
    table_sort(keys, function(a, b)
        local ea = tbl[a]
        local eb = tbl[b]

        -- Utility weighting (defaults to 1 if missing)
        local ua = ea.u or 1
        local ub = eb.u or 1

        -- Recency weighting (days-based linear decay).
        -- Score = (Count * Utility) / (DaysOld + 1)
        local ageA_days = math_max(0, (now - (ea.t or 0)) / 86400)
        local ageB_days = math_max(0, (now - (eb.t or 0)) / 86400)

        local scoreA = (ea.c * ua) / (ageA_days + 1)
        local scoreB = (eb.c * ub) / (ageB_days + 1)

        return scoreA > scoreB -- Keep high scores
    end)

    -- Evict the bottom 10% to make breathing room
    local targetSize = math_floor(limit * 0.9)
    for i = targetSize + 1, #keys do
        local k = keys[i]
        tbl[k] = nil
        -- db cannot be nil
        ---@diagnostic disable-next-line: need-check-nil
        if tableName == "freq" and db.total then
            ---@diagnostic disable-next-line: need-check-nil
            db.total = math_max(0, db.total - 1)
        end
    end

    if tableName == "freq" then
        RebuildFreqSorted(db)
    end
end

function YALLM:Reset(locale)
    if not locale then
        _G.YapperDB.SpellcheckLearned = nil
    elseif _G.YapperDB.SpellcheckLearned then
        _G.YapperDB.SpellcheckLearned[locale] = nil
    end
    self:Init()
end

-- ---------------------------------------------------------------------------
-- UI Helpers
-- ---------------------------------------------------------------------------

function YALLM:GetDataSummary(locale)
    locale = locale or (YapperTable.Spellcheck and YapperTable.Spellcheck:GetLocale())
    local db = self:GetLocaleDB(locale)
    if not db then return nil end

    local freqList = {}
    for word, entry in pairs(db.freq) do
        table_insert(freqList, { word = word, count = entry.c, last = entry.t })
    end
    table_sort(freqList, function(a, b) return a.count > b.count end)

    local biasList = {}
    for key, entry in pairs(db.bias) do
        local typo, correction = key:match("^(.-):(.+)$")
        if typo and correction then
            table_insert(biasList,
                { typo = typo, correction = correction, count = entry.c, last = entry.t, utility = entry.u })
        end
    end
    table_sort(biasList, function(a, b) return a.count > b.count end)

    local autoList = {}
    for word, entry in pairs(db.auto) do
        table_insert(autoList, { word = word, count = entry.c, last = entry.t })
    end
    table_sort(autoList, function(a, b) return a.count > b.count end)

    local phList = {}
    for key, entry in pairs(db.phBias or {}) do
        local hash, corr = key:match("([^:]+):(.+)")
        table_insert(phList, { hash = hash, correction = corr, count = entry.c, last = entry.t })
    end
    table_sort(phList, function(a, b) return a.count > b.count end)

    local negList = {}
    for key, entry in pairs(db.negBias or {}) do
        local typo, word = key:match("^(.-):(.+)$")
        if typo and word then
            table_insert(negList, { typo = typo, word = word, count = entry.c, last = entry.t, utility = entry.u })
        end
    end
    table_sort(negList, function(a, b) return a.count > b.count end)

    return {
        freq      = freqList,
        bias      = biasList,
        phBias    = phList,
        negBias   = negList,
        auto      = autoList,
        total     = db.total,
        cap       = self:GetFreqCap(),
        threshold = self:GetAutoThreshold(),
    }
end

--- Export current learned data for a locale as a text block.
function YALLM:Export(locale)
    local db = self:GetLocaleDB(locale)
    if not db then return "No data for " .. tostring(locale) end

    local out = {}
    table_insert(out, "Yapper YALLM Export - " .. tostring(locale))
    table_insert(out, "------------------------------------------")

    local fCount = 0
    for _ in pairs(db.freq) do fCount = fCount + 1 end
    table_insert(out, string_format("Vocabulary (freq): %d words", fCount))

    local bCount = 0
    for _ in pairs(db.bias) do bCount = bCount + 1 end
    table_insert(out, string_format("Selection Bias:    %d pairs", bCount))

    local phCount = 0
    for _ in pairs(db.phBias) do phCount = phCount + 1 end
    table_insert(out, string_format("Phonetic Patterns: %d patterns", phCount))

    table_insert(out, "------------------------------------------")
    table_insert(out, "Top Frequency Words:")
    local data = self:GetDataSummary(locale)
    if data and data.freq then
        for i = 1, math_min(10, #data.freq) do
            local entry = data.freq[i]
            table_insert(out, string_format("  %s (%d usage)", entry.word, entry.count))
        end
    end

    return table.concat(out, "\n")
end

function YALLM:ClearSpecificUsage(usageType, key, locale)
    local db = self:GetLocaleDB(locale)
    if not db then return end
    if usageType == "freq" and db.freq[key] then
        db.freq[key] = nil
        db.total = math_max(0, db.total - 1)
        db.freqSortedDirty = true
    elseif usageType == "bias" and db.bias[key] then
        db.bias[key] = nil
    elseif usageType == "auto" and db.auto[key] then
        db.auto[key] = nil
    elseif usageType == "phBias" and db.phBias[key] then
        db.phBias[key] = nil
    end
end
