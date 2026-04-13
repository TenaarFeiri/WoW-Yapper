--[[
    YALLM: Yapper Adaptive Learning Language Model
    Personalized ranking and vocabulary tracking for the spellcheck engine.
]]

local YapperName, YapperTable = ...
local YALLM = {}
YapperTable.Spellcheck.YALLM = YALLM -- Hook into internal table
_G.YALLM = YALLM -- Global access for simplicity

-- Tuning Constants
local FREQ_CAP       = 2000     -- Max unique words to track
local AUTO_THRESHOLD = 10       -- Times sent before auto-added to dict
local MAX_BIAS_PAIRS = 500      -- Max Typo -> Selection pairs to track
local WEIGHTS = {
    freqBonus = -2.5,   -- High usage = lower score (better)
    biasBonus = -5.0,   -- Past selection = significantly lower score
}

-- ---------------------------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------------------------

function YALLM:Init()
    if not _G.YapperDB then return end
    if not _G.YapperDB.SpellcheckLearned then
        _G.YapperDB.SpellcheckLearned = {
            freq = {},   -- word -> count
            bias = {},   -- typo:correction -> count
            auto = {},   -- word -> "sent anyway" count
            total = 0,   -- total unique words tracked
        }
    end
    self.db = _G.YapperDB.SpellcheckLearned
end

-- ---------------------------------------------------------------------------
-- Tracking Logic
-- ---------------------------------------------------------------------------

--- Standardise word for tracking
local function Clean(s) return s:lower():gsub("[%p%s]", "") end

function YALLM:IsSaneWord(word)
    local w = Clean(word)
    if #w < 3 then return false end

    -- 1. Linguistic Cluster Check (7+ consecutive consonants)
    -- Protects valid words like "catchphrase" while blocking "sxcvbhm"
    if w:match("[^aeiouy]{7,}") then 
        return false 
    end

    -- 2. Keyboard Smash Check (3+ identical consecutive characters)
    -- Prevents learning "loool", "ahhh", "www"
    if w:match("(.)%1%1") then 
        return false 
    end

    -- 3. N-Gram Anchor (Sanity Verification)
    -- Validates that the word shares at least ONE bigram with the English language.
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
    
    -- Fast-split into words (alphanumeric only)
    for word in text:gmatch("[%w']+") do
        if self:IsSaneWord(word) then
            local w = Clean(word)
            if not self.db.freq[w] then
                -- Handle Capacity (LFU Eviction)
                if self.db.total >= FREQ_CAP then
                    self:EvictLeastUsed()
                end
                self.db.freq[w] = 0
                self.db.total = self.db.total + 1
            end
            self.db.freq[w] = self.db.freq[w] + 1
        end
    end
end

--- Record when a user picks a specific suggestion for a typo
function YALLM:RecordSelection(typo, correction)
    if not self.db then return end
    local key = Clean(typo) .. ":" .. Clean(correction)
    self.db.bias[key] = (self.db.bias[key] or 0) + 1
    
    -- Cap the bias table size
    local count = 0
    for _ in pairs(self.db.bias) do count = count + 1 end
    if count > MAX_BIAS_PAIRS then
        -- Simple random prune for bias (less critical than freq)
        local k = next(self.db.bias)
        if k then self.db.bias[k] = nil end
    end
end

--- Record when a user sends a word that is currently flagged as a typo
function YALLM:RecordIgnored(word)
    if not self.db then return end
    if not self:IsSaneWord(word) then return end
    
    local w = Clean(word)
    self.db.auto[w] = (self.db.auto[w] or 0) + 1
    
    if self.db.auto[w] >= AUTO_THRESHOLD then
        -- Auto-promote to user dictionary
        local Spellcheck = YapperTable.Spellcheck
        if Spellcheck and Spellcheck.AddWord then
            Spellcheck:AddWord(word)
            self.db.auto[w] = nil -- Reset now that it's in the dict
            if YapperTable.Utils then
                YapperTable.Utils:Print("YALLM: Learned new word '" .. word .. "' after persistent usage.")
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Scoring Logic
-- ---------------------------------------------------------------------------

--- Return the combined score bonus for a candidate
function YALLM:GetBonus(cand, typo)
    if not self.db then return 0 end
    local c = Clean(cand)
    local t = Clean(typo)
    local bonus = 0

    -- 1. Frequency Bonus (Common Word)
    local fCount = self.db.freq[c] or 0
    if fCount > 5 then
        bonus = bonus + WEIGHTS.freqBonus
    end

    -- 2. Bias Bonus (Past Correction)
    local key = t .. ":" .. c
    local bCount = self.db.bias[key] or 0
    if bCount > 0 then
        bonus = bonus + (WEIGHTS.biasBonus * math.min(bCount, 5))
    end

    return bonus
end

-- ---------------------------------------------------------------------------
-- Maintenance
-- ---------------------------------------------------------------------------

function YALLM:EvictLeastUsed()
    local minKey, minVal = nil, 1e9
    -- Scan 50 random entries to find a candidate for eviction (avoid full scan for perf)
    local count = 0
    for k, v in pairs(self.db.freq) do
        if v < minVal then
            minVal = v
            minKey = k
        end
        count = count + 1
        if count > 50 then break end
    end
    
    if minKey then
        -- Telemetry: track if we are forced to evict a high-frequency word
        if minVal > 2 and _G.YALLM_STATS then
            _G.YALLM_STATS.highFreqEvictions = (_G.YALLM_STATS.highFreqEvictions or 0) + 1
        end
        self.db.freq[minKey] = nil
        self.db.total = self.db.total - 1
        if _G.YALLM_STATS then
            _G.YALLM_STATS.totalEvictions = (_G.YALLM_STATS.totalEvictions or 0) + 1
        end
    end
end

function YALLM:Reset()
    _G.YapperDB.SpellcheckLearned = nil
    self:Init()
end
