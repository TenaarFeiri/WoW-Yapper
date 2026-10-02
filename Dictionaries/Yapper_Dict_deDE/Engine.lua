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
-- NormaliseWord / NormaliseVowels / tokenisation
-- Dictionary words are indexed lowercased; umlauts are kept as-is.  Word
-- bytes include bytes >= 128 so UTF-8 umlauts (ä ö ü) and ß stay inside a
-- word token.
-- ---------------------------------------------------------------------------
local function NormaliseWord(word)
    if type(word) ~= "string" then return "" end
    return string_lower(word)
end

local function NormaliseVowels(word)
    if type(word) ~= "string" then return "" end
    return string_gsub(string_lower(word), "[aeiouyäöü]", "*")
end

local WORD_BYTES = {}
local WORD_START_BYTES = {}
for b = 65, 90 do
    WORD_BYTES[b] = true
    WORD_START_BYTES[b] = true
end
for b = 97, 122 do
    WORD_BYTES[b] = true
    WORD_START_BYTES[b] = true
end
for b = 128, 255 do
    WORD_BYTES[b] = true       -- UTF-8 lead/continuation bytes (umlauts, ß)
end
WORD_BYTES[39] = true          -- apostrophe (names, colloquial elisions)

-- ---------------------------------------------------------------------------
-- HashWord + BlockedHashes (mandatory security data)
-- 32-bit DJB2 over UTF-8 bytes — identical algorithm to
-- tools/generate_blocklist.py (encode-then-hash so umlauts match).
-- The seed list is a compact set of common German profanity/slurs; extend by
-- regenerating with tools/generate_blocklist.py and a German word list.
-- ---------------------------------------------------------------------------
local string_byte = string.byte
local function HashWord(word)
    local hash = 5381
    for i = 1, #word do
        hash = ((hash * 33) + string_byte(word, i)) % 4294967296
    end
    return hash
end

local BLOCKED_HASHES = {
    [120825287] = true, [143288082] = true, [143288086] = true, [143672688] = true,
    [215723726] = true, [253411990] = true, [259001014] = true, [259235629] = true,
    [261820231] = true, [264643108] = true, [266548673] = true, [267529925] = true,
    [268225866] = true, [268346843] = true, [268938421] = true, [270877897] = true,
    [274667632] = true, [278210365] = true, [285033411] = true, [300966619] = true,
    [324970599] = true, [330453146] = true, [348813961] = true, [349036119] = true,
    [349036123] = true, [446231518] = true, [474079654] = true, [474097369] = true,
    [505614717] = true, [515599122] = true, [587496623] = true, [591007563] = true,
    [622397352] = true, [622397367] = true, [703160047] = true, [744704779] = true,
    [893430030] = true, [1110756869] = true, [1122981937] = true, [1460508594] = true,
    [1543709244] = true, [1543797816] = true, [1551716562] = true, [1657975082] = true,
    [1671428349] = true, [1714523622] = true, [1833193213] = true, [2043401357] = true,
    [2043695199] = true, [2090256898] = true, [2090342329] = true, [2090536439] = true,
    [2090760586] = true, [2112534479] = true, [2175566280] = true, [2259337975] = true,
    [2259340659] = true, [2259975971] = true, [2419697801] = true, [2485770611] = true,
    [2640229838] = true, [2705762084] = true, [2780851869] = true, [2788489133] = true,
    [2818156982] = true, [2825009670] = true, [3359243542] = true, [3359243546] = true,
    [3440419286] = true, [3447929820] = true, [3871504753] = true, [3962006400] = true,
    [3989015391] = true, [4017627426] = true, [4090958319] = true, [4119011568] = true,
    [4170377705] = true, [4252065781] = true, [4252065785] = true, [4259808571] = true,
    [4289635319] = true,
}

-- ---------------------------------------------------------------------------
-- GetPhoneticHash  (MUST match tools/phonetics_de.py exactly)
-- Maps German spelling to a standardized phonetic string.
-- ---------------------------------------------------------------------------
local function GetPhoneticHash(word)
    local hash = string_upper(word)

    -- Standardize Umlauts. string.upper is ASCII-only in Lua 5.1, so the
    -- lowercase UTF-8 forms (ä ö ü) must be mapped explicitly or [^%a]
    -- would strip them — tools/phonetics_de.py's str.upper() handles both.
    hash = string_gsub(hash, "Ä", "A"); hash = string_gsub(hash, "ä", "A")
    hash = string_gsub(hash, "Ö", "O"); hash = string_gsub(hash, "ö", "O")
    hash = string_gsub(hash, "Ü", "U"); hash = string_gsub(hash, "ü", "U")
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

    -- Strip duplicate adjacent letters. Must collapse the WHOLE run to match
    -- tools/phonetics_de.py's re.sub(r'([A-Z])\1+', ...). Lua 5.1 cannot
    -- quantify a %n backreference, so repeat single-pair collapses until
    -- stable (bounded: each pass halves the longest run).
    repeat
        local n
        hash, n = string_gsub(hash, "(%a)%1", "%1")
    until n == 0
    
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
    -- ===== Required contract fields =======================================
    NormaliseWord   = NormaliseWord,
    NormaliseVowels = NormaliseVowels,
    WordBytes       = WORD_BYTES,
    WordStartBytes  = WORD_START_BYTES,
    GetPhoneticHash = GetPhoneticHash,
    HashWord        = HashWord,
    BlockedHashes   = BLOCKED_HASHES,

    -- ===== Optional contract fields =======================================
    HasVariantRules = true,
    VariantRules    = VARIANT_RULES,
    KBLayouts       = KB_LAYOUTS,
    DefaultLayout   = "QWERTZ",
    ScoreWeights    = SCORE_WEIGHTS,
    Locales         = { "deDE" },
    DisplayName     = "Deutsch",
})

if not ok and DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cffff6666Yapper_Dict_deDE:|r Failed to register German language engine."
    )
end
