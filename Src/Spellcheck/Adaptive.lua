--[[
    YAS: Yapper Adaptive Spellcheck
    Personalized ranking and vocabulary tracking for the spellcheck engine.
]]

local _, YapperTable = ...
local YAS = {}
YapperTable.Spellcheck.YAS = YAS
local Utils = YapperTable.Utils
local IsDebugEnabled = YapperTable.Spellcheck.IsDebugEnabled

-- Cap defaults (used as fallbacks when config is not yet available).
-- WEIGHTS are fixed scoring constants, not config fallbacks — planned to
-- become per-locale learned weights in the adaptive scorer rework.
local FREQ_CAP = 2000      -- Max unique words to track
local AUTO_THRESHOLD = 10  -- Times sent before auto-added to dict
local AUTO_CAP = 500       -- Max auto-learn tracking entries
local MAX_BIAS_PAIRS = 500 -- Max Typo -> Selection pairs to track
local INTENT_CAP = 1000    -- Max per-token intent records
local BIGRAM_CAP = 2000    -- Max prev->next transition entries (all buckets)
local CONF_CAP = 200       -- Max confusion-pair entries in errProfile
local CONSOLIDATION_CHUNK = 200 -- Entries per background-consolidation tick
local DECAY_AGE = 30 * 86400   -- Entries cold this long get halved on sweep
local INTENT_STALE_AGE = 60 * 86400 -- Unclassified intent older than this is dropped
-- Intent classification thresholds (session-clock values, not persisted):
-- a word sent unchanged INTENT_CONSISTENT_N times with no correction events
-- is INTENTIONAL (typos vary; names/consistent spellings don't).  A send
-- within INTENT_EXPOSURE_TTL of the popup showing, at least INTENT_DWELL_MIN
-- seconds after it appeared, is a waiver (saw it, deliberately sent anyway).
local INTENT_CONSISTENT_N = 3
local INTENT_DWELL_MIN    = 1.0
local INTENT_EXPOSURE_TTL = 30
local WEIGHTS = {
    freqBonus = -2.5,      -- High usage = lower score (better)
    biasBonus = -8.0,      -- Past selection = significantly lower score
    phBonus = -4.0,        -- Phonetic pattern match = moderate score bonus
    negBias = 3.0,         -- Rejected via "More..." = penalty (higher score)
    bigramBonus = -2.0,    -- Candidate follows the user's observed prev->next history
    errAffinity = -0.25,   -- Candidate's needed edit matches the user's habitual slip class
}

local time = time
local pairs = pairs
local ipairs = ipairs
local type = type
local next = next
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local table_insert = table.insert
local table_sort = table.sort
local string_format = string.format
local string_sub = string.sub

local function VerifyFreqIndex(db)
    if not IsDebugEnabled() then return end
    if type(db) ~= "table" or type(db.freq) ~= "table" then return end
    if type(db.freqSorted) ~= "table" then
        error("YAS freqSorted invariant failed: missing sorted index")
    end

    local seen = {}
    local count = 0
    local prev = nil
    for i = 1, #db.freqSorted do
        local w = db.freqSorted[i]
        if type(w) ~= "string" or w == "" then
            error("YAS freqSorted invariant failed: invalid word at index " .. tostring(i))
        end
        if prev and w < prev then
            error("YAS freqSorted invariant failed: non-monotonic order")
        end
        if not db.freq[w] then
            error("YAS freqSorted invariant failed: index contains missing freq key '" .. tostring(w) .. "'")
        end
        if seen[w] then
            error("YAS freqSorted invariant failed: duplicate key '" .. tostring(w) .. "'")
        end
        seen[w] = true
        prev = w
        count = count + 1
    end

    local freqCount = 0
    for word in pairs(db.freq) do
        freqCount = freqCount + 1
        if not seen[word] then
            error("YAS freqSorted invariant failed: missing key '" .. tostring(word) .. "'")
        end
    end
    if freqCount ~= count then
        error("YAS freqSorted invariant failed: cardinality mismatch")
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

--- Returns true if YAS is enabled in the configuration.
function YAS:IsEnabled()
    local sc = YapperTable.Spellcheck
    if not sc or not sc:IsEnabled() then return false end
    if not sc.Dictionaries or next(sc.Dictionaries) == nil then return false end
    local cfg = YapperTable.Config and YapperTable.Config.Spellcheck
    return (cfg and cfg.YASEnabled ~= false)
end

--- Returns the maximum number of unique vocabulary words to track.
function YAS:GetFreqCap()
    local cfg = YapperTable.Config and YapperTable.Config.Spellcheck
    local v = tonumber(cfg and cfg.YASFreqCap) or FREQ_CAP
    return math_max(100, math_min(v, 10000))
end

--- Returns the maximum number of typo->correction bias pairs to track.
function YAS:GetBiasCap()
    local cfg = YapperTable.Config and YapperTable.Config.Spellcheck
    local v = tonumber(cfg and cfg.YASBiasCap) or MAX_BIAS_PAIRS
    return math_max(50, math_min(v, 5000))
end

--- Returns the number of sends before a word is auto-promoted to the user dictionary.
function YAS:GetAutoThreshold()
    local cfg = YapperTable.Config and YapperTable.Config.Spellcheck
    local v = tonumber(cfg and cfg.YASAutoThreshold) or AUTO_THRESHOLD
    return math_max(1, math_min(v, 200))
end

--- Returns the maximum number of rejected suggestion pairs to track.
function YAS:GetNegBiasCap()
    local cfg = YapperTable.Config and YapperTable.Config.Spellcheck
    local v = tonumber(cfg and cfg.YASNegBiasCap) or MAX_BIAS_PAIRS
    return math_max(100, math_min(v, 10000))
end

--- Returns the maximum number of pending auto-learn tracking entries.
function YAS:GetAutoCap()
    local cfg = YapperTable.Config and YapperTable.Config.Spellcheck
    local v = tonumber(cfg and cfg.YASAutoCap) or AUTO_CAP
    return math_max(50, math_min(v, 5000))
end

--- Returns the maximum number of per-token intent records.
function YAS:GetIntentCap()
    local cfg = YapperTable.Config and YapperTable.Config.Spellcheck
    local v = tonumber(cfg and cfg.YASIntentCap) or INTENT_CAP
    return math_max(100, math_min(v, 10000))
end

--- Returns the maximum number of bigram transition entries (summed over
--- all preceding-word buckets).
function YAS:GetBigramCap()
    local cfg = YapperTable.Config and YapperTable.Config.Spellcheck
    local v = tonumber(cfg and cfg.YASBigramCap) or BIGRAM_CAP
    return math_max(200, math_min(v, 20000))
end

-- Runtime clock for exposure/dwell measurements.  GetTime() is the WoW
-- session clock (sub-second); os.clock() is the headless test fallback.
-- Distinct from `time()` (epoch) which stamps persisted records.
local function RtNow()
    if type(GetTime) == "function" then return GetTime() end
    return os.clock()
end

-- Learned-scorer model: the WEIGHTS table stays the frozen "safe" fallback;
-- what adapts is a per-locale multiplier vector m[i] centred on 1.0, so
-- scoring degrades to the tuned constants exactly when the model regresses.
--   bonus_i = WEIGHT_i * f_i * m_i
-- Update is a bounded perceptron: accepted candidates reinforce the features
-- that surfaced them; rejected candidates dampen them.
local MODEL_FEATURES = { "freq", "bias", "ph", "neg", "bigram", "err" }
local MODEL_LR0 = 0.02          -- initial learning rate
local MODEL_LR_DECAY = 500      -- lr = LR0 / (1 + updates/DECAY)
local MODEL_MIN, MODEL_MAX = 0.25, 4.0
local EVAL_MIN_SAMPLES = 20     -- self-eval needs this many promoted picks
local EVAL_DAMPEN_RATIO = 0.4   -- recorrected share that triggers regression
-- Read-path fallback: all-neutral multipliers, identical to frozen WEIGHTS.
local DEFAULT_MODEL_M = { freq = 1, bias = 1, ph = 1, neg = 1, bigram = 1, err = 1 }

--- Per-locale learned model; lazily attached to the partition.
local function GetModel(db)
    local m = db.model
    if type(m) ~= "table" then
        m = {
            m = { freq = 1, bias = 1, ph = 1, neg = 1, bigram = 1, err = 1 },
            updates = 0,
            eval = { promotedAccepted = 0, retypeAfterPromoted = 0 },
        }
        db.model = m
    end
    m.m = m.m or {}
    m.eval = m.eval or { promotedAccepted = 0, retypeAfterPromoted = 0 }
    for _, k in ipairs(MODEL_FEATURES) do
        if type(m.m[k]) ~= "number" then m.m[k] = 1 end
    end
    return m
end

--- Apply one bounded perceptron update.  dir = +1 reinforces features that
--- led to an accepted candidate, -1 dampens features behind a rejection.
local function ModelUpdate(db, f, dir)
    local m = GetModel(db)
    m.updates = (m.updates or 0) + 1
    local lr = MODEL_LR0 / (1 + (m.updates / MODEL_LR_DECAY))
    for _, k in ipairs(MODEL_FEATURES) do
        local mv = m.m[k] + dir * lr * f[k]
        m.m[k] = math_min(MODEL_MAX, math_max(MODEL_MIN, mv))
    end
    -- Weights feed scoring; invalidate suggestion caches.
    db._rev = (db._rev or 0) + 1
end

--- Self-eval: when YAS-surfaced picks get re-corrected too often, regress
--- all learned multipliers halfway toward the frozen defaults.
local function MaybeRegressModel(db)
    local m = GetModel(db)
    local ev = m.eval
    local total = (ev.promotedAccepted or 0) + (ev.retypeAfterPromoted or 0)
    if total < EVAL_MIN_SAMPLES then return end
    if (ev.retypeAfterPromoted or 0) / total > EVAL_DAMPEN_RATIO then
        for _, k in ipairs(MODEL_FEATURES) do
            m.m[k] = 1 + (m.m[k] - 1) * 0.5
        end
        ev.promotedAccepted = 0
        ev.retypeAfterPromoted = 0
    end
end

-- ---------------------------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------------------------

-- Stranded partition keys: "enBASE" was the legacy flat-DB migration target
-- and "enBase" is the shared-dict addon key, but partition keys are dict
-- locales ("enUS", "enGB", ...) — GetLocale() can never produce either, so
-- anything under them is unreachable. "_pending" parks data recorded before
-- a locale resolves; "_legacy" parks flat pre-partition data.
local LEGACY_PARTITION_KEYS = { enBASE = true, enBase = true }
local LEGACY_SOURCES = { "_legacy", "enBASE", "enBase", "_pending" }

--- Merge one intent record (different shape from the count/utility tables:
--- per-token signal counters + an optional explicit pin).
local function MergeIntentRecord(d, e)
    d.c = (d.c or 0) + (e.c or 0)
    d.sentUnchanged = (d.sentUnchanged or 0) + (e.sentUnchanged or 0)
    d.waived        = (d.waived or 0) + (e.waived or 0)
    d.accepted      = (d.accepted or 0) + (e.accepted or 0)
    d.corrected     = (d.corrected or 0) + (e.corrected or 0)
    d.lastSeen      = math_max(d.lastSeen or 0, e.lastSeen or 0)
    d.t             = d.lastSeen -- keep the pruneable timestamp in sync
    -- Explicit pins survive merges; an existing pin is not overwritten.
    if not d.pinned then d.pinned = e.pinned end
end

--- Merge one partition's learning tables into another (counts sum,
--- recency keeps the newest timestamp, utility keeps the max).
local function MergePartition(dst, src)
    local merged = false
    for _, tbl in ipairs({ "freq", "bias", "auto", "phBias", "negBias" }) do
        local dt, st = dst[tbl], src[tbl]
        if type(st) == "table" then
            if type(dt) ~= "table" then
                dst[tbl] = st
                merged = true
            else
                for k, e in pairs(st) do
                    local d = dt[k]
                    if d then
                        d.c = (d.c or 0) + (e.c or 0)
                        d.t = math_max(d.t or 0, e.t or 0)
                        if e.u then d.u = math_max(d.u or 1, e.u) end
                    else
                        dt[k] = e
                    end
                    merged = true
                end
            end
        end
    end
    if type(src.intent) == "table" then
        if type(dst.intent) ~= "table" then
            dst.intent = src.intent
        else
            for k, e in pairs(src.intent) do
                local d = dst.intent[k]
                if d then MergeIntentRecord(d, e) else dst.intent[k] = e end
            end
        end
        merged = true
    end
    -- Nested transition table: bigram[prev][next] = { c, t }
    if type(src.bigram) == "table" then
        if type(dst.bigram) ~= "table" then
            dst.bigram = src.bigram
        else
            for prev, bucket in pairs(src.bigram) do
                local db_ = dst.bigram[prev]
                if type(db_) ~= "table" then
                    dst.bigram[prev] = bucket
                else
                    for nxt, e in pairs(bucket) do
                        local d = db_[nxt]
                        if d then
                            d.c = (d.c or 0) + (e.c or 0)
                            d.t = math_max(d.t or 0, e.t or 0)
                        else
                            db_[nxt] = e
                        end
                    end
                end
            end
        end
        merged = true
    end
    if type(src.errProfile) == "table" then
        local dep = dst.errProfile
        if type(dep) ~= "table" then
            dst.errProfile = src.errProfile
        else
            local sep = src.errProfile
            if type(sep.ops) == "table" then
                dep.ops = dep.ops or {}
                for k, v in pairs(sep.ops) do dep.ops[k] = (dep.ops[k] or 0) + v end
            end
            if type(sep.conf) == "table" then
                dep.conf = dep.conf or {}
                for k, v in pairs(sep.conf) do dep.conf[k] = (dep.conf[k] or 0) + v end
            end
        end
        merged = true
    end
    -- Learned multipliers: prefer the destination's (it's the live partition);
    -- adopt the source's only when the destination never learned.
    if type(src.model) == "table" and type(dst.model) ~= "table" then
        dst.model = src.model
        merged = true
    end
    -- Shadow decision log: append source entries, keep the newest entries.
    if type(src.autocorrLog) == "table" and #src.autocorrLog > 0 then
        local log = dst.autocorrLog
        if type(log) ~= "table" then
            log = {}
            dst.autocorrLog = log
        end
        for _, e in ipairs(src.autocorrLog) do log[#log + 1] = e end
        while #log > 50 do table.remove(log, 1) end
        merged = true
    end
    return merged
end

--- Recount a partition's cached cardinality counters after structural change.
local function RecountPartition(db)
    local function count(t)
        local n = 0
        if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
        return n
    end
    db.total        = count(db.freq)
    db.biasCount    = count(db.bias)
    db.autoCount    = count(db.auto)
    db.phBiasCount  = count(db.phBias)
    db.negBiasCount = count(db.negBias)
    db.intentCount  = count(db.intent)
    local bg = 0
    if type(db.bigram) == "table" then
        for _, bucket in pairs(db.bigram) do
            if type(bucket) == "table" then
                for _ in pairs(bucket) do bg = bg + 1 end
            end
        end
    end
    db.bigramCount = bg
    db.freqSortedDirty = true
end

--- Initialize the YAS learning system and migrate legacy data if needed.
function YAS:Init()
    if not _G.YapperDB then return end

    -- Structure: _G.YapperDB.SpellcheckLearned[locale] = { freq = {}, bias = {}, ... }
    if not _G.YapperDB.SpellcheckLearned then
        _G.YapperDB.SpellcheckLearned = {}
    end

    -- Migration: if the root table itself contains 'freq', it's a legacy
    -- flat pre-partition DB. Park it under "_legacy" so the first real
    -- locale partition can fold it in (previously this was moved to the
    -- "enBASE" key, which no locale ever reads — stranding all learned data).
    local legacy = _G.YapperDB.SpellcheckLearned
    if legacy.freq and type(legacy.freq) == "table" then
        local oldCopy = {}
        for k, v in pairs(legacy) do
            oldCopy[k] = v
            legacy[k] = nil -- Clear root key
        end
        legacy._legacy = oldCopy
        Utils:Print("info", "YAS: Parked legacy flat database for merge into the active locale partition.")
    end

    self.db = _G.YapperDB.SpellcheckLearned
end

--- Returns the locale-specific learning database.
---@param locale string|nil The dict locale key (e.g., "enUS"). Defaults to
---       the current spellcheck locale; before a locale resolves, data parks
---       under "_pending" and merges forward later.
---@param noCreate boolean|nil If true, never create a missing partition
---       (use on read hot paths so lookups don't allocate SavedVars tables).
---@return table|nil db The locale database or nil if unavailable.
function YAS:GetLocaleDB(locale, noCreate)
    if not self.db then return nil end
    local loc = locale
    if not loc then
        local sc = YapperTable.Spellcheck
        loc = (sc and sc.GetLocale and sc:GetLocale()) or nil
    end
    if not loc then loc = "_pending" end

    local db = self.db[loc]
    if not db then
        if noCreate then return nil end
        db = {
            freq = {},    -- word -> { c, t }
            freqSorted = {}, -- derived sorted array of cleaned keys from freq (alphabetical order)
            freqSortedDirty = false, -- true when freq has changed and index must rebuild
            bias = {},    -- typo:correction -> { c, t, u }
            auto = {},    -- word -> { c, t }
            autoCount = 0,-- cached count of auto entries
            phBias = {},  -- PhoneticHash(typo):correction -> { c, t }
            negBias = {}, -- typo:word -> { c, t }
            intent = {},  -- token -> intent record (Phase 1: see _ClassifyRecord)
            intentCount = 0,
            bigram = {},  -- prev -> { [next] = { c, t } } context transitions
            bigramCount = 0,
            errProfile = { ops = {}, conf = {} }, -- habitual error classes
            total = 0,    -- total unique words tracked
        }
        self.db[loc] = db
    end
    db._locale = loc -- lets record-level helpers reach back for pruning
    db.freq = Utils:EnsureTable(db.freq)
    -- Retrofit post-Phase-0 tables onto partitions created before they existed.
    db.intent = Utils:EnsureTable(db.intent)
    db.bigram = Utils:EnsureTable(db.bigram)
    db.errProfile = Utils:EnsureTable(db.errProfile)
    db.errProfile.ops = Utils:EnsureTable(db.errProfile.ops)
    db.errProfile.conf = Utils:EnsureTable(db.errProfile.conf)
    if db.total == nil or db.autoCount == nil or db.negBiasCount == nil
        or db.intentCount == nil or db.bigramCount == nil then
        RecountPartition(db)
    end
    if db.freqSortedDirty == nil then
        db.freqSortedDirty = true
    end
    if db.freqSorted ~= nil and type(db.freqSorted) ~= "table" then
        db.freqSorted = nil
        db.freqSortedDirty = true
    end

    -- Fold stranded sources into the first real locale partition that asks:
    -- parked legacy flats, orphaned enBASE/enBase partitions, and pending
    -- pre-locale recordings.
    if not LEGACY_PARTITION_KEYS[loc] and loc ~= "_pending" then
        local merged = false
        for _, key in ipairs(LEGACY_SOURCES) do
            local src = self.db[key]
            if type(src) == "table" and MergePartition(db, src) then
                self.db[key] = nil
                merged = true
            end
        end
        if merged then
            RecountPartition(db)
            db._rev = (db._rev or 0) + 1
        end
    end

    return db
end

--- Ensures the frequency-sorted index is up-to-date, rebuilding if dirty.
---@param locale string|nil The locale key.
---@return table|nil freqSorted The sorted frequency array or nil if db is unavailable.
function YAS:EnsureFreqSorted(locale)
    local db = self:GetLocaleDB(locale, true)
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

--- Standardise word for tracking. Uses the active engine's canonicaliser
--- (e.g. case-folding, accent rules) so learned keys match dictionary form.
local function Clean(s)
    if not s then return "" end
    local sc = YapperTable.Spellcheck
    if sc and sc.NormaliseWord then
        s = sc.NormaliseWord(s)
    else
        s = s:lower()
    end
    return s:gsub("[%p%c%s]", "")
end

--- Cheap error-operation classifier (typo a -> correction b).  Not a full
--- edit-script backtrace — just enough to bucket the user's habitual slips:
--- "transpose", "substitute", "insert", "delete", "other".  Also returns the
--- differing byte pair for confusion-pair stats when applicable.
---@return string op, number|nil aByte, number|nil bByte
local function ClassifyEdit(a, b)
    local la, lb = #a, #b
    if la == lb then
        local d1, d2
        for i = 1, la do
            if a:byte(i) ~= b:byte(i) then
                if not d1 then d1 = i
                elseif not d2 then d2 = i
                else return "substitute" end -- 3+ diffs: not a clean op
            end
        end
        if d1 and d2 then
            if d2 == d1 + 1 and a:byte(d1) == b:byte(d2) and a:byte(d2) == b:byte(d1) then
                return "transpose"
            end
            return "substitute", a:byte(d1), b:byte(d1)
        end
        if d1 then return "substitute", a:byte(d1), b:byte(d1) end
        return "other"
    elseif lb == la + 1 then
        for i = 1, lb do
            if a:byte(i) ~= b:byte(i) then return "insert", nil, b:byte(i) end
        end
        return "insert", nil, b:byte(lb)
    elseif la == lb + 1 then
        for i = 1, la do
            if a:byte(i) ~= b:byte(i) then return "delete", a:byte(i), nil end
        end
        return "delete", a:byte(la), nil
    end
    return "other"
end

--- Per-candidate feature magnitudes (same scale as the legacy GetBonus
--- terms: counts already log-scaled/capped).  Pure read — no writes.
local function FeatureVector(db, t, c, cand, prevWord, typoPhHash)
    local f = { freq = 0, bias = 0, ph = 0, neg = 0, bigram = 0, err = 0 }

    local freqEntry = db.freq and (db.freq[cand] or db.freq[c])
    if freqEntry and freqEntry.c > 2 then
        f.freq = math_min(math.log(freqEntry.c) / 2, 3.0)
    end

    local key = t .. ":" .. c
    local biasEntry = db.bias and db.bias[key]
    if biasEntry then
        f.bias = math_min(biasEntry.c, 3) * math_max(biasEntry.u or 1.0, 1.0)
    end

    if typoPhHash and db.phBias then
        local phEntry = db.phBias[typoPhHash .. ":" .. c]
        if phEntry then
            f.ph = math_min(phEntry.c, 2) * math_max(phEntry.u or 1.0, 1.0)
        end
    end

    if db.negBias then
        local negEntry = db.negBias[key]
        if negEntry then
            local ageDays = math_max(0, (time() - (negEntry.t or 0)) / 86400)
            f.neg = math_min(negEntry.c, 5) / (ageDays / 30 + 1)
        end
    end

    if prevWord and prevWord ~= "" and db.bigram then
        local bucket = db.bigram[Clean(prevWord)]
        local e = bucket and (bucket[c] or bucket[cand])
        if e then f.bigram = math_min(e.c, 5) end
    end

    if db.errProfile and db.errProfile.ops and t ~= c then
        local op = ClassifyEdit(t, c)
        f.err = math_min(db.errProfile.ops[op] or 0, 8)
    end

    return f
end

--- Checks if a word passes sanity filters for learning (length, consonant
--- clusters, keyboard smash, engine veto, n-gram anchors).
---@param w string The word to check (should be lowercase, no punctuation).
---@param locale string|nil The locale key for n-gram checking.
---@return boolean isSane True if the word is safe to learn.
function YAS:IsSaneWord(w, locale)
    if not w then return false end
    -- Caller passes pre-cleaned input (lowercase, no punctuation).
    if #w < 2 or #w > 40 then return false end

    local sc = YapperTable.Spellcheck
    local engine = sc and sc._EngineForLocale
        and sc:_EngineForLocale(locale or sc:GetLocale())
    if not engine and sc and sc.GetActiveEngine then
        -- YAS partitions ("enBASE") aren't dict locales; fall back to the
        -- active locale's engine for word-shape judgement.
        engine = sc:GetActiveEngine()
    end

    -- Vowel-neutral form via the engine's vowel model (fallback: ASCII vowels
    -- for the pre-engine window, when learning is inert anyway).
    local norm = (engine and engine.NormaliseVowels and engine.NormaliseVowels(w))
        or w:gsub("[aeiouy]", "*")

    -- 1. Reject 7+ consecutive consonants (non-'*' in the vowel-normal form).
    --    Lua patterns have no {n,} quantifier, so the class is repeated.
    if norm:match("[^*][^*][^*][^*][^*][^*][^*]") then return false end

    -- 2. Reject keyboard smash (3+ identical consecutive characters).
    if w:match("(.)%1%1") then return false end

    -- 3. Engine-specific word-shape veto (optional contract field).
    if engine and engine.IsSaneWord then
        if sc:_SafeEngineCall(engine, "IsSaneWord", false, w) ~= true then
            return false
        end
    end

    -- 4. N-gram anchor: a real word should share at least one vowel-neutral
    -- n-gram with the dictionary. The index name and gram size follow
    -- GetNgramN() (dictionaries build "ngramIndex"..N and "ngramIndex"..N+1).
    -- The base dictionary loads asynchronously after login, so the index may
    -- be absent for the first few messages; in that case this check is
    -- skipped (harmless false-negatives, while the false-positives from
    -- checks 1-2 are the real concern).
    local dict = sc and sc.GetDictionary and sc:GetDictionary()
    local n = (sc and sc.GetNgramN and sc:GetNgramN()) or 2
    local ngramIdx = dict and dict["ngramIndex" .. n]
    if ngramIdx then
        local foundValidGram = false
        for i = 1, #norm - n + 1 do
            local g = string_sub(norm, i, i + n - 1)
            if ngramIdx[g] then
                foundValidGram = true
                break
            end
        end
        if not foundValidGram then return false end
    end

    return true
end

--- Record usage frequency of words in a message
function YAS:RecordUsage(text, locale)
    if not self:IsEnabled() then return end
    local db = self:GetLocaleDB(locale)
    if not db then return end
    local now = time()
    
    local isSlashCommand = (text:find("^%s*/") ~= nil)
    local isFirstWord = true

    local sc = YapperTable.Spellcheck
    -- Tokenise with the engine's word-boundary rules; normalise with the
    -- target locale's canonicaliser.
    local iter = sc and sc.IterWords or function(t)
        local g = t:gmatch("()([%w']+)()")
        return function()
            local s, w, e = g()
            if s then return s, e - 1, w end
        end
    end
    local normFn = (sc and sc._NormForLocale and sc:_NormForLocale(locale))
        or function(x) return x:lower() end
    local wrote = false
    local prevW -- last sane token seen, for bigram transitions

    for s, e, word in iter(text) do
        local skip = false
        if isFirstWord then
            isFirstWord = false
            if isSlashCommand then skip = true end
        end
        if word:sub(1, 1) == "{" then skip = true end -- raid icons

        local w = normFn(word)
        local isBlocked = sc and sc.IsWordBlocked and sc:IsWordBlocked(w, locale, true)

        if not skip and not isBlocked and self:IsSaneWord(w, locale) then
            -- Bigram transition: prev sane word -> this word. Sentence-initial
            -- words use the "<s>" pseudo-token so openers are context too.
            if db.bigram then
                local prevKey = prevW or "<s>"
                local bucket = db.bigram[prevKey]
                if not bucket then bucket = {}; db.bigram[prevKey] = bucket end
                local be = bucket[w]
                if not be then
                    db.bigramCount = (db.bigramCount or 0) + 1
                    if db.bigramCount > self:GetBigramCap() then
                        self:PruneBigrams(self:GetBigramCap(), locale)
                    end
                    be = { c = 0, t = 0 }
                    bucket[w] = be
                end
                be.c = be.c + 1
                be.t = now
                wrote = true -- bigram feeds GetBonus scoring
            end
            prevW = w
            if not db.freq[w] then
                -- Capacity: prune least-useful entries before inserting.
                if db.total >= self:GetFreqCap() then
                    self:Prune("freq", self:GetFreqCap(), locale)
                end
                db.freq[w] = { c = 1, t = now }
                db.total = db.total + 1
                wrote = true
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
                wrote = true
            end
        end
    end
    -- Frequency feeds GetBonus, so any write must invalidate cached scores.
    if wrote then db._rev = (db._rev or 0) + 1 end
end

-- ---------------------------------------------------------------------------
-- Intent classification (Phase 1)
--
-- Every misspelled token that reaches send accumulates a small record of
-- behavioural signals: how often it was sent unchanged, whether the
-- suggestion popup was visibly shown in time to matter, whether the user
-- ever accepted a correction or retyped the word, and any explicit pin
-- (Add to Dictionary / Ignore Word).  The classifier answers one question:
-- did the user mean to write it that way?
--
--   ACCIDENT     — corrected at least once; feeds bias/error learning.
--   WAIVER       — popup seen (dwell), token still sent unchanged.
--   INTENTIONAL  — consistent unchanged sends with zero corrections;
--                  the only class allowed to auto-promote to the user dict.
-- ---------------------------------------------------------------------------

--- Fetch (or lazily create under cap) the intent record for a token.
---@param db table Locale partition.
---@param w string Cleaned token.
---@param noCreate boolean|nil Read-only lookup.
local function GetIntentRecord(db, w, noCreate)
    if type(db.intent) ~= "table" then
        if noCreate then return nil end
        db.intent = {}
    end
    local rec = db.intent[w]
    if rec or noCreate then return rec end
    db.intentCount = (db.intentCount or 0) + 1
    if db.intentCount > YAS:GetIntentCap() then
        YAS:Prune("intent", YAS:GetIntentCap(), db._locale)
        local count = 0
        for _ in pairs(db.intent) do count = count + 1 end
        db.intentCount = count
    end
    rec = { c = 0, t = 0, sentUnchanged = 0, waived = 0, accepted = 0, corrected = 0, lastSeen = 0 }
    db.intent[w] = rec
    return rec
end

--- Classify an intent record.  Pinned classes win; any correction evidence
--- means ACCIDENT; consistent unchanged sends mean INTENTIONAL; observed
--- dwell-and-send means WAIVER; otherwise unclassified (nil).
local function ClassifyRecord(rec)
    if not rec then return nil end
    if rec.pinned then return rec.pinned end
    if (rec.accepted or 0) > 0 or (rec.corrected or 0) > 0 then return "ACCIDENT" end
    if (rec.sentUnchanged or 0) >= INTENT_CONSISTENT_N then return "INTENTIONAL" end
    if (rec.waived or 0) > 0 then return "WAIVER" end
    return nil
end

--- Note that the suggestion popup is now visible for `word` (session-local
--- exposure credit consumed by the next RecordIgnored for the same token).
function YAS:RecordExposure(word, locale)
    if not self:IsEnabled() then return end
    if type(word) ~= "string" then return end
    local w = Clean(word)
    if w == "" then return end
    self._exposed = self._exposed or {}
    local nowRt = RtNow()
    -- Opportunistic hygiene: drop exposures older than the crediting TTL so
    -- words that were shown but never sent can't grow the table unbounded.
    local n = 0
    for k, e in pairs(self._exposed) do
        if nowRt - e.t > INTENT_EXPOSURE_TTL then
            self._exposed[k] = nil
        else
            n = n + 1
            if n > 200 then break end
        end
    end
    self._exposed[w] = { t = nowRt, shown = true }
end

--- Classify the intent of a token: "ACCIDENT" | "WAIVER" | "INTENTIONAL" | nil.
function YAS:GetIntent(word, locale)
    if not self:IsEnabled() then return nil end
    if type(word) ~= "string" then return nil end
    local w = Clean(word)
    if w == "" then return nil end
    local db = self:GetLocaleDB(locale, true)
    local rec = db and GetIntentRecord(db, w, true)
    return ClassifyRecord(rec)
end

--- Pin a token's intent from an explicit user action.  class is
--- "INTENTIONAL" (Add to Dictionary) or "WAIVER" (Ignore Word).
--- Pinned classes are permanent and immune to pruning.
function YAS:PinIntent(word, class, locale)
    if not self:IsEnabled() then return end
    if class ~= "INTENTIONAL" and class ~= "WAIVER" and class ~= "ACCIDENT" then return end
    if type(word) ~= "string" then return end
    local db = self:GetLocaleDB(locale)
    if not db then return end
    local w = Clean(word)
    if w == "" then return end
    local rec = GetIntentRecord(db, w)
    if rec then
        rec.pinned = class
        rec.lastSeen = time()
        rec.t = rec.lastSeen
    end
end

--- Record when a user picks a specific suggestion for a typo.
function YAS:RecordSelection(typo, correction, utilityGain, locale)
    if not self:IsEnabled() then return end
    local db = self:GetLocaleDB(locale)
    if not db then return end
    local c = Clean(correction)
    local t = Clean(typo)

    -- Don't learn from empty/punctuation-only corrections or blocked words.
    if c == "" or t == "" then return end

    -- Accepting a correction for this token is accident evidence.
    local rec = GetIntentRecord(db, t)
    if rec then
        rec.accepted = rec.accepted + 1
        rec.c = rec.c + 1
        rec.lastSeen = time()
        rec.t = rec.lastSeen
    end

    -- Personal error profile: bucket the edit that fixed this typo so the
    -- scorer can favour candidates matching the user's habitual slip class.
    if db.errProfile and t ~= c then
        local op, ab, bb = ClassifyEdit(t, c)
        db.errProfile.ops[op] = (db.errProfile.ops[op] or 0) + 1
        -- Confusion pair for substitutions (printable ASCII only).
        if ab and bb and ab >= 32 and ab <= 126 and bb >= 32 and bb <= 126 then
            local conf = db.errProfile.conf
            local key = string.char(ab) .. ">" .. string.char(bb)
            conf[key] = (conf[key] or 0) + 1
        end
    end

    local sc = YapperTable.Spellcheck
    if sc and sc.IsWordBlocked and sc:IsWordBlocked(c, locale, true) then return end

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
        Utils:Print("debug", string.format("YAS: RecordSelection typo='%s' corr='%s' gain=%.2f", typo, correction, gain))
    end

    local now = time()

    -- 1. Exact bias
    local key = t .. ":" .. c
    if not db.bias[key] then
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

    -- 2. Phonetic pattern bias: generalise the correction to other typos
    -- that produce the same phonetic hash. Shares the bias cap.
    if sc and sc.GetPhoneticHash then
        local ph = sc.GetPhoneticHash(t)
        if ph and ph ~= "" then
            local phKey = ph .. ":" .. c
            if not db.phBias[phKey] then
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

    -- Learned scorer: reinforce the features behind the accepted candidate.
    -- gain > 0 means YAS surfaced this pick — count it for self-eval and
    -- remember the pick so a later manual retype can flag it as overreach.
    local ph = sc and sc.GetPhoneticHash and sc.GetPhoneticHash(t)
    ModelUpdate(db, FeatureVector(db, t, c, c, nil, ph), 1)
    if gain > 0 then
        local m = GetModel(db)
        m.eval.promotedAccepted = (m.eval.promotedAccepted or 0) + 1
        self._lastPromoted = self._lastPromoted or {}
        self._lastPromoted[t] = c
        MaybeRegressModel(db)
    end
end

--- Record a correction that was made by the user manually retyping (implicit backtrack).
--- Determines the appropriate learning strength based on whether the correction was
--- already a known candidate and how phonetically/textually close it is to the typo.
function YAS:RecordImplicitCorrection(typo, correction, candidates, locale)
    if not self:IsEnabled() then return end
    local db = self:GetLocaleDB(locale)
    if not db then return end

    local c = Clean(correction)
    local sc = YapperTable.Spellcheck
    if sc and sc.IsWordBlocked and sc:IsWordBlocked(c, locale, true) then return end


    local t = Clean(typo)
    if t == "" or c == "" then return end

    -- A manual retype-correction is accident evidence for this token.
    local rec = GetIntentRecord(db, t)
    if rec then
        rec.corrected = rec.corrected + 1
        rec.c = rec.c + 1
        rec.lastSeen = time()
        rec.t = rec.lastSeen
    end

    -- Self-eval: if the user is manually re-correcting a token YAS previously
    -- surfaced, the promotion was overreach.  Enough of those regresses the
    -- learned multipliers toward the frozen defaults.
    local promoted = self._lastPromoted and self._lastPromoted[t]
    if promoted then
        if promoted ~= c then
            local m = GetModel(db)
            m.eval.retypeAfterPromoted = (m.eval.retypeAfterPromoted or 0) + 1
            MaybeRegressModel(db)
        end
        self._lastPromoted[t] = nil
    end

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
        -- Retyped a shown suggestion: treat as a full explicit selection
        -- (strongest signal).
        utilityGain = 0.5
    else
        -- Gate by similarity so unrelated retypes (e.g. user deleted the
        -- word and started a new sentence) don't pollute the bias table.
        local typoHash = sc and sc.GetPhoneticHash and sc.GetPhoneticHash(t) or ""
        local corrHash = sc and sc.GetPhoneticHash and sc.GetPhoneticHash(c) or ""

        if typoHash ~= "" and typoHash == corrHash then
            -- Same phonetic fingerprint despite different spelling: clear correction.
            utilityGain = 0.3
        else
            -- Fall back to similarity heuristics; a looser maxDist (3)
            -- captures more manual corrections than suggestion scoring.
            local dist = (sc and type(sc.EditDistance) == "function") and sc:EditDistance(t, c, 3) or 4
            
            if dist <= 1 then
                -- Single-char edit or transposition: very strong signal.
                utilityGain = 0.5
            elseif dist <= 2 then
                utilityGain = 0.35
            elseif dist <= 3 then
                utilityGain = 0.2
            else
                -- Not a close edit, check shared prefix/suffix as a last resort.
                local maxLen = math_max(#t, #c)
                local shared = 0
                for i = 1, math_min(#t, #c) do -- shared prefix
                    if t:sub(i, i) ~= c:sub(i, i) then break end
                    shared = shared + 1
                end
                for i = 0, math_min(#t, #c) - 1 do -- shared suffix
                    if i >= shared then -- stop before double-counting overlap
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
function YAS:RecordRejection(typo, candidates, locale)
    if not self:IsEnabled() then return end
    local db = self:GetLocaleDB(locale)
    if not db or not typo or type(candidates) ~= "table" then return end

    local t = Clean(typo)

    -- Paging past the popup is necessarily a seen-and-skipped event:
    -- waiver evidence, regardless of which class the token lands in.
    local rec = GetIntentRecord(db, t)
    if rec then
        rec.waived = rec.waived + 1
        rec.c = rec.c + 1
        rec.lastSeen = time()
        rec.t = rec.lastSeen
    end

    -- On an INTENTIONAL token, "More" means "stop suggesting" — don't
    -- punish the candidates for a word the user meant to write.
    if rec and ClassifyRecord(rec) == "INTENTIONAL" then
        self._exposed = self._exposed or {}
        self._exposed[t] = nil
        return
    end

    local now = time()
    local wrote = false

    for _, candObj in ipairs(candidates) do
        local word = type(candObj) == "table" and (candObj.word or candObj.value) or candObj
        if word then
            local key = t .. ":" .. Clean(word)
            if not db.negBias[key] then
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
            wrote = true
        end
    end
    -- negBias feeds GetBonus; invalidate cached suggestion scores on write.
    if wrote then db._rev = (db._rev or 0) + 1 end

    -- Learned scorer: the user paged past these candidates — dampen the
    -- features that surfaced them.  Capped so a long page can't stall a frame.
    local sc = YapperTable.Spellcheck
    local ph = sc and sc.GetPhoneticHash and sc.GetPhoneticHash(t)
    local n = 0
    for _, candObj in ipairs(candidates) do
        if n >= 5 then break end
        local word = type(candObj) == "table" and (candObj.word or candObj.value) or candObj
        if word then
            local cw = Clean(word)
            if cw ~= "" then
                ModelUpdate(db, FeatureVector(db, t, cw, cw, nil, ph), -1)
                n = n + 1
            end
        end
    end
end

--- Record high-repetition typos for auto-learning
function YAS:RecordIgnored(word, locale)
    if not self:IsEnabled() then return end
    if not locale then
        local sc = YapperTable.Spellcheck
        locale = sc and sc.GetLocale and sc:GetLocale() or nil
    end
    local db = self:GetLocaleDB(locale)
    if not db or type(word) ~= "string" then return end

    -- Auto keys live in the same normalised domain as freq/bias keys.
    local w = Clean(word)
    if w == "" then return end
    local sc = YapperTable.Spellcheck
    if sc and sc.IsWordBlocked and sc:IsWordBlocked(w, locale, true) then return end

    if not self:IsSaneWord(w, locale) then return end
    local now = time()

    -- Intent bookkeeping: this word survived to send unchanged.
    local rec = GetIntentRecord(db, w)
    if rec then
        rec.sentUnchanged = rec.sentUnchanged + 1
        rec.c = rec.c + 1
        rec.lastSeen = now
        rec.t = now

        -- Was the popup shown recently for this token?  Enough dwell time
        -- between appearance and send is a deliberate waiver; a fast send
        -- means the user plausibly never saw it (no credit either way).
        local exp = self._exposed and self._exposed[w]
        if exp then
            self._exposed[w] = nil -- exposure credit is consumed by this send
            local dwell = RtNow() - exp.t
            if dwell <= INTENT_EXPOSURE_TTL and dwell >= INTENT_DWELL_MIN then
                rec.waived = rec.waived + 1
            end
        end
    end

    if not db.auto[w] then
        db.auto[w] = { c = 1, t = now }
        db.autoCount = (db.autoCount or 0) + 1
        if db.autoCount >= self:GetAutoCap() then
            self:Prune("auto", self:GetAutoCap(), locale)
            local count = 0
            for _ in pairs(db.auto) do count = count + 1 end
            db.autoCount = count
        end
    else
        local entry = db.auto[w]
        entry.c = entry.c + 1
        entry.t = now
    end

    -- Auto-promotion requires INTENTIONAL-class evidence: consistent
    -- unchanged sends with zero corrections.  A user who keeps sending the
    -- same token without looking isn't teaching us vocabulary; one who
    -- once accepted a correction for it typed an accident.
    if db.auto[w].c >= self:GetAutoThreshold()
        and ClassifyRecord(rec) == "INTENTIONAL" then
        -- Auto-promote to user dictionary
        local Spellcheck = YapperTable.Spellcheck
        if Spellcheck and Spellcheck.AddUserWord then
            local loc = locale or Spellcheck:GetLocale()
            Spellcheck:AddUserWord(loc, word)
            db.auto[w] = nil -- Reset now that it's in the dict
            db.autoCount = math_max(0, (db.autoCount or 1) - 1)
            if rec then rec.pinned = "INTENTIONAL" end
            Utils:VerbosePrint("info",
                "YAS: Learned new word '" .. word .. "' (" .. (loc or "Shared") .. ") after persistent usage.")
            -- Notify external addons about the auto-learned word.
            if YapperTable.API then
                YapperTable.API:Fire("YAS_WORD_LEARNED", word, loc)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Scoring Logic
-- ---------------------------------------------------------------------------

--- Return the combined score bonus for a candidate using a pre-computed
--- phonetic hash.  `prevWord` (normalised) is the token before the typo —
--- feeds the bigram context feature.
function YAS:GetBonus(cand, typo, typoPhHash, locale, prevWord)
    if not self:IsEnabled() then return 0 end
    local db = self:GetLocaleDB(locale, true)
    if not db then return 0 end
    local c = Clean(cand)
    local t = Clean(typo)
    local f = FeatureVector(db, t, c, cand, prevWord, typoPhHash)

    -- Frozen WEIGHTS scaled by the learned per-locale multipliers.  When the
    -- model table is absent the multipliers are all 1.0 and this reduces to
    -- the original fixed-weight behaviour.
    local m = (db.model and db.model.m) or DEFAULT_MODEL_M

    return WEIGHTS.freqBonus * f.freq * m.freq
         + WEIGHTS.biasBonus * f.bias * m.bias
         + WEIGHTS.phBonus * f.ph * m.ph
         + WEIGHTS.negBias * f.neg * m.neg
         + WEIGHTS.bigramBonus * f.bigram * m.bigram
         + WEIGHTS.errAffinity * f.err * m.err
end

--- Returns a list of candidate words that have been learned as corrections for the given typo.
function YAS:GetBiasTargets(typo, locale)
    if not self:IsEnabled() then return nil end
    local db = self:GetLocaleDB(locale, true)
    if not db or not db.bias then return nil end
    local t = Clean(typo)
    if t == "" then return nil end

    local targets = {}
    -- Scan for "typo:*" keys; the bias table is capped at 500 so a full
    -- scan is cheap.
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

    -- Phonetic bias targets too (same typo sound, different spelling).
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
-- Autocorrect scaffold (Phase 4) — decision machinery, no application path.
-- Nothing here mutates user text.  Tiers/classification/log are produced so
-- the future autocorrect feature plugs into machinery that's already live
-- and observable via shadow logging.
-- ---------------------------------------------------------------------------

local AUTOCORR_LOG_CAP = 50   -- Bounded ring of shadow decisions
local AUTOCORR_UNDO_CAP = 50  -- Session ring for revertable applications
local TIER_AUTO_MIN     = 0.8 -- Confidence threshold for the (unused) AUTO tier
local TIER_SUGGEST_MIN  = 0.4

--- Is the AUTO tier currently suspended by self-eval evidence?
--- True once promoted picks have been re-corrected often enough.
local function AutoTierSuspended(db)
    local m = db and db.model
    local ev = m and m.eval
    if not ev then return false end
    local total = (ev.promotedAccepted or 0) + (ev.retypeAfterPromoted or 0)
    if total < EVAL_MIN_SAMPLES then return false end
    return (ev.retypeAfterPromoted or 0) / total > EVAL_DAMPEN_RATIO
end

--- Classify what a suggestion means for a future autocorrect pass.
--- Pure read: returns { suggestion, confidence, tier, vetoReasons }.
---   tier: "AUTO" | "SUGGEST" | "OFFER" | "SUPPRESS"
---   vetoReasons: { intentional, waiver, recentRecorrect, engineVeto }
--- INTENTIONAL/WAIVER intent is a hard veto forever; engine AutocorrectVeto
--- and MaxConfidence are respected; self-eval suspends the AUTO tier.
function YAS:ClassifySuggestion(typo, candidate, locale, prevWord)
    if not self:IsEnabled() then return nil end
    if type(typo) ~= "string" or type(candidate) ~= "string" then return nil end
    local db = self:GetLocaleDB(locale, true)
    if not db then return nil end

    local t = Clean(typo)
    local c = Clean(candidate)
    if t == "" or c == "" then return nil end

    local veto = {
        intentional = false,
        waiver = false,
        recentRecorrect = false,
        engineVeto = false,
    }

    -- Intent vetoes (Phase 1 machinery is what autocorrect stands on).
    local rec = db.intent and db.intent[t]
    if rec then
        local cls = ClassifyRecord(rec)
        if cls == "INTENTIONAL" then
            veto.intentional = true
        elseif cls == "WAIVER" then
            veto.waiver = true
        end
        if (rec.corrected or 0) > 0 then
            veto.recentRecorrect = true
        end
    end

    -- Engine contract: language-specific veto + confidence ceiling.
    local maxConf = 1.0
    local sc = YapperTable.Spellcheck
    local engine = sc and sc._EngineForLocale
        and sc:_EngineForLocale(locale or sc:GetLocale())
    if not engine and sc and sc.GetActiveEngine then
        engine = sc:GetActiveEngine()
    end
    local ac = engine and engine.Autocorrect
    if type(ac) == "table" then
        if ac.AutocorrectVeto
            and sc:_SafeEngineCall(ac, "AutocorrectVeto", false, t, c) == true then
            veto.engineVeto = true
        end
        if type(ac.MaxConfidence) == "number" then
            maxConf = math_min(maxConf, ac.MaxConfidence)
        end
    end

    -- Confidence: utility-weighted evidence, bounded [0,1].
    local f = FeatureVector(db, t, c, c, prevWord, nil)
    local conf = math_min(f.bias * 0.2, 0.60)   -- learned utility dominates
               + math_min(f.freq * 0.05, 0.15)
               + math_min(f.ph * 0.10, 0.15)
               + math_min(f.bigram * 0.04, 0.10)
    if veto.recentRecorrect then
        conf = conf * 0.5   -- a re-corrected pair earns half trust
    end
    conf = math_min(conf, maxConf)

    local tier
    if veto.intentional or veto.waiver then
        tier = "SUPPRESS"
    elseif conf >= TIER_AUTO_MIN and not veto.engineVeto
        and not AutoTierSuspended(db) then
        tier = "AUTO"
    elseif conf >= TIER_SUGGEST_MIN then
        tier = "SUGGEST"
    else
        tier = "OFFER"
    end

    return {
        suggestion = candidate,
        confidence = conf,
        tier = tier,
        vetoReasons = veto,
    }
end

--- Shadow-mode entry point: classify a shown suggestion and append the
--- decision to the bounded autocorrLog ring.  Opt-in via config
--- (YASAutocorrectShadow); lets us observe would-be autocorrections before
--- any silent text mutation exists.  Returns the decision or nil.
function YAS:ShadowClassify(typo, candidate, locale, prevWord)
    if not self:IsEnabled() then return nil end
    local cfg = YapperTable.Config and YapperTable.Config.Spellcheck
    if not (cfg and cfg.YASAutocorrectShadow) then return nil end
    local d = self:ClassifySuggestion(typo, candidate, locale, prevWord)
    if not d then return nil end

    local db = self:GetLocaleDB(locale)
    if not db then return d end
    local log = db.autocorrLog
    if type(log) ~= "table" then
        log = {}
        db.autocorrLog = log
    end
    log[#log + 1] = {
        t = Clean(typo),
        s = d.suggestion,
        tier = d.tier,
        conf = d.confidence,
        ts = time(),
    }
    while #log > AUTOCORR_LOG_CAP do
        table.remove(log, 1)
    end

    if IsDebugEnabled() then
        Utils:Print("debug", string.format(
            "YAS shadow: '%s' -> '%s' tier=%s conf=%.2f",
            typo, d.suggestion, d.tier, d.confidence))
    end
    return d
end

--- Push a reversion record for a (future) applied autocorrection.
--- Session ring — undo data is worthless across relogs anyway.
function YAS:PushUndo(entry)
    if not self:IsEnabled() then return end
    if type(entry) ~= "table" or type(entry.original) ~= "string"
        or type(entry.applied) ~= "string" then
        return
    end
    entry.time = entry.time or time()
    local u = self._undoRing
    if not u then
        u = {}
        self._undoRing = u
    end
    u[#u + 1] = entry
    while #u > AUTOCORR_UNDO_CAP do
        table.remove(u, 1)
    end
end

--- Pop the most recent reversion record (LIFO).
function YAS:PopUndo()
    if not self:IsEnabled() then return nil end
    local u = self._undoRing
    if not u or #u == 0 then return nil end
    local e = u[#u]
    u[#u] = nil
    return e
end

-- ---------------------------------------------------------------------------
-- Maintenance
-- ---------------------------------------------------------------------------

--- Systematic pruning of a learning table
function YAS:Prune(tableName, limit, locale)
    local db = self:GetLocaleDB(locale)
    if not db then return end
    local tbl = db[tableName]
    if not tbl then return end

    local keys = {}
    for k, e in pairs(tbl) do
        -- Explicitly pinned intent records are never evicted.
        if not (tableName == "intent" and type(e) == "table" and e.pinned) then
            table_insert(keys, k)
        end
    end
    if #keys < limit then return end

    -- Sort by relevance: score = (count * utility) / (daysOld + 1).
    local now = time()
    table_sort(keys, function(a, b)
        local ea = tbl[a]
        local eb = tbl[b]

        local ua = ea.u or 1
        local ub = eb.u or 1

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
        if tableName == "freq" and db.total then
            db.total = math_max(0, db.total - 1)
        end
    end

    if tableName == "freq" then
        RebuildFreqSorted(db)
    end
end

--- Prune the nested bigram transition table to `limit` total entries,
--- evicting the lowest-scored transitions and dropping empty buckets.
function YAS:PruneBigrams(limit, locale)
    local db = self:GetLocaleDB(locale)
    if not db or type(db.bigram) ~= "table" then return end

    local entries = {}
    for prev, bucket in pairs(db.bigram) do
        if type(bucket) == "table" then
            for nxt, e in pairs(bucket) do
                entries[#entries + 1] = { prev = prev, nxt = nxt, e = e }
            end
        end
    end
    if #entries < limit then return end

    local now = time()
    table_sort(entries, function(a, b)
        local sa = (a.e.c or 0) / (math_max(0, (now - (a.e.t or 0)) / 86400) + 1)
        local sb = (b.e.c or 0) / (math_max(0, (now - (b.e.t or 0)) / 86400) + 1)
        return sa > sb
    end)

    local targetSize = math_floor(limit * 0.9)
    for i = targetSize + 1, #entries do
        local it = entries[i]
        local bucket = db.bigram[it.prev]
        if bucket then
            bucket[it.nxt] = nil
            if next(bucket) == nil then db.bigram[it.prev] = nil end
        end
    end
    db.bigramCount = targetSize
end

-- ---------------------------------------------------------------------------
-- Background consolidation
--
-- Long-horizon bookkeeping (count decay, stale-intent eviction, cap sweeps)
-- spread over timer ticks so nothing runs on the input path.  The job is a
-- cursor over per-phase key snapshots; each _ConsolidationStep processes at
-- most CONSOLIDATION_CHUNK entries and returns true while work remains.
-- Tests can drive _ConsolidationStep directly for determinism.
-- ---------------------------------------------------------------------------

local CONSOLIDATION_PHASES = { "decay", "intent", "bigram", "conf" }

--- Begin a background consolidation pass for a locale.  Returns true if a
--- job was started (or is already running), false when disabled/no data.
function YAS:StartConsolidation(locale)
    if not self:IsEnabled() then return false end
    if self._consolidating then return false end
    local db = self:GetLocaleDB(locale, true)
    if not db then return false end

    self._consolidating = {
        db = db, phaseIdx = 1, keys = nil, i = 1,
    }
    -- Schedule under WoW's timer; in headless test runs the caller drives
    -- _ConsolidationStep directly.
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        local function tick()
            if self._consolidating then
                if not self:_ConsolidationStep() then
                    self._consolidating = nil
                    return
                end
                C_Timer.After(0, tick)
            end
        end
        C_Timer.After(0, tick)
    end
    return true
end

--- Advance the running consolidation job by one chunk.
---@return boolean more true while work remains.
function YAS:_ConsolidationStep()
    local job = self._consolidating
    if not job then return false end
    local db = job.db

    if not job.keys then
        job.keys = {}
        job.i = 1
        local phase = CONSOLIDATION_PHASES[job.phaseIdx]
        if phase == "decay" then
            for _, tbl in ipairs({ "freq", "auto", "bias", "phBias", "negBias" }) do
                for k in pairs(db[tbl] or {}) do
                    job.keys[#job.keys + 1] = tbl .. "\0" .. k
                end
            end
        elseif phase == "intent" then
            for k in pairs(db.intent or {}) do job.keys[#job.keys + 1] = k end
        elseif phase == "bigram" then
            -- One shot: the cap prune is already sorted work, no cursor.
            self:PruneBigrams(self:GetBigramCap(), db._locale)
            job.keys = {}
        elseif phase == "conf" then
            for k in pairs((db.errProfile or {}).conf or {}) do
                job.keys[#job.keys + 1] = k
            end
        end
    end

    local now = time()
    local phase = CONSOLIDATION_PHASES[job.phaseIdx]
    local n = 0
    while job.i <= #job.keys and n < CONSOLIDATION_CHUNK do
        local k = job.keys[job.i]
        job.i = job.i + 1
        n = n + 1

        if phase == "decay" then
            -- "tbl\0key" — split on the first NUL.
            local sep = k:find("\0", 1, true)
            local tbl, key = k:sub(1, sep - 1), k:sub(sep + 1)
            local e = db[tbl] and db[tbl][key]
            if e and type(e) == "table" and (now - (e.t or 0)) > DECAY_AGE then
                local newC = math_floor((e.c or 1) * 0.5)
                if newC < 1 then
                    db[tbl][key] = nil
                    if tbl == "freq" then
                        db.total = math_max(0, (db.total or 1) - 1)
                        db.freqSortedDirty = true
                    elseif tbl == "auto" then
                        db.autoCount = math_max(0, (db.autoCount or 1) - 1)
                    elseif tbl == "bias" then
                        db.biasCount = math_max(0, (db.biasCount or 1) - 1)
                    elseif tbl == "phBias" then
                        db.phBiasCount = math_max(0, (db.phBiasCount or 1) - 1)
                    elseif tbl == "negBias" then
                        db.negBiasCount = math_max(0, (db.negBiasCount or 1) - 1)
                    end
                    db._rev = (db._rev or 0) + 1
                else
                    e.c = newC
                    db._rev = (db._rev or 0) + 1
                end
            end
        elseif phase == "intent" then
            local e = db.intent and db.intent[k]
            if e and not e.pinned and ClassifyRecord(e) == nil
                and (now - (e.lastSeen or e.t or 0)) > INTENT_STALE_AGE then
                db.intent[k] = nil
                db.intentCount = math_max(0, (db.intentCount or 1) - 1)
            end
        elseif phase == "conf" then
            -- Confusion pairs: keep the strongest CONF_CAP entries.
            local conf = db.errProfile and db.errProfile.conf
            if conf then
                local cnt = 0
                for _ in pairs(conf) do cnt = cnt + 1 end
                if cnt > CONF_CAP then
                    local ranked = {}
                    for ck in pairs(conf) do ranked[#ranked + 1] = ck end
                    table_sort(ranked, function(a, b) return conf[a] > conf[b] end)
                    for i = CONF_CAP + 1, #ranked do conf[ranked[i]] = nil end
                    break -- table rewritten; stop this phase
                end
                break -- under cap; nothing to do for remaining keys
            end
        end
    end

    if job.i <= #job.keys then return true end

    job.phaseIdx = job.phaseIdx + 1
    job.keys = nil
    return job.phaseIdx <= #CONSOLIDATION_PHASES
end

--- Clears learned data, either globally or for a specific locale.
---@param locale string|nil If provided, only clears that locale's data. Otherwise clears all.
function YAS:Reset(locale)
    if not locale then
        _G.YapperDB.SpellcheckLearned = nil
    elseif _G.YapperDB.SpellcheckLearned then
        _G.YapperDB.SpellcheckLearned[locale] = nil
    end
    -- Session-only learning state dies with the data it describes.
    self._exposed = nil
    self._lastPromoted = nil
    self._undoRing = nil
    self:Init()
end

-- ---------------------------------------------------------------------------
-- UI Helpers
-- ---------------------------------------------------------------------------

--- Returns a summary of learned data for a locale (counts, caps, top words).
---@param locale string|nil The locale key.
---@return table|nil summary Data table with freq, bias, auto, total, cap, threshold fields.
function YAS:GetDataSummary(locale)
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
        freq        = freqList,
        bias        = biasList,
        phBias      = phList,
        negBias     = negList,
        auto        = autoList,
        total       = db.total,
        intentCount = db.intentCount or 0,
        bigramCount = db.bigramCount or 0,
        cap         = self:GetFreqCap(),
        threshold   = self:GetAutoThreshold(),
    }
end

--- Export current learned data for a locale as a text block.
function YAS:Export(locale)
    local db = self:GetLocaleDB(locale)
    if not db then return "No data for " .. tostring(locale) end

    local out = {}
    table_insert(out, "Yapper YAS Export - " .. tostring(locale))
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

--- Clears a specific entry from a learning table by type and key.
---@param usageType string One of: "freq", "bias", "auto", "phBias", "negBias", "intent".
---@param key string The entry key to remove.
---@param locale string|nil The locale key.
function YAS:ClearSpecificUsage(usageType, key, locale)
    local db = self:GetLocaleDB(locale, true)
    if not db then return end
    local function dec(c) return math_max(0, (c or 1) - 1) end
    if usageType == "freq" and db.freq[key] then
        db.freq[key] = nil
        db.total = dec(db.total)
        db.freqSortedDirty = true
        db._rev = (db._rev or 0) + 1
    elseif usageType == "bias" and db.bias[key] then
        db.bias[key] = nil
        db.biasCount = dec(db.biasCount)
        db._rev = (db._rev or 0) + 1
    elseif usageType == "auto" and db.auto[key] then
        db.auto[key] = nil
        db.autoCount = dec(db.autoCount)
    elseif usageType == "phBias" and db.phBias[key] then
        db.phBias[key] = nil
        db.phBiasCount = dec(db.phBiasCount)
        db._rev = (db._rev or 0) + 1
    elseif usageType == "negBias" and db.negBias[key] then
        db.negBias[key] = nil
        db.negBiasCount = dec(db.negBiasCount)
        db._rev = (db._rev or 0) + 1
    elseif usageType == "intent" and db.intent and db.intent[key] then
        db.intent[key] = nil
        db.intentCount = dec(db.intentCount)
    end
end
