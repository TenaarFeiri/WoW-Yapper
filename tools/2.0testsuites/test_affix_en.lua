#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_affix_en.lua  --  English affix-strip regression tests
-- Run from the repo root:  lua tools/2.0testsuites/test_affix_en.lua
--
-- Loads the real Dictionaries/Yapper_Dict_en/Engine.lua and exercises
-- StripAffixes against a toy dictionary.  Covers the suffix classes the
-- upstream Hunspell sources derive via flags that our flat wordlists do not
-- always spell out — most importantly -ive (flag V, e.g. "ale" -> "alive")
-- and the y-fold comparatives (-ier/-iest, e.g. "cozy" -> "cozier").
-- ---------------------------------------------------------------------------

local PASS, FAIL, FAILURES = "PASS", "FAIL", 0

local function check(label, condition)
    if condition then
        print("  [" .. PASS .. "] " .. label)
    else
        FAILURES = FAILURES + 1
        print("  [" .. FAIL .. "] " .. label)
    end
end

-- The dictionary engine registers through the LOD-addon global.
local registered
_G.YapperAPI = {
    RegisterLanguageEngine = function(self, family, engine)
        registered = engine
        return true
    end,
}

local loader = assert(loadfile("Dictionaries/Yapper_Dict_en/Engine.lua"))
loader()
assert(registered and registered.StripAffixes, "en engine did not register StripAffixes")

-- Toy dictionary: StripAffixes consults dict:Contains for candidate roots.
local set = {
    ale = true, conduce = true, innovate = true, deliberate = true,
    coerce = true, immerse = true, recluse = true, adopt = true,
    cozy = true, cosy = true, sad = true, happy = true, ready = true,
    live = true, give = true, five = true, olive = true, talk = true,
    perform = true,
    blame = true, use = true, move = true, agree = true, comfort = true,
    enjoy = true, tea = true, go = true,
}
local dict = {
    set = set,
    Contains = function(self, w) return set[w] == true end,
}

local function strip(word)
    return registered.StripAffixes(registered, word, dict)
end

local function expectStrip(word, root)
    check(("'%s' strips to '%s'"):format(word, root), strip(word) == root)
end
local function expectNil(word)
    check(("'%s' not affix-resolved"):format(word), strip(word) == nil)
end

-- == -ive (flag V) =======================================================
-- Upstream derives these via ale/V-style flags; the original import never
-- expanded them so they were stranded in locale deltas (or missing, like
-- "alive" itself — the case that started this audit).
expectStrip("alive", "ale")
expectStrip("conducive", "conduce")
expectStrip("innovative", "innovate")
expectStrip("deliberative", "deliberate")
expectStrip("coercive", "coerce")
expectStrip("immersive", "immerse")
expectStrip("reclusive", "recluse")
-- non-e root branch: adopt -> adoptive
expectStrip("adoptive", "adopt")

-- == -able (flag B) =====================================================
-- The 5 upstream -able forms absent from every shipped dict were all
-- e-drop derivations on -ize roots; the rule also covers the consonant
-- and ee branches upstream defines.
expectStrip("blamable", "blame")
expectStrip("usable", "use")
expectStrip("movable", "move")
expectStrip("comfortable", "comfort")
expectStrip("enjoyable", "enjoy")   -- 'y' is a consonant for [^aeiou]
expectStrip("agreeable", "agree")   -- ee-stem branch
-- upstream only allows -able on consonant/ee stems; vowel stems reject
expectNil("goable")
expectNil("teaable")
-- "able" itself and short words must not strip
expectNil("sable")

-- == -ier / -iest y-fold (flags R/T: y -> ier/iest) ======================
expectStrip("cozier", "cozy")
expectStrip("coziest", "cozy")
expectStrip("cosier", "cosy")
expectStrip("happier", "happy")
expectStrip("readiest", "ready")

-- == existing rules still hold =========================================
expectStrip("sadly", "sad")
expectStrip("talking", "talk")
-- ness i->y fold only fires when the root exists ("lively" not in toy set)
expectNil("liveliness")

-- == must not over-strip ===============================================
expectNil("five")
expectNil("olive")
expectNil("dive")
expectNil("archive")   -- root "arch" not in toy set
-- "lives" resolves via the -s rule (root "live" in set), not -ive
check("'lives' resolves via -s to 'live'", strip("lives") == "live")

if FAILURES > 0 then
    print(("FAILED: %d checks failed"):format(FAILURES))
    os.exit(1)
end
print("SUCCESS: all affix checks passed")
