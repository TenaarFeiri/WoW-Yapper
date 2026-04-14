--[[
    YALLM: Yapper Adaptive Learning Language Model
    Personalized ranking and vocabulary tracking for the spellcheck engine.
]]

local YapperName, YapperTable = ...
local YALLM = {}
YapperTable.Spellcheck.YALLM = YALLM -- Hook into internal table
_G.YALLM = YALLM                     -- Global access for simplicity

-- Tuning Constants (used as fallbacks when config is not yet available)
local FREQ_CAP       = 2000  -- Max unique words to track
local AUTO_THRESHOLD = 10    -- Times sent before auto-added to dict
local MAX_BIAS_PAIRS = 500   -- Max Typo -> Selection pairs to track
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
    if not _G.YapperDB.SpellcheckLearned then
        _G.YapperDB.SpellcheckLearned = {
            freq = {},    -- word -> { c, t }
            bias = {},    -- typo:correction -> { c, t, u }
            auto = {},    -- word -> { c, t }
            phBias = {},  -- PhoneticHash(typo):correction -> { c, t }
            negBias = {}, -- typo:word -> { c, t }
            total = 0,    -- total unique words tracked
        }
    end
    self.db = _G.YapperDB.SpellcheckLearned

    -- Migration: Convert legacy numeric entries to table format
    local now = time()
    local tablesToMigrate = { "freq", "bias", "auto", "phBias", "negBias" }
    for _, tableName in ipairs(tablesToMigrate) do
        local tbl = self.db[tableName]
        if tbl then
            for k, v in pairs(tbl) do
                if type(v) == "number" then
                    tbl[k] = { c = v, t = now, u = 1 }
                end
            end
        end
    end
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
    if w:match("[^aeiouy]{7,}") then return false end

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
function YALLM:RecordUsage(text)
    if not self.db then return end
    local now = time()

    -- Fast-split into words (alphanumeric only)
    for word in text:gmatch("[%w']+") do
        if self:IsSaneWord(word) then
            local w = Clean(word)
            if not self.db.freq[w] then
                -- Handle Capacity (Weighted LRU Eviction)
                if self.db.total >= self:GetFreqCap() then
                    self:Prune("freq", self:GetFreqCap())
                end
                self.db.freq[w] = { c = 1, t = now }
                self.db.total = self.db.total + 1
            else
                local entry = self.db.freq[w]
                entry.c = entry.c + 1
                entry.t = now
            end
        end
    end
end

--- Record when a user picks a specific suggestion for a typo.
--- utilityGain may be:
---   true        -> 0.5  (backward-compat shorthand for "full boost")
---   false / nil -> 0    (no growth)
---   number      -> that exact increment applied to 'u' on each recording
function YALLM:RecordSelection(typo, correction, utilityGain)
    if not self.db then return end
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
    if not self.db.bias[key] then
        -- Handle Capacity
        local count = 0
        for _ in pairs(self.db.bias) do count = count + 1 end
        if count >= self:GetBiasCap() then
            self:Prune("bias", self:GetBiasCap())
        end
        self.db.bias[key] = { c = 1, t = now, u = 1 + gain }
    else
        local entry = self.db.bias[key]
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
            if not self.db.phBias[phKey] then
                self.db.phBias[phKey] = { c = 1, t = now }
            else
                local entry = self.db.phBias[phKey]
                entry.c = entry.c + 1
                entry.t = now
            end
        end
    end
end

--- Record a correction that was made by the user manually retyping (implicit backtrack).
--- Determines the appropriate learning strength based on whether the correction was
--- already a known candidate and how phonetically/textually close it is to the typo.
function YALLM:RecordImplicitCorrection(typo, correction, candidates)
    if not self.db then return end

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

    self:RecordSelection(typo, correction, utilityGain)

    -- Only penalise shown candidates if the correction wasn't among them,
    -- so we don't double-penalise words the user actually wanted.
    if not inCandidates and type(candidates) == "table" then
        self:RecordRejection(typo, candidates)
    end
end

--- Record when a user rejects a list of suggestions by clicking "More"
function YALLM:RecordRejection(typo, candidates)
    if not self.db or not typo or type(candidates) ~= "table" then return end
    local t = Clean(typo)
    local now = time()

    for _, candObj in ipairs(candidates) do
        local word = type(candObj) == "table" and (candObj.word or candObj.value) or candObj
        if word then
            -- Clean the candidate word before key construction to ensure consistent matching
            local key = t .. ":" .. Clean(word)
            if not self.db.negBias[key] then
                self.db.negBias[key] = { c = 1, t = now, u = 1.0 }
            else
                local entry = self.db.negBias[key]
                entry.c = entry.c + 1
                entry.t = now
                entry.u = math_min((entry.u or 1.0) + 0.2, 5.0)
            end
        end
    end
end

--- Record when a user sends a word that is currently flagged as a typo
function YALLM:RecordIgnored(word)
    if not self.db then return end
    if not self:IsSaneWord(word) then return end

    local w = Clean(word)
    local now = time()
    if not self.db.auto[w] then
        self.db.auto[w] = { c = 1, t = now }
    else
        local entry = self.db.auto[w]
        entry.c = entry.c + 1
        entry.t = now
    end

    if self.db.auto[w].c >= self:GetAutoThreshold() then
        -- Auto-promote to user dictionary
        local Spellcheck = YapperTable.Spellcheck
        if Spellcheck and Spellcheck.AddUserWord then
            local locale = Spellcheck:GetLocale()
            Spellcheck:AddUserWord(locale, word)
            self.db.auto[w] = nil -- Reset now that it's in the dict
            if YapperTable.Utils then
                YapperTable.Utils:Print("info", "YALLM: Learned new word '" .. word .. "' after persistent usage.")
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Scoring Logic
-- ---------------------------------------------------------------------------

