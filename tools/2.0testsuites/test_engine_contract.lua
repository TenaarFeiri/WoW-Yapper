#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
-- test_engine_contract.lua  --  Language-engine contract tests
-- Run from the repo root:  lua tools/2.0testsuites/test_engine_contract.lua
--
-- Covers the strict RegisterLanguageEngine contract: required/optional field
-- validation, function probes, owner locking, dictionary family binding, and
-- purge semantics when an engine faults at runtime.
-- ---------------------------------------------------------------------------

local PASS, FAIL, TESTS, FAILURES = "PASS", "FAIL", 0, 0

local function check(label, condition)
    TESTS = TESTS + 1
    if condition then
        print("  [" .. PASS .. "] " .. label)
    else
        FAILURES = FAILURES + 1
        print("  [" .. FAIL .. "] " .. label)
    end
end

-- ===========================================================================
-- Minimal WoW environment mock
-- ===========================================================================
local notified = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) notified[#notified + 1] = msg end }
_G.GetCurrentRegion = function() return nil end
_G.GetLocale = function() return "enUS" end

local YapperName = "Yapper"
local YapperTable = {
    Config = {
        System = { DEBUG = false, VERBOSE = false },
        Spellcheck = { Enabled = true, Locale = "tloc" },
    },
}

local function loadModule(path)
    local loader, err = loadfile(path)
    if not loader then
        print("FATAL: cannot load " .. path .. ": " .. tostring(err))
        os.exit(1)
    end
    loader(YapperName, YapperTable)
end

loadModule("Src/Utils.lua")
YapperTable.Utils.Print = function() end

loadModule("Src/Spellcheck.lua")
loadModule("Src/Spellcheck/Dictionary.lua")
loadModule("Src/Spellcheck/Engine.lua")

local Spellcheck = YapperTable.Spellcheck
-- UI-owned timer path is not under test; stub it.
Spellcheck.ScheduleRefresh = function() end

-- ===========================================================================
-- Helpers
-- ===========================================================================
local function byteSet(extra)
    local t = {}
    for b = 65, 90 do t[b] = true end
    for b = 97, 122 do t[b] = true end
    for b = 128, 255 do t[b] = true end
    for _, b in ipairs(extra or {}) do t[b] = true end
    return t
end

local function makeEngine()
    return {
        NormaliseWord   = function(w) return type(w) == "string" and w:lower() or "" end,
        NormaliseVowels = function(w) return (w:lower():gsub("[aeiou]", "*")) end,
        GetPhoneticHash = function(w) return w:upper():gsub("[AEIOU]", "") end,
        HashWord        = function(w)
            local h = 5381
            for i = 1, #w do h = (h * 33 + w:byte(i)) % 4294967296 end
            return h
        end,
        BlockedHashes   = {},
        WordBytes       = byteSet({ 39 }),
        WordStartBytes  = byteSet(),
    }
end

local function resetEngines()
    Spellcheck.LanguageEngines = {}
    Spellcheck._engineOwners = {}
    Spellcheck._engineFamily = {}
    Spellcheck._failedEngines = {}
    Spellcheck.Dictionaries = {}
    Spellcheck._failedLocaleLoads = {}
    Spellcheck.UserDictCache = {}
    Spellcheck:ClearSuggestionCache()
end

-- ===========================================================================
-- Test 1: happy-path registration
-- ===========================================================================
print("\nTest 1: contract acceptance")

resetEngines()
local eng = makeEngine()
check("valid engine accepted", Spellcheck:_RegisterLanguageEngine("t1", eng) == true)
check("engine stored", Spellcheck:GetEngine("t1") == eng)
check("'{' injected into WordStartBytes", eng.WordStartBytes[123] == true)
check("family backref recorded", Spellcheck._engineFamily[eng] == "t1")

-- ===========================================================================
-- Test 2: required-field rejection
-- ===========================================================================
print("\nTest 2: required-field rejection")

local function rejectCase(label, mutate)
    resetEngines()
    local e = makeEngine()
    mutate(e)
    local ok = Spellcheck:_RegisterLanguageEngine("t2", e)
    check(label, ok ~= true and Spellcheck.LanguageEngines.t2 == nil
        and Spellcheck._failedEngines.t2 ~= nil)
end

for _, field in ipairs({
    "NormaliseWord", "NormaliseVowels", "GetPhoneticHash",
    "HashWord", "BlockedHashes", "WordBytes", "WordStartBytes",
}) do
    rejectCase("missing " .. field, function(e) e[field] = nil end)
end

rejectCase("BlockedHashes non-numeric key", function(e) e.BlockedHashes = { foo = true } end)
rejectCase("WordBytes non-byte key", function(e) e.WordBytes = { [300] = true, a = true } end)
rejectCase("WordBytes non-true value", function(e) e.WordBytes = { [97] = 1 } end)
rejectCase("WordStartBytes false value", function(e) e.WordStartBytes = { [98] = false } end)

-- ===========================================================================
-- Test 3: probe failures
-- ===========================================================================
print("\nTest 3: function probes")

rejectCase("NormaliseWord errors", function(e) e.NormaliseWord = function() error("boom") end end)
rejectCase("NormaliseWord non-string", function(e) e.NormaliseWord = function() return 5 end end)
rejectCase("NormaliseWord non-idempotent", function(e)
    local flip = false
    e.NormaliseWord = function(w) flip = not flip; return flip and w:lower() or w:upper() end
end)
rejectCase("GetPhoneticHash non-string", function(e) e.GetPhoneticHash = function() return {} end end)
rejectCase("HashWord out of range", function(e) e.HashWord = function() return -1 end end)
rejectCase("HashWord non-integer", function(e) e.HashWord = function() return 1.5 end end)

-- ===========================================================================
-- Test 4: strict whitelist + optional field validation
-- ===========================================================================
print("\nTest 4: whitelist + optional fields")

rejectCase("unknown top-level key", function(e) e.TotallyCustomField = 1 end)

resetEngines()
local e4 = makeEngine()
e4.X_VendorExtension = { anything = true }
check("X_ extension keys allowed", Spellcheck:_RegisterLanguageEngine("t4", e4) == true)

rejectCase("VariantRules without HasVariantRules", function(e) e.VariantRules = { { "a", "b" } } end)
rejectCase("VariantRules malformed entry", function(e)
    e.HasVariantRules = true; e.VariantRules = { { "a" } }
end)
rejectCase("VariantRules too many", function(e)
    e.HasVariantRules = true
    e.VariantRules = {}
    for i = 1, 65 do e.VariantRules[i] = { "a" .. i, "b" .. i } end
end)
rejectCase("ScoreWeights unknown key", function(e) e.ScoreWeights = { madeUpWeight = 1 } end)
rejectCase("ScoreWeights non-number", function(e) e.ScoreWeights = { lenDiff = "x" } end)
rejectCase("KBLayouts bad coords", function(e)
    e.KBLayouts = { Q = { a = { "x", 0 } } }
end)
rejectCase("DefaultLayout not in KBLayouts", function(e)
    e.KBLayouts = { Q = { a = { 0, 0 } } }
    e.DefaultLayout = "MISSING"
end)
rejectCase("DefaultLayout without KBLayouts", function(e) e.DefaultLayout = "QWERTY" end)
rejectCase("ShouldCheckWord non-boolean", function(e) e.ShouldCheckWord = function() return "yes" end end)
rejectCase("MatchCase non-string", function(e) e.MatchCase = function() return 42 end end)

rejectCase("Autocorrect unknown sub-field", function(e)
    e.Autocorrect = { MysteryFn = function() end }
end)
rejectCase("Autocorrect.MaxConfidence out of range", function(e)
    e.Autocorrect = { MaxConfidence = 1.5 }
end)
rejectCase("Autocorrect.MaxConfidence non-number", function(e)
    e.Autocorrect = { MaxConfidence = "high" }
end)
rejectCase("Autocorrect.ConfusionPairs bad key", function(e)
    e.Autocorrect = { ConfusionPairs = { badkey = 1 } }
end)
rejectCase("Autocorrect.ConfusionPairs bad count", function(e)
    e.Autocorrect = { ConfusionPairs = { ["a>b"] = "many" } }
end)
rejectCase("Autocorrect.ConfusionPairs over cap", function(e)
    e.Autocorrect = { ConfusionPairs = {} }
    local i = 0
    for a = 0, 25 do
        for b = 0, 25 do
            i = i + 1
            if i > 257 then break end
            e.Autocorrect.ConfusionPairs[string.char(97 + a) .. ">" .. string.char(97 + b)] = i
        end
        if i > 257 then break end
    end
end)
rejectCase("Autocorrect.SplitCompounds returns string", function(e)
    e.Autocorrect = { SplitCompounds = function() return "notatable" end }
end)
rejectCase("Autocorrect.SplitCompounds single part", function(e)
    e.Autocorrect = { SplitCompounds = function() return { "word" } end }
end)
rejectCase("Autocorrect.SplitCompounds errors", function(e)
    e.Autocorrect = { SplitCompounds = function() error("boom") end }
end)
rejectCase("Autocorrect.AutocorrectVeto non-boolean", function(e)
    e.Autocorrect = { AutocorrectVeto = function() return "sure" end }
end)

resetEngines()
local e4c = makeEngine()
e4c.Autocorrect = {
    SplitCompounds = function(w)
        if w == "testword" then return { "test", "word" } end
    end,
    ConfusionPairs = { ["i>e"] = 3 },
    AutocorrectVeto = function() return false end,
    MaxConfidence = 0.9,
}
check("valid Autocorrect block accepted", Spellcheck:_RegisterLanguageEngine("t4c", e4c) == true)

resetEngines()
local e4b = makeEngine()
e4b.KBLayouts = { QTEST = { a = { 0, 0 }, b = { 1, 0 } } }
e4b.DefaultLayout = "QTEST"
e4b.Locales = { "tloc" }
e4b.DisplayName = "Test"
e4b.ScoreWeights = { lenDiff = 2.5 }
check("valid optional fields accepted", Spellcheck:_RegisterLanguageEngine("t4b", e4b) == true)
check("locales set built", e4b._localesSet and e4b._localesSet.tloc == true)

-- ===========================================================================
-- Test 5: owner lock
-- ===========================================================================
print("\nTest 5: owner lock")

resetEngines()
check("first owner registers", Spellcheck:_RegisterLanguageEngine("t5", makeEngine(), "AddonA") == true)
check("same owner can re-register", Spellcheck:_RegisterLanguageEngine("t5", makeEngine(), "AddonA") == true)
check("foreign owner rejected", Spellcheck:_RegisterLanguageEngine("t5", makeEngine(), "AddonB") ~= true)
check("lock records owner", Spellcheck._engineOwners.t5 == "AddonA")
check("nil owner can register other family", Spellcheck:_RegisterLanguageEngine("t5b", makeEngine(), nil) == true)

-- ===========================================================================
-- Test 6: dictionary registration requires a resolvable engine
-- ===========================================================================
print("\nTest 6: dictionary family binding")

resetEngines()
Spellcheck:RegisterDictionary("nodict", { words = { "hello" } })
check("dict without languageFamily rejected", Spellcheck.Dictionaries.nodict == nil)

Spellcheck:RegisterDictionary("orphan", { words = { "hello" }, languageFamily = "missing" })
check("dict with unregistered family rejected", Spellcheck.Dictionaries.orphan == nil)

Spellcheck:_RegisterLanguageEngine("test", makeEngine())
Spellcheck:RegisterDictionary("tloc", { words = { "hello", "world", "help" }, languageFamily = "test" })
check("dict with registered engine accepted", Spellcheck.Dictionaries.tloc ~= nil)
check("dict indexed via engine normaliser", Spellcheck.Dictionaries.tloc.set.hello == true)

-- Bundled engine registration via dictionary data bundle.
Spellcheck:RegisterDictionary("bundled", {
    words = { "bundled" },
    languageFamily = "bundfam",
    engine = makeEngine(),
}, "BundleAddon")
check("bundled engine registered", Spellcheck:GetEngine("bundfam") ~= nil)
check("bundled dict accepted", Spellcheck.Dictionaries.bundled ~= nil)

-- ===========================================================================
-- Test 7: runtime fault purges engine + bound dictionaries
-- ===========================================================================
print("\nTest 7: engine purge on runtime fault")

resetEngines()
local e7 = makeEngine()
Spellcheck:_RegisterLanguageEngine("test", e7)
Spellcheck:RegisterDictionary("tloc", { words = { "hello", "world" }, languageFamily = "test" })
check("dict present pre-purge", Spellcheck.Dictionaries.tloc ~= nil)

-- Simulate a runtime fault inside an engine method.
e7.GetPhoneticHash = function() error("engine exploded") end
local hash = Spellcheck.GetPhoneticHash("hello")
check("faulted call returns empty", hash == "")
check("engine removed", Spellcheck.LanguageEngines.test == nil)
check("bound dict purged", Spellcheck.Dictionaries.tloc == nil)
check("locale marked failed", Spellcheck._failedLocaleLoads.tloc == "ENGINE_PURGED")
check("failure recorded", Spellcheck._failedEngines.test ~= nil)
check("notify emitted", #notified > 0)

-- ===========================================================================
-- Test 8: delegates + tokenisation + blocklist
-- ===========================================================================
print("\nTest 8: delegates and tokenisation")

resetEngines()
local e8 = makeEngine()
Spellcheck:_RegisterLanguageEngine("test", e8)
Spellcheck:RegisterDictionary("tloc", { words = { "hello", "world" }, languageFamily = "test" })

check("NormaliseWord delegate", Spellcheck.NormaliseWord("HELLO") == "hello")
check("NormaliseVowels delegate", Spellcheck.NormaliseVowels("hello") == "h*ll*")
check("GetPhoneticHash delegate", Spellcheck.GetPhoneticHash("hello") == "HLL")
check("IterWords splits on engine bytes", (function()
    local words = {}
    for _, _, w in Spellcheck.IterWords("one, two! don't") do
        words[#words + 1] = w
    end
    return #words == 3 and words[3] == "don't"
end)())
check("IterWords sees '{' as word-start", (function()
    local first
    for _, _, w in Spellcheck.IterWords("x {star") do first = w end
    return first == "{star" or first == "{star}"
end)())

-- Blocklist: hash a blocked word with the engine's own HashWord.
local blockedWord = "badword"
e8.BlockedHashes[e8.HashWord(blockedWord)] = true
check("IsWordBlocked via engine hash", Spellcheck:IsWordBlocked("badword", "tloc", true) == true)
check("IsWordBlocked clean word", Spellcheck:IsWordBlocked("hello", "tloc", true) == false)

-- ===========================================================================
-- Test 9: keyboard layout resolution
-- ===========================================================================
print("\nTest 9: engine keyboard layouts")

resetEngines()
local e9 = makeEngine()
e9.KBLayouts = {
    QTEST = { a = { 0, 0 }, b = { 1, 0 }, c = { 2, 0 } },
    OTHER = { a = { 9, 9 } },
}
e9.DefaultLayout = "QTEST"
Spellcheck:_RegisterLanguageEngine("test", e9)
Spellcheck:RegisterDictionary("tloc", { words = { "abc" }, languageFamily = "test" })

check("layout names sorted", (function()
    local names = Spellcheck:GetKeyboardLayoutNames()
    return #names == 2 and names[1] == "OTHER" and names[2] == "QTEST"
end)())
check("default layout resolves", Spellcheck:GetKeyboardLayout() == "QTEST")
check("dist table built", (function()
    local d = Spellcheck:_GetKBDistFromLayouts(e9.KBLayouts, "QTEST")
    return type(d) == "table" and #d == 676 and d[(97 - 97) * 26 + (98 - 97) + 1] == 1
end)())
check("missing layout returns nil", Spellcheck:_GetKBDistFromLayouts(e9.KBLayouts, "NOPE") == nil)
check("nil layouts returns nil", Spellcheck:_GetKBDistFromLayouts(nil, "QWERTY") == nil)

-- ===========================================================================
-- Summary
-- ===========================================================================
print(("\n%d checks, %d failures"):format(TESTS, FAILURES))
if FAILURES > 0 then os.exit(1) end
print("ALL TESTS PASSED")
