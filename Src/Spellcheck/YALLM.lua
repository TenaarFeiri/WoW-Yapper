--[[
    YALLM: Yapper Adaptive Learning Language Model
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
    biasBonus = -5.0,      -- Past selection = significantly lower score
    phBonus = -3.0,        -- Phonetic pattern match = moderate score bonus
    negBias = 2.0,         -- Twice rejected (More...) = penalty (higher score)
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

-- ---------------------------------------------------------------------------
-- Config-driven cap accessors
-- ---------------------------------------------------------------------------

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
            bias = {},    -- typo:correction -> { c, t, u }
            auto = {},    -- word -> { c, t }
            phBias = {},  -- PhoneticHash(typo):correction -> { c, t }
            negBias = {}, -- typo:word -> { c, t }
            total = 0,    -- total unique words tracked
        }
    end
    return self.db[loc]
end

-- ---------------------------------------------------------------------------
-- Tracking Logic
-- ---------------------------------------------------------------------------

--- Standardise word for tracking
local function Clean(s)
    if not s then return "" end
    return s:lower():gsub("[%p%c%s]", "")
end

function YALLM:IsSaneWord(word)
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
                db.phBias[phKey] = { c = 1, t = now }
            else
                local entry = db.phBias[phKey]
                entry.c = entry.c + 1
                entry.t = now
            end
        end
    end
end

--- Record a correction that was made by the user manually retyping (implicit backtrack).
--- Determines the appropriate learning strength based on whether the correction was
--- already a known candidate and how phonetically/textually close it is to the typo.
function YALLM:RecordImplicitCorrection(typo, correction, candidates, locale)
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
            -- Fall back to raw edit distance for a cheap sanity gate.
            -- We compute a simple character-level distance without the full
            -- EditDistance function to avoid a hard dependency on Spellcheck internals.
            local lenDiff = math_abs(#t - #c)
            -- Treat words more than 40% different in length as "too different".
            local maxLen = math_max(#t, #c)
            if maxLen == 0 or lenDiff / maxLen > 0.4 then
                -- Too different: silently skip rather than pollute bias with noise.
                return
            end
            -- Small shared prefix is a lightweight similarity proxy.
            local sharedPrefix = 0
            for i = 1, math_min(#t, #c) do
                if t:sub(i, i) ~= c:sub(i, i) then break end
                sharedPrefix = sharedPrefix + 1
            end
            local similarity = sharedPrefix / maxLen
            if similarity >= 0.4 then
                -- Reasonably close — moderate signal that grows with repetition.
                utilityGain = 0.15
            elseif similarity >= 0.2 then
                -- Vaguely related — weak initial signal, still grows slowly.
                utilityGain = 0.05
            else
                -- Effectively unrelated — skip.
                return
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
            if YapperTable.Utils then
                YapperTable.Utils:Print("info",
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
    local db = self:GetLocaleDB(locale)
    if not db then return 0 end
    local c = Clean(cand)
    local t = Clean(typo)
    local bonus = 0

    -- 1. Frequency Bonus
    local freqEntry = db.freq[c]
    if freqEntry and freqEntry.c > 2 then
        -- Use logarithmic scaling so common words get a better proportional boost
        local logBonus = math_min(math.log(freqEntry.c) / 2, 3.0)
        bonus = bonus + (WEIGHTS.freqBonus * logBonus)
    end

    -- 2. Bias Bonus
    local key = t .. ":" .. c
    local biasEntry = db.bias[key]
    if biasEntry then
        -- Cap selection bias so it provides a strong boost (±10.0) without
        -- indefinitely pinning candidates regardless of intent.
        local cappedBias = math_min(biasEntry.c, 2)
        bonus = bonus + (WEIGHTS.biasBonus * cappedBias)
    end

    -- 3. Phonetic Pattern Bonus (Optimized: use passed-down hash)
    if typoPhHash and db.phBias then
        local phKey = typoPhHash .. ":" .. c
        local phEntry = db.phBias[phKey]
        if phEntry then
            -- Moderate boost (±6.0) for generalized phonetic learning
            local cappedPh = math_min(phEntry.c, 2)
            bonus = bonus + (WEIGHTS.phBonus * cappedPh)
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

-- ---------------------------------------------------------------------------
-- Maintenance
-- ---------------------------------------------------------------------------

--- Systematic pruning of a learning table
function YALLM:Prune(tableName, limit, locale)
    local db = self:GetLocaleDB(locale)
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
        if tableName == "freq" then
            db.total = math_max(0, db.total - 1)
        end
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
    for i = 1, math_min(10, #data.freq) do
        local entry = data.freq[i]
        table_insert(out, string_format("  %s (%d usage)", entry.word, entry.count))
    end

    return table.concat(out, "\n")
end

function YALLM:ClearSpecificUsage(usageType, key, locale)
    local db = self:GetLocaleDB(locale)
    if not db then return end
    if usageType == "freq" and db.freq[key] then
        db.freq[key] = nil
        db.total = math_max(0, db.total - 1)
    elseif usageType == "bias" and db.bias[key] then
        db.bias[key] = nil
    elseif usageType == "auto" and db.auto[key] then
        db.auto[key] = nil
    elseif usageType == "phBias" and db.phBias[key] then
        db.phBias[key] = nil
    end
end