--- Return the combined score bonus for a candidate using a pre-computed phonetic hash.
function YALLM:GetBonus(cand, typo, typoPhHash)
    if not self.db then return 0 end
    local c = Clean(cand)
    local t = Clean(typo)
    local bonus = 0

    -- 1. Frequency Bonus
    local freqEntry = self.db.freq[c]
    if freqEntry and freqEntry.c > 5 then
        bonus = bonus + WEIGHTS.freqBonus
    end

    -- 2. Bias Bonus
    local key = t .. ":" .. c
    local biasEntry = self.db.bias[key]
    if biasEntry then
        bonus = bonus + (WEIGHTS.biasBonus * math_min(biasEntry.c, 5))
    end

    -- 3. Phonetic Pattern Bonus (Optimized: use passed-down hash)
    if typoPhHash and self.db.phBias then
        local phKey = typoPhHash .. ":" .. c
        local phEntry = self.db.phBias[phKey]
        if phEntry then
            bonus = bonus + (WEIGHTS.phBonus * math_min(phEntry.c, 5))
        end
    end

    -- 4. Rejection Penalty
    if self.db.negBias then
        local negEntry = self.db.negBias[key]
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
function YALLM:Prune(tableName, limit)
    local tbl = self.db[tableName]
    if not tbl then return end

    local keys = {}
    for k in pairs(tbl) do table.insert(keys, k) end
    if #keys <= limit then return end

    -- Sort by relevance: Score = Count * Utility * RecencyFactor
    -- Items used a long time ago have lower recency factors.
    local now = time()
    table.sort(keys, function(a, b)
        local ea = tbl[a]
        local eb = tbl[b]

        -- Utility weighting (defaults to 1 if missing)
        local ua = ea.u or 1
        local ub = eb.u or 1

        -- Recency weighting (days-based linear decay).
        -- Score = (Count * Utility) / (DaysOld + 1)
        local ageA_days = math.max(0, (now - (ea.t or 0)) / 86400)
        local ageB_days = math.max(0, (now - (eb.t or 0)) / 86400)

        local scoreA = (ea.c * ua) / (ageA_days + 1)
        local scoreB = (eb.c * ub) / (ageB_days + 1)

        return scoreA > scoreB -- Keep high scores
    end)

    -- Evict the bottom 10% to make breathing room
    local targetSize = math.floor(limit * 0.9)
    for i = targetSize + 1, #keys do
        local k = keys[i]
        tbl[k] = nil
        if tableName == "freq" then
            self.db.total = math.max(0, self.db.total - 1)
        end
    end
end

function YALLM:Reset()
    _G.YapperDB.SpellcheckLearned = nil
    self:Init()
end

-- ---------------------------------------------------------------------------
-- UI Helpers
-- ---------------------------------------------------------------------------

function YALLM:GetDataSummary()
    if not self.db then return nil end

    local freqList = {}
    for word, entry in pairs(self.db.freq) do
        table.insert(freqList, { word = word, count = entry.c, last = entry.t })
    end
    table.sort(freqList, function(a, b) return a.count > b.count end)

    local biasList = {}
    for key, entry in pairs(self.db.bias) do
        local typo, correction = key:match("^(.-):(.+)$")
        if typo and correction then
            table.insert(biasList,
                { typo = typo, correction = correction, count = entry.c, last = entry.t, utility = entry.u })
        end
    end
    table.sort(biasList, function(a, b) return a.count > b.count end)

    local autoList = {}
    for word, entry in pairs(self.db.auto) do
        table.insert(autoList, { word = word, count = entry.c, last = entry.t })
    end
    table.sort(autoList, function(a, b) return a.count > b.count end)

    local phList = {}
    for key, entry in pairs(self.db.phBias or {}) do
        local hash, corr = key:match("([^:]+):(.+)")
        table.insert(phList, { hash = hash, correction = corr, count = entry.c, last = entry.t })
    end
    table.sort(phList, function(a, b) return a.count > b.count end)

    local negList = {}
    for key, entry in pairs(self.db.negBias or {}) do
        local typo, word = key:match("^(.-):(.+)$")
        if typo and word then
            table.insert(negList, { typo = typo, word = word, count = entry.c, last = entry.t, utility = entry.u })
        end
    end
    table.sort(negList, function(a, b) return a.count > b.count end)

    return {
        freq      = freqList,
        bias      = biasList,
        phBias    = phList,
        negBias   = negList,
        auto      = autoList,
        total     = self.db.total,
        cap       = self:GetFreqCap(),
        threshold = self:GetAutoThreshold(),
    }
end

function YALLM:ClearSpecificUsage(usageType, key)
    if not self.db then return end
    if usageType == "freq" and self.db.freq[key] then
        self.db.freq[key] = nil
        self.db.total = math.max(0, self.db.total - 1)
    elseif usageType == "bias" and self.db.bias[key] then
        self.db.bias[key] = nil
    elseif usageType == "auto" and self.db.auto[key] then
        self.db.auto[key] = nil
    elseif usageType == "phBias" and self.db.phBias[key] then
        self.db.phBias[key] = nil
    end
end
