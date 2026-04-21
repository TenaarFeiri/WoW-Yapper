-- Yapper_Dict_deDE/Engine.lua
-- German language engine for the Yapper Spellcheck system.
--
-- Registers via YapperAPI:RegisterLanguageEngine("de", engine).
-- This must load before Dict_deDE.lua (ensured by TOC order).

local string_gsub  = string.gsub
local string_lower = string.lower
local string_upper = string.upper
local string_sub   = string.sub

-- ---------------------------------------------------------------------------
-- Variant rules: Exact equivalence mappings.
-- Used by the scoring engine to boost candidates that use alternative but valid spellings.
-- ---------------------------------------------------------------------------
local VARIANT_RULES = {
    { "ss", "ß" }, { "ß", "ss" },
    { "ae", "ä" }, { "ä", "ae" },
    { "oe", "ö" }, { "ö", "oe" },
    { "ue", "ü" }, { "ü", "ue" },
}

-- ---------------------------------------------------------------------------
-- Score Weights
-- German overrides the default lenDiff penalty because compounding often causes length disparities.
-- ---------------------------------------------------------------------------
local SCORE_WEIGHTS = {
    lenDiff       = 1.5, -- Reduced penalty for German compounds
    longerPenalty = 2.0,
    prefix        = 1.5,
    letterBag     = 1.0,
    bigram        = 1.5,
    kbProximity   = 1.0, 
    firstCharBias = 1.5, 
    vowelBonus    = 2.5, 
}

-- ---------------------------------------------------------------------------
-- Keyboard Layouts (QWERTZ)
-- German relies exclusively on the QWERTZ layout structure.
-- ---------------------------------------------------------------------------
local KB_LAYOUTS = {
    QWERTZ = {
        q = { 0,    0 }, w = { 1,    0 }, e = { 2,    0 }, r = { 3,    0 },
        t = { 4,    0 }, z = { 5,    0 }, u = { 6,    0 }, i = { 7,    0 },
        o = { 8,    0 }, p = { 9,    0 },
        a = { 0.25, 1 }, s = { 1.25, 1 }, d = { 2.25, 1 }, f = { 3.25, 1 },
        g = { 4.25, 1 }, h = { 5.25, 1 }, j = { 6.25, 1 }, k = { 7.25, 1 },
        l = { 8.25, 1 },
        y = { 0.75, 2 }, x = { 1.75, 2 }, c = { 2.75, 2 }, v = { 3.75, 2 },
        b = { 4.75, 2 }, n = { 5.75, 2 }, m = { 6.75, 2 },
    }
}

-- ---------------------------------------------------------------------------
-- NormaliseVowels
-- Strips vowels (replaced with '*') for vowel-neutral similarity comparisons.
-- Included German umlauts.
-- ---------------------------------------------------------------------------
local function NormaliseVowels(word)
    if type(word) ~= "string" then return "" end
    return string_gsub(string_lower(word), "[aeiouyäöü]", "*")
end

-- ---------------------------------------------------------------------------
-- GetPhoneticHash  (MUST match tools/phonetics_de.py exactly)
-- Maps German spelling to a standardized phonetic string.
-- ---------------------------------------------------------------------------
local function GetPhoneticHash(word)
    local hash = string_upper(word)
    
    -- Standardize Umlauts
    hash = string_gsub(hash, "Ä", "A")
    hash = string_gsub(hash, "Ö", "O")
    hash = string_gsub(hash, "Ü", "U")
    hash = string_gsub(hash, "ß", "SS")
    
    -- Strip non-alphabetic characters
    hash = string_gsub(hash, "[^%a]", "")
    if hash == "" then return "" end

    -- Consonant Groupings
    hash = string_gsub(hash, "SCH", "S")
    hash = string_gsub(hash, "CH",  "X")
    hash = string_gsub(hash, "PH",  "F")
    hash = string_gsub(hash, "V",   "F")
    hash = string_gsub(hash, "W",   "V")
    hash = string_gsub(hash, "Z",   "S")
    hash = string_gsub(hash, "QU",  "KV")
    hash = string_gsub(hash, "DT",  "T")
    hash = string_gsub(hash, "TH",  "T")

    -- Strip duplicate adjacent letters
    hash = string_gsub(hash, "(%a)%1", "%1")
    
    if hash == "" then return "" end

    -- Keep first letter; strip remaining vowels
    local firstChar = string_sub(hash, 1, 1)
    local rest      = string_sub(hash, 2)
    rest = string_gsub(rest, "[AEIOUY]", "")

    return firstChar .. rest
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------
if not _G.YapperAPI then return end

local ok = YapperAPI:RegisterLanguageEngine("de", {
    GetPhoneticHash = GetPhoneticHash,
    NormaliseVowels = NormaliseVowels,
    HasVariantRules = true,
    VariantRules    = VARIANT_RULES,
    KBLayouts       = KB_LAYOUTS,
    ScoreWeights    = SCORE_WEIGHTS,
})

if not ok and DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cffff6666Yapper_Dict_deDE:|r Failed to register German language engine."
    )
end
