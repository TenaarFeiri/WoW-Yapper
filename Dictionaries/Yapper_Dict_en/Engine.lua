-- Yapper_Dict_en/Engine.lua
-- English language engine for the Yapper Spellcheck system.
--
-- Registers via YapperAPI:RegisterLanguageEngine("en", engine).
-- This must load before Dict_enBase.lua (ensured by TOC order).
--
-- IMPORTANT: The phonetic rules in GetPhoneticHash MUST remain in exact parity
-- with the Python generation script (tools/generate_phonetic_dict_en.py).
-- See Documentation/Spellcheck/SpellcheckSpec.md for the change protocol.

-- ---------------------------------------------------------------------------
-- Variant rules: spellings that differ between English dialects.
-- Used by the scoring engine to boost candidates that are variant-spellings
-- of the input (e.g. "colour" suggested when the user types "color").
-- ---------------------------------------------------------------------------
local VARIANT_RULES = {
    { "or",   "our"  }, { "our",  "or"   },
    { "ize",  "ise"  }, { "ise",  "ize"  },
    { "er",   "re"   }, { "re",   "er"   },
    { "og",   "ogue" }, { "ogue", "og"   },
    { "l",    "ll"   }, { "ll",   "l"    },
}

-- ---------------------------------------------------------------------------
-- Keyboard layouts
-- Each layout maps lowercase letter → {x, y} screen coordinates.
-- x is the column (with stagger offset), y is the row.
-- Only a-z; digits and punctuation are filtered before proximity scoring.
-- ---------------------------------------------------------------------------
local KB_LAYOUTS = {
    QWERTY = {
        q = { 0,    0 }, w = { 1,    0 }, e = { 2,    0 }, r = { 3,    0 },
        t = { 4,    0 }, y = { 5,    0 }, u = { 6,    0 }, i = { 7,    0 },
        o = { 8,    0 }, p = { 9,    0 },
        a = { 0.25, 1 }, s = { 1.25, 1 }, d = { 2.25, 1 }, f = { 3.25, 1 },
        g = { 4.25, 1 }, h = { 5.25, 1 }, j = { 6.25, 1 }, k = { 7.25, 1 },
        l = { 8.25, 1 },
        z = { 0.75, 2 }, x = { 1.75, 2 }, c = { 2.75, 2 }, v = { 3.75, 2 },
        b = { 4.75, 2 }, n = { 5.75, 2 }, m = { 6.75, 2 },
    },
    QWERTZ = {
        q = { 0,    0 }, w = { 1,    0 }, e = { 2,    0 }, r = { 3,    0 },
        t = { 4,    0 }, z = { 5,    0 }, u = { 6,    0 }, i = { 7,    0 },
        o = { 8,    0 }, p = { 9,    0 },
        a = { 0.25, 1 }, s = { 1.25, 1 }, d = { 2.25, 1 }, f = { 3.25, 1 },
        g = { 4.25, 1 }, h = { 5.25, 1 }, j = { 6.25, 1 }, k = { 7.25, 1 },
        l = { 8.25, 1 },
        y = { 0.75, 2 }, x = { 1.75, 2 }, c = { 2.75, 2 }, v = { 3.75, 2 },
        b = { 4.75, 2 }, n = { 5.75, 2 }, m = { 6.75, 2 },
    },
    AZERTY = {
        a = { 0,    0 }, z = { 1,    0 }, e = { 2,    0 }, r = { 3,    0 },
        t = { 4,    0 }, y = { 5,    0 }, u = { 6,    0 }, i = { 7,    0 },
        o = { 8,    0 }, p = { 9,    0 },
        q = { 0.25, 1 }, s = { 1.25, 1 }, d = { 2.25, 1 }, f = { 3.25, 1 },
        g = { 4.25, 1 }, h = { 5.25, 1 }, j = { 6.25, 1 }, k = { 7.25, 1 },
        l = { 8.25, 1 }, m = { 9.25, 1 },
        w = { 0.75, 2 }, x = { 1.75, 2 }, c = { 2.75, 2 }, v = { 3.75, 2 },
        b = { 4.75, 2 }, n = { 5.75, 2 },
    },
}

-- ---------------------------------------------------------------------------
-- NormaliseVowels
-- Strips vowels (replaced with '*') for vowel-neutral similarity comparisons.
-- ---------------------------------------------------------------------------
local string_gsub  = string.gsub
local string_lower = string.lower
local string_upper = string.upper
local string_sub   = string.sub

local function NormaliseVowels(word)
    if type(word) ~= "string" then return "" end
    return string_gsub(string_lower(word), "[aeiouy]", "*")
end

-- ---------------------------------------------------------------------------
-- GetPhoneticHash  (MUST match tools/generate_phonetic_dict_en.py exactly)
--
-- Change protocol (see SpellcheckSpec.md):
--   1. Update SpellcheckSpec.md → English phonetic rules section
--   2. Update this function
--   3. Update tools/generate_phonetic_dict_en.py
--   4. Regenerate enBase, enGB, enUS phonetics tables
-- ---------------------------------------------------------------------------
local function GetPhoneticHash(word)
    local hash = string_upper(word)
    -- Strip non-alphabetic characters (including apostrophes)
    hash = string_gsub(hash, "[^%a]", "")

    -- Strip duplicate adjacent letters (e.g. "LL" → "L")
    hash = string_gsub(hash, "(%a)%1", "%1")

    -- Silent / variable consonant groups
    hash = string_gsub(hash, "GHT", "T")
    hash = string_gsub(hash, "PH",  "F")
    hash = string_gsub(hash, "KN",  "N")
    hash = string_gsub(hash, "GN",  "N")
    hash = string_gsub(hash, "WR",  "R")
    hash = string_gsub(hash, "CH",  "K")
    hash = string_gsub(hash, "SH",  "X")
    hash = string_gsub(hash, "C",   "K")
    hash = string_gsub(hash, "Q",   "K")
    hash = string_gsub(hash, "X",   "KS")
    hash = string_gsub(hash, "Z",   "S")

    -- GH at end of word sounds like F (laugh, enough)
    if string_sub(hash, -2) == "GH" then
        hash = string_sub(hash, 1, -3) .. "F"
    else
        hash = string_gsub(hash, "GH", "")  -- silent GH (night, through)
    end

    if hash == "" then return "" end

    -- Keep first letter; strip remaining vowels
    local firstChar = string_sub(hash, 1, 1)
    local rest      = string_sub(hash, 2)
    rest = string_gsub(rest, "[AEIOUY]", "")

    return firstChar .. rest
end

-- ---------------------------------------------------------------------------
-- Register the English language engine with Yapper.
-- YapperAPI is a global injected by Yapper before any LOD addons load.
-- ---------------------------------------------------------------------------
if not _G.YapperAPI then
    -- Safety net: if this somehow loads before Yapper, bail gracefully.
    return
end

local ok = YapperAPI:RegisterLanguageEngine("en", {
    -- Required
    GetPhoneticHash = GetPhoneticHash,

    -- Optional helpers — fall back to built-in if absent
    NormaliseVowels = NormaliseVowels,

    -- English has British/American spelling variants
    HasVariantRules = true,
    VariantRules    = VARIANT_RULES,

    -- Keyboard layout data (same schema as the built-in KB_LAYOUTS table)
    KBLayouts       = KB_LAYOUTS,

    -- No ScoreWeights override — English uses the built-in defaults
    ScoreWeights    = nil,
})

if not ok then
    -- This should never happen unless Yapper is out of date.
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffff6666Yapper_Dict_en:|r Failed to register English language engine. " ..
            "Ensure Yapper is up to date."
        )
    end
end
