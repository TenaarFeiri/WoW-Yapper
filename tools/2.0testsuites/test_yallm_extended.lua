-- Mock Globals
_G.YapperDB = {}
_G.time = os.time

local YapperName, YapperTable = "Yapper", {
    Utils = {
        EnsureTable = function(_, t) return type(t) == "table" and t or {} end,
        Print = function() end,
        VerbosePrint = function() end,
        DebugPrint = function() end,
    },
    Config = { 
        Spellcheck = { 
            Enabled = true, 
            YASFreqCap = 5, 
            YASBiasCap = 100,
            YASAutoThreshold = 3
        },
        System = { DEBUG = false }
    },
    Spellcheck = {
        IsDebugEnabled = function() return false end,
        Dictionaries = { enUS = {} }, -- YAS:IsEnabled requires a loaded dictionary
        IsEnabled = function() return true end,
        GetLocale = function() return "enUS" end,
        GetDictionary = function() return nil end, -- No ngram check for basic tests
    }
}

-- Load the real YAS
loadfile("../../Src/Spellcheck/Adaptive.lua")(YapperName, YapperTable)
local YAS = YapperTable.Spellcheck.YAS
YAS:Init()

local function assert_bool(val, expected, msg)
    if val ~= expected then
        print(string.format("  [FAIL] %s: expected %s, got %s", msg, tostring(expected), tostring(val)))
        os.exit(1)
    else
        print(string.format("  [PASS] %s", msg))
    end
end

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        print(string.format("  [FAIL] %s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
        os.exit(1)
    else
        print(string.format("  [PASS] %s", msg))
    end
end

print("Verifying YAS Refactor & New Logic...")
print("---------------------------------------")

-- 1. IsSaneWord Invariants (Pre-cleaned expectations)
print("1. IsSaneWord (Pre-cleaned):")
assert_bool(YAS:IsSaneWord("apple"), true, "Valid word accepted")
assert_bool(YAS:IsSaneWord("a"), false, "Too short rejected")
assert_bool(YAS:IsSaneWord("thisiswaytoolongtobeactuallyconsideredasanehumanword"), false, "Too long rejected")
assert_bool(YAS:IsSaneWord("strngthss"), false, "Consonant cluster rejected")
assert_bool(YAS:IsSaneWord("aaab"), false, "Keyboard smash rejected")

-- 2. RecordUsage Logic (Standard)
print("\n2. RecordUsage (Standard):")
YAS:RecordUsage("The quick brown fox", "enUS")
local db = YAS:GetLocaleDB("enUS")
assert_eq(db.freq["quick"] ~= nil, true, "Recorded standard word")
assert_eq(db.freq["the"] ~= nil, true, "Recorded lowercase word")

-- 3. Slash Command Skipping
print("\n3. Slash Command Skipping:")
YAS:Reset("enUS")
YAS:RecordUsage("/dance happily", "enUS")
db = YAS:GetLocaleDB("enUS")
assert_eq(db.freq["dance"], nil, "Ignored first word of slash command (/dance)")
assert_eq(db.freq["happily"] ~= nil, true, "Recorded subsequent words in slash command")

YAS:Reset("enUS")
YAS:RecordUsage("   /dance happily", "enUS")
db = YAS:GetLocaleDB("enUS")
assert_eq(db.freq["dance"], nil, "Ignored first word with leading spaces")

-- 4. Learning Pruning (Capacity)
print("\n4. Capacity Pruning (Cap=100):")
YapperTable.Config.Spellcheck.YASFreqCap = 100
YAS:Reset("enUS")
for i = 1, 100 do
    YAS:RecordUsage("word" .. i, "enUS")
end
db = YAS:GetLocaleDB("enUS")
assert_eq(db.total, 100, "Reached capacity")

YAS:RecordUsage("extra", "enUS")
print("  Total after 'extra':", db.total)
assert_eq(db.total <= 100, true, "Stayed at or below capacity (pruned)")
assert_eq(db.freq["extra"] ~= nil, true, "Newly added word exists")

-- 5. RecordIgnored (Auto-Learn Path)
print("\n5. RecordIgnored (Manual Word Typing):")
YAS:Reset("enUS")
local learned = false
YapperTable.Spellcheck.AddUserWord = function(self, loc, word)
    if word == "SpecialWord" then learned = true end
end

YAS:RecordIgnored("SpecialWord", "enUS")
YAS:RecordIgnored("SpecialWord", "enUS")
assert_bool(learned, false, "Not learned yet (Threshold=3)")
YAS:RecordIgnored("SpecialWord", "enUS")
assert_bool(learned, true, "Learned after 3 ignores")

-- 6. Phase 0 regressions
print("\n6. Phase 0 correctness:")

-- 6a. Disabled YAS collects nothing and promotes nothing.
YapperTable.Config.Spellcheck.YASEnabled = false
YAS:Reset("enUS")
learned = false
YAS:RecordUsage("ghostword", "enUS")
YAS:RecordIgnored("SpecialWord", "enUS")
YAS:RecordSelection("typ", "typed", 0.5, "enUS")
YAS:RecordRejection("typ", { "typed" }, "enUS")
db = YAS:GetLocaleDB("enUS", true)
assert_bool(db == nil or (db.freq["ghostword"] == nil and db.auto["specialword"] == nil
    and next(db.bias) == nil and next(db.negBias) == nil),
    true, "Disabled YAS: no freq/auto/bias/negBias writes")
assert_bool(learned, false, "Disabled YAS: no auto-promotion")
assert_eq(YAS:GetBonus("x", "y", nil, "enUS"), 0, "Disabled YAS: GetBonus returns 0")
YapperTable.Config.Spellcheck.YASEnabled = nil
YAS:Reset("enUS")

-- 6b. db._rev bumps on every scoring-relevant writer.
YAS:Reset("enUS")
db = YAS:GetLocaleDB("enUS")
local rev0 = db._rev or 0
YAS:RecordUsage("revword", "enUS")
db = YAS:GetLocaleDB("enUS")
assert_bool((db._rev or 0) > rev0, true, "_rev bumped by RecordUsage (freq write)")
rev0 = db._rev
YAS:RecordRejection("typo", { "badword" }, "enUS")
db = YAS:GetLocaleDB("enUS")
assert_bool((db._rev or 0) > rev0, true, "_rev bumped by RecordRejection (negBias write)")
rev0 = db._rev
YAS:RecordSelection("typo", "goodword", 0.5, "enUS")
db = YAS:GetLocaleDB("enUS")
assert_bool((db._rev or 0) > rev0, true, "_rev bumped by RecordSelection (bias write)")

-- 6c. Nil locale resolves to the active spellcheck locale (stub = enUS),
-- never the orphaned "enBASE" key.
YAS:Reset("enUS")
_G.YapperDB.SpellcheckLearned = {}; YAS:Init()
YAS:RecordUsage("parked")  -- no locale arg
assert_bool(_G.YapperDB.SpellcheckLearned.enBASE == nil, true, "No enBASE partition created")
db = YAS:GetLocaleDB("enUS", true)
assert_bool(db ~= nil and db.freq["parked"] ~= nil, true, "Nil-locale write landed in active locale")

-- 6d. Pre-locale writes park under _pending and fold forward.
_G.YapperDB.SpellcheckLearned = {}; YAS:Init()
local realGetLocale = YapperTable.Spellcheck.GetLocale
YapperTable.Spellcheck.GetLocale = function() return nil end
YAS:RecordUsage("earlybird")
assert_bool(_G.YapperDB.SpellcheckLearned._pending ~= nil
    and _G.YapperDB.SpellcheckLearned._pending.freq["earlybird"] ~= nil,
    true, "Pre-locale write parked under _pending")
YapperTable.Spellcheck.GetLocale = realGetLocale
db = YAS:GetLocaleDB("enUS")
assert_bool(_G.YapperDB.SpellcheckLearned._pending == nil, true, "_pending drained")
assert_bool(db.freq["earlybird"] ~= nil, true, "_pending merged into enUS")

-- 6e. Flat legacy DB parks under _legacy at Init, then merges on first touch.
_G.YapperDB.SpellcheckLearned = {
    freq = { legacylearned = { c = 5, t = 1 } },
    bias = { ["ooold:cold"] = { c = 2, t = 1, u = 1 } },
}
YAS:Init()
assert_bool(_G.YapperDB.SpellcheckLearned._legacy ~= nil, true, "Flat legacy parked under _legacy")
assert_bool(_G.YapperDB.SpellcheckLearned.freq == nil, true, "Flat root cleared at Init")
db = YAS:GetLocaleDB("enUS")
assert_bool(_G.YapperDB.SpellcheckLearned._legacy == nil, true, "_legacy folded into enUS")
assert_bool(db.freq["legacylearned"] ~= nil and db.freq["legacylearned"].c == 5,
    true, "Legacy freq entry preserved (count intact)")
assert_bool(db.bias["ooold:cold"] ~= nil, true, "Legacy bias entry preserved")

-- 6f. Stranded "enBASE"/"enBase" partitions merge into the real locale.
YAS:Reset("enUS")
_G.YapperDB.SpellcheckLearned = {}; YAS:Init()
_G.YapperDB.SpellcheckLearned.enBASE = { freq = { stranded = { c = 3, t = 1 } } }
_G.YapperDB.SpellcheckLearned.enBase = { freq = { addonkey = { c = 1, t = 1 } } }
db = YAS:GetLocaleDB("enUS")
assert_bool(db.freq["stranded"] ~= nil, true, "enBASE partition merged into enUS")
assert_bool(db.freq["addonkey"] ~= nil, true, "enBase partition merged into enUS")
assert_bool(_G.YapperDB.SpellcheckLearned.enBASE == nil
    and _G.YapperDB.SpellcheckLearned.enBase == nil, true, "Stranded keys removed")

-- 6g. Peek mode (noCreate) never allocates partitions.
YAS:Reset("enUS")
_G.YapperDB.SpellcheckLearned = {}; YAS:Init()
assert_eq(YAS:GetLocaleDB("enUS", true), nil, "Peek on missing partition returns nil")
assert_bool(_G.YapperDB.SpellcheckLearned.enUS == nil, true, "Peek did not create partition")

-- 6h. autoCount is maintained across promotion.
YAS:Reset("enUS")
db = YAS:GetLocaleDB("enUS")
for _ = 1, 3 do YAS:RecordIgnored("CountedWord", "enUS") end
assert_eq(db.auto["countedword"], nil, "Promoted word removed from auto table")
assert_eq(db.autoCount or 0, 0, "autoCount decremented on promotion")

-- 6i. ClearSpecificUsage maintains counters and bumps _rev for scoring tables.
YAS:Reset("enUS")
db = YAS:GetLocaleDB("enUS")
YAS:RecordUsage("clearword", "enUS")
YAS:RecordSelection("clr", "cleared", 0.5, "enUS")
db = YAS:GetLocaleDB("enUS")
assert_eq(db.total, 1, "total counts freq entry")
assert_eq(db.biasCount, 1, "biasCount counts bias entry")
rev0 = db._rev
YAS:ClearSpecificUsage("freq", "clearword", "enUS")
db = YAS:GetLocaleDB("enUS")
assert_eq(db.total, 0, "ClearSpecificUsage decremented total")
assert_bool(db._rev > rev0, true, "_rev bumped by ClearSpecificUsage")
rev0 = db._rev
YAS:ClearSpecificUsage("bias", "clr:cleared", "enUS")
db = YAS:GetLocaleDB("enUS")
assert_eq(db.biasCount or 0, 0, "ClearSpecificUsage decremented biasCount")

-- 6j. IsSaneWord honours the configured ngram index, not a hardcoded 2.
YapperTable.Spellcheck.GetNgramN = function() return 3 end
YapperTable.Spellcheck.GetDictionary = function()
    return { ngramIndex3 = { ["pl*"] = { 1 } } } -- "apple" -> "*ppl*" has pl*
end
assert_bool(YAS:IsSaneWord("apple", "enUS"), true, "ngramIndex3 anchor accepts 'apple'")
assert_bool(YAS:IsSaneWord("zzzqk", "enUS"), false, "ngramIndex3 anchor rejects 'zzzqk'")
YapperTable.Spellcheck.GetNgramN = function() return 4 end
assert_bool(YAS:IsSaneWord("apple", "enUS"), true,
    "Missing ngramIndex4 skips anchor check (index absent)")
YapperTable.Spellcheck.GetNgramN = nil
YapperTable.Spellcheck.GetDictionary = function() return nil end

-- 7. Phase 1: intent classification
print("\n7. Intent classification:")

-- Controllable runtime clock for exposure/dwell tests.
local fakeNow = 1000.0
_G.GetTime = function() return fakeNow end

-- 7a. Shown popup + dwell + sent unchanged => WAIVER.
YAS:Reset("enUS")
YAS:RecordExposure("wavedword", "enUS")
fakeNow = fakeNow + 2.0 -- user lingered 2s after the popup appeared
YAS:RecordIgnored("wavedword", "enUS")
assert_eq(YAS:GetIntent("wavedword", "enUS"), "WAIVER", "Seen-and-sent-unchanged is waiver")

-- 7b. Fast send (< dwell minimum) gives no waiver credit.
YAS:Reset("enUS")
YAS:RecordExposure("fastword", "enUS")
fakeNow = fakeNow + 0.2 -- sent almost immediately: never saw the popup
YAS:RecordIgnored("fastword", "enUS")
assert_eq(YAS:GetIntent("fastword", "enUS"), nil, "Fast send stays unclassified")

-- 7c. Stale exposure (> TTL) is not credited to this send.
YAS:Reset("enUS")
YAS:RecordExposure("staleword", "enUS")
fakeNow = fakeNow + 60.0
YAS:RecordIgnored("staleword", "enUS")
db = YAS:GetLocaleDB("enUS")
assert_eq(db.intent["staleword"].waived or 0, 0, "Expired exposure is not a waiver")

-- 7d. Consistent unchanged sends => INTENTIONAL, and auto-promotion works.
YAS:Reset("enUS")
learned = false
YapperTable.Spellcheck.AddUserWord = function(self, loc, word)
    if word == "Rpname" then learned = true end
end
for _ = 1, 3 do YAS:RecordIgnored("Rpname", "enUS") end
assert_eq(YAS:GetIntent("rpname", "enUS"), "INTENTIONAL", "Consistent unchanged sends are intentional")
assert_bool(learned, true, "INTENTIONAL word promotes at auto threshold")
db = YAS:GetLocaleDB("enUS")
assert_eq(db.intent["rpname"].pinned, "INTENTIONAL", "Promotion pins the intent record")

-- 7e. Any correction evidence => ACCIDENT, and auto-promotion is blocked.
YAS:Reset("enUS")
learned = false
YapperTable.Spellcheck.AddUserWord = function(self, loc, word)
    if word == "mispell" then learned = true end
end
YAS:RecordIgnored("mispell", "enUS")
YAS:RecordSelection("mispell", "misspell", 0.5, "enUS") -- user once accepted a fix
for _ = 1, 6 do YAS:RecordIgnored("mispell", "enUS") end
assert_eq(YAS:GetIntent("mispell", "enUS"), "ACCIDENT", "Correction evidence classifies accident")
assert_bool(learned, false, "ACCIDENT token never auto-promotes")
db = YAS:GetLocaleDB("enUS")
assert_bool(db.auto["mispell"] ~= nil and db.auto["mispell"].c >= 6, true,
    "Accident sends still counted (but never promote)")

-- 7f. Implicit corrections also count as accident evidence.
YAS:Reset("enUS")
YapperTable.Spellcheck.GetPhoneticHash = function(w) return "PH:" .. w end
YAS:RecordImplicitCorrection("bakc", "back", nil, "enUS")
assert_eq(YAS:GetIntent("bakc", "enUS"), "ACCIDENT", "Backtrack-correction is accident evidence")

-- 7g. RecordRejection on an INTENTIONAL token skips negBias entirely.
YAS:Reset("enUS")
for _ = 1, 3 do YAS:RecordIgnored("rpname", "enUS") end -- INTENTIONAL
YAS:RecordRejection("rpname", { "rename", "ripname" }, "enUS")
db = YAS:GetLocaleDB("enUS")
assert_eq(next(db.negBias), nil, "No negBias written for INTENTIONAL token")
assert_eq(db.intent["rpname"].waived, 1, "Rejection still counted as waiver evidence")

-- 7h. RecordRejection on an unclassified token still writes negBias + waiver.
YAS:Reset("enUS")
YAS:RecordRejection("typo", { "typo1", "typo2" }, "enUS")
db = YAS:GetLocaleDB("enUS")
assert_bool(db.negBias["typo:typo1"] ~= nil, true, "negBias written for normal token")
assert_eq(db.intent["typo"].waived, 1, "Rejection recorded waiver signal")

-- 7i. Explicit pins win over inferred classes and survive pruning.
YAS:Reset("enUS")
YAS:PinIntent("guildslang", "INTENTIONAL", "enUS")
YAS:RecordSelection("guildslang", "guildsling", 0.5, "enUS") -- noise can't unpin
assert_eq(YAS:GetIntent("guildslang", "enUS"), "INTENTIONAL", "Pin overrides accident evidence")

-- Pinned records are immune to intent pruning. (GetIntentCap floors at 100.)
YapperTable.Config.Spellcheck.YASIntentCap = 100
YAS:Reset("enUS")
YAS:PinIntent("keepme", "WAIVER", "enUS")
for i = 1, 110 do YAS:RecordIgnored("filler" .. i, "enUS") end
db = YAS:GetLocaleDB("enUS")
assert_bool(db.intent["keepme"] ~= nil and db.intent["keepme"].pinned == "WAIVER", true,
    "Pinned intent survives pruning")
assert_bool(db.intentCount <= 101, true,
    "Intent cap enforced on unpinned records (pinned exempt)")
YapperTable.Config.Spellcheck.YASIntentCap = nil

-- 7j. Disabled YAS: intent records nothing and GetIntent reads nothing.
YapperTable.Config.Spellcheck.YASEnabled = false
YAS:Reset("enUS")
YAS:RecordExposure("deadword", "enUS")
YAS:RecordIgnored("deadword", "enUS")
YAS:PinIntent("deadword", "INTENTIONAL", "enUS")
db = YAS:GetLocaleDB("enUS", true)
assert_bool(db == nil or next(db.intent or {}) == nil, true,
    "Disabled YAS writes no intent records")
assert_eq(YAS:GetIntent("deadword", "enUS"), nil, "Disabled YAS classifies nothing")
assert_bool(YAS._exposed == nil or YAS._exposed["deadword"] == nil, true,
    "Disabled YAS records no exposure")
YapperTable.Config.Spellcheck.YASEnabled = nil

-- 7k. Pending intent records merge forward into the real locale.
YAS:Reset("enUS")
_G.YapperDB.SpellcheckLearned = {}; YAS:Init()
YapperTable.Spellcheck.GetLocale = function() return nil end
YAS:RecordIgnored("parkedintent", nil) -- parks under "_pending"
YapperTable.Spellcheck.GetLocale = function() return "enUS" end
db = YAS:GetLocaleDB("enUS")
assert_bool(db.intent["parkedintent"] ~= nil
    and db.intent["parkedintent"].sentUnchanged == 1, true,
    "Pending intent record merged into enUS")
assert_eq(_G.YapperDB.SpellcheckLearned._pending, nil, "_pending drained")

_G.GetTime = nil

-- 8. Phase 2: bigrams, error profile, consolidation
print("\n8. Bigrams / error profile / consolidation:")

-- 8a. RecordUsage records prev->next transitions, "<s>" for openers.
YAS:Reset("enUS")
YAS:RecordUsage("see you later", "enUS")
db = YAS:GetLocaleDB("enUS")
assert_bool(db.bigram["<s>"] and db.bigram["<s>"]["see"] ~= nil, true,
    "Sentence-initial bigram recorded under <s>")
assert_bool(db.bigram["see"] and db.bigram["see"]["you"] ~= nil, true,
    "Transition see->you recorded")
assert_bool(db.bigram["you"] and db.bigram["you"]["later"] ~= nil, true,
    "Transition you->later recorded")
assert_eq(db.bigramCount, 3, "bigramCount tracks transitions")

-- 8b. Bigram context flows into GetBonus.
YAS:Reset("enUS")
for _ = 1, 3 do YAS:RecordUsage("im sorry", "enUS") end
local bWith = YAS:GetBonus("sorry", "sory", nil, "enUS", "im")
local bWithout = YAS:GetBonus("sorry", "sory", nil, "enUS", "unrelated")
assert_bool(bWith < bWithout, true, "Bigram-observed candidate scores better")

-- 8c. errProfile accumulates edit-op classes from accepted corrections.
YAS:Reset("enUS")
YAS:RecordSelection("teh", "the", 0.5, "enUS")    -- transposition
YAS:RecordSelection("mispell", "misspell", 0.5, "enUS") -- insert (missing s)
db = YAS:GetLocaleDB("enUS")
assert_eq(db.errProfile.ops.transpose, 1, "Transposition classified")
assert_eq(db.errProfile.ops.insert, 1, "Insertion classified")

-- errAffinity: transposition candidate benefits when user transposes a lot.
for _ = 1, 5 do YAS:RecordSelection("wrod", "word", 0.5, "enUS") end
local bTr = YAS:GetBonus("word", "wrod", nil, "enUS") -- transpose fix
local bSub = YAS:GetBonus("xord", "wrod", nil, "enUS") -- substitution fix
assert_bool(bTr < bSub, true, "Habitual-transpose user favours transpose fixes")

-- confusion pair recorded for substitutions
YAS:RecordSelection("cot", "cat", 0.5, "enUS")
assert_bool(db.errProfile.conf["o>a"] ~= nil, true, "Confusion pair o->a recorded")

-- 8d. PruneBigrams evicts low-score transitions, keeps buckets clean.
YAS:Reset("enUS")
YapperTable.Config.Spellcheck.YASBigramCap = 3
for i = 1, 8 do YAS:RecordUsage("p" .. i .. " n" .. i, "enUS") end
db = YAS:GetLocaleDB("enUS")
assert_eq(db.bigramCount, 16, "bigramCount tracked") -- 8 lines x (<s>->w + w->w)
YAS:PruneBigrams(4, "enUS")
local total = 0
for _, bucket in pairs(db.bigram) do for _ in pairs(bucket) do total = total + 1 end end
assert_bool(total <= 4, true, "PruneBigrams evicts down to ~90% of limit")
YapperTable.Config.Spellcheck.YASBigramCap = nil

-- 8e. Consolidation decays cold counts and evicts stale unclassified intent.
YAS:Reset("enUS")
db = YAS:GetLocaleDB("enUS")
local old = time() - 40 * 86400 -- 40 days ago
db.freq["coldword"] = { c = 8, t = old }
db.freq["hotword"] = { c = 8, t = time() }
db.total = 2
db.intent["staleone"] = { c = 1, t = time() - 70 * 86400, lastSeen = time() - 70 * 86400, sentUnchanged = 1 }
db.intentCount = 1
YAS._consolidating = { db = db, phaseIdx = 1 }
while YAS:_ConsolidationStep() do end
assert_eq(db.freq["coldword"].c, 4, "Cold freq count halved")
assert_eq(db.freq["hotword"].c, 8, "Recent count untouched")
assert_eq(db.intent["staleone"], nil, "Stale unclassified intent evicted")
assert_eq(db.intentCount, 0, "intentCount maintained by consolidation")

-- 8f. Consolidation decays to removal and bumps _rev.
YAS:Reset("enUS")
db = YAS:GetLocaleDB("enUS")
db.freq["dyingword"] = { c = 1, t = old }
db.total = 1
local revBefore = db._rev or 0
YAS._consolidating = { db = db, phaseIdx = 1 }
while YAS:_ConsolidationStep() do end
assert_eq(db.freq["dyingword"], nil, "Count decayed to zero is removed")
assert_eq(db.total, 0, "total maintained on decay removal")
assert_bool((db._rev or 0) > revBefore, true, "Decay bumps _rev")

-- 8g. Bigram merge: stranded partition's transitions fold forward.
YAS:Reset("enUS")
_G.YapperDB.SpellcheckLearned = {}; YAS:Init()
_G.YapperDB.SpellcheckLearned._pending = {
    bigram = { ["<s>"] = { hello = { c = 2, t = 1 } } },
    errProfile = { ops = { transpose = 2 }, conf = { ["i>e"] = 1 } },
}
db = YAS:GetLocaleDB("enUS")
assert_bool(db.bigram["<s>"]["hello"] ~= nil, true, "Pending bigram merged forward")
assert_eq(db.errProfile.ops.transpose, 2, "Pending errProfile merged forward")
assert_eq(db.bigramCount, 1, "bigramCount recounted after merge")

-- 8h. Disabled YAS: consolidation never starts, RecordUsage writes no bigrams.
YapperTable.Config.Spellcheck.YASEnabled = false
YAS:Reset("enUS")
assert_eq(YAS:StartConsolidation("enUS"), false, "Disabled: consolidation refuses")
YAS:RecordUsage("one two three", "enUS")
db = YAS:GetLocaleDB("enUS", true)
assert_bool(db == nil or db.bigram == nil or next(db.bigram) == nil, true,
    "Disabled: no bigram writes")
YapperTable.Config.Spellcheck.YASEnabled = nil


print("")
print("=== 9. Learned scorer (Phase 3) ===")

-- 9a. Accepting a suggestion reinforces the features behind it.
YAS:Reset("enUS")
YAS:RecordUsage("apple apple apple apple", "enUS")  -- freq c=4
YAS:RecordSelection("aple", "apple", 0, "enUS")
db = YAS:GetLocaleDB("enUS")
assert_bool(db.model ~= nil, true, "Model table created on first update")
assert_bool(db.model.m.freq > 1, true, "Accepted pick reinforces freq multiplier")
assert_bool(db.model.m.bias > 1, true, "Accepted pick reinforces bias multiplier")

-- 9b. Rejection dampens the features behind the rejected candidate.
local beforeFreq = db.model.m.freq
YAS:RecordRejection("aple", { "apple" }, "enUS")
assert_bool(db.model.m.freq < beforeFreq, true, "Rejection dampens freq multiplier")

-- 9c. Multipliers are clamped at the floor no matter how many rejections.
for i = 1, 250 do YAS:RecordRejection("aple", { "apple" }, "enUS") end
assert_bool(db.model.m.freq >= 0.25, true, "Multiplier clamped at floor")

-- 9d. Self-eval: enough re-corrections of promoted picks regresses the model.
YAS:Reset("enUS")
db = YAS:GetLocaleDB("enUS")
db.model = {
    m = { freq = 4, bias = 1, ph = 1, neg = 1, bigram = 1, err = 1 },
    updates = 1,
    eval = { promotedAccepted = 10, retypeAfterPromoted = 10 },
}
YAS._lastPromoted = { sometypo = "goodword" }
YAS:RecordImplicitCorrection("sometypo", "different", {}, "enUS")
assert_bool(db.model.m.freq < 4 and db.model.m.freq > 1,
    true, "Self-eval regresses multipliers toward 1")
assert_eq(db.model.eval.promotedAccepted, 0, "Eval counters reset on regression")

-- 9e. Regression only fires with enough samples.
YAS:Reset("enUS")
db = YAS:GetLocaleDB("enUS")
db.model = {
    m = { freq = 4, bias = 1, ph = 1, neg = 1, bigram = 1, err = 1 },
    updates = 1,
    eval = { promotedAccepted = 3, retypeAfterPromoted = 2 },
}
YAS._lastPromoted = { sometypo = "goodword" }
YAS:RecordImplicitCorrection("sometypo", "different", {}, "enUS")
assert_eq(db.model.m.freq, 4, "Below sample floor: no regression")

-- 9f. Model from a stranded partition folds forward on merge.
YAS:Reset("enUS")
_G.YapperDB.SpellcheckLearned = {}; YAS:Init()
_G.YapperDB.SpellcheckLearned.enBASE = { model = { m = { freq = 2 } } }
db = YAS:GetLocaleDB("enUS")
assert_eq(db.model.m.freq, 2, "Stranded model adopted on merge")

-- 9g. Disabled YAS: no model writes.
YapperTable.Config.Spellcheck.YASEnabled = false
YAS:Reset("enUS")
YAS:RecordSelection("aple", "apple", 0.5, "enUS")
YAS:RecordRejection("aple", { "apple" }, "enUS")
db = YAS:GetLocaleDB("enUS", true)
assert_bool(db == nil or db.model == nil, true, "Disabled: no model writes")
YapperTable.Config.Spellcheck.YASEnabled = nil


print("")
print("=== 10. Autocorrect scaffold (Phase 4) ===")

-- 10a. Bare token: classification works, no evidence -> OFFER.
YAS:Reset("enUS")
db = YAS:GetLocaleDB("enUS")
local d = YAS:ClassifySuggestion("aple", "apple", "enUS")
assert_bool(d ~= nil, true, "ClassifySuggestion returns a decision")
assert_eq(d.tier, "OFFER", "No evidence -> OFFER tier")
assert_bool(d.vetoReasons.intentional, false, "No intent veto on bare token")

-- 10b. INTENTIONAL token is a hard SUPPRESS veto.
db.intent["rpname"] = { c = 1, t = time(), pinned = "INTENTIONAL", sentUnchanged = 5 }
local d2 = YAS:ClassifySuggestion("rpname", "renamed", "enUS")
assert_eq(d2.tier, "SUPPRESS", "Intentional token suppressed")
assert_bool(d2.vetoReasons.intentional, true, "vetoReasons.intentional set")

-- 10c. Strong evidence can reach AUTO.
YAS:Reset("enUS")
db = YAS:GetLocaleDB("enUS")
db.freq["apple"] = { c = 100, t = time() }
db.bias["aple:apple"] = { c = 5, t = time(), u = 5 }
db.bigram["see"] = { apple = { c = 5, t = time() } }
local d3 = YAS:ClassifySuggestion("aple", "apple", "enUS", "see")
assert_eq(d3.tier, "AUTO", "Strong evidence reaches AUTO tier")

-- 10d. Engine AutocorrectVeto blocks AUTO; MaxConfidence caps the score.
YapperTable.Spellcheck._EngineForLocale = function() return {
    Autocorrect = {
        AutocorrectVeto = function() return true end,
        MaxConfidence = 0.5,
    },
} end
YapperTable.Spellcheck._SafeEngineCall = function(_, eng, key, passSelf, a1, a2)
    local f = eng[key]; if passSelf then return f(eng, a1, a2) end
    return f(a1, a2)
end
local d4 = YAS:ClassifySuggestion("aple", "apple", "enUS", "see")
assert_bool(d4.confidence <= 0.5, true, "Engine MaxConfidence caps confidence")
assert_bool(d4.tier ~= "AUTO", true, "Engine veto blocks AUTO")
assert_bool(d4.vetoReasons.engineVeto, true, "vetoReasons.engineVeto set")
YapperTable.Spellcheck._EngineForLocale = nil
YapperTable.Spellcheck._SafeEngineCall = nil

-- 10e. Self-eval suspends the AUTO tier.
db.model = { m = {}, updates = 1, eval = { promotedAccepted = 10, retypeAfterPromoted = 10 } }
local d5 = YAS:ClassifySuggestion("aple", "apple", "enUS", "see")
assert_bool(d5.tier ~= "AUTO", true, "Self-eval suspends AUTO tier")
assert_eq(d5.tier, "SUGGEST", "Suspended AUTO falls back to SUGGEST")

-- 10f. ShadowClassify is opt-in and bounded.
local d6 = YAS:ShadowClassify("aple", "apple", "enUS")
assert_eq(d6, nil, "ShadowClassify off by default")
YapperTable.Config.Spellcheck.YASAutocorrectShadow = true
local d7 = YAS:ShadowClassify("aple", "apple", "enUS")
assert_bool(d7 ~= nil, true, "ShadowClassify emits decision when enabled")
db = YAS:GetLocaleDB("enUS")
assert_eq(#db.autocorrLog, 1, "Shadow decision logged")
assert_eq(db.autocorrLog[1].s, "apple", "Log records suggestion")
for i = 1, 80 do YAS:ShadowClassify("w"..i, "apple", "enUS") end
assert_bool(#db.autocorrLog <= 50, true, "autocorrLog bounded at 50")
YapperTable.Config.Spellcheck.YASAutocorrectShadow = nil

-- 10g. Undo ring: LIFO, bounded, session-only.
YAS:Reset("enUS")
YAS:PushUndo({ pos = 5, original = "teh", applied = "the" })
YAS:PushUndo({ pos = 9, original = "adn", applied = "and" })
local u = YAS:PopUndo()
assert_eq(u.original, "adn", "Undo pops most recent")
assert_eq(u.applied, "and", "Undo record intact")
for i = 1, 80 do YAS:PushUndo({ pos = i, original = "w"..i, applied = "x"..i }) end
assert_bool(#YAS._undoRing <= 50, true, "Undo ring bounded at 50")
YAS:Reset("enUS")
assert_eq(YAS._undoRing, nil, "Reset clears undo ring")

-- 10h. Disabled YAS: classify/shadow/undo all inert.
YapperTable.Config.Spellcheck.YASEnabled = false
YAS:Reset("enUS")
assert_eq(YAS:ClassifySuggestion("aple", "apple", "enUS"), nil, "Disabled: no classification")
YapperTable.Config.Spellcheck.YASAutocorrectShadow = true
assert_eq(YAS:ShadowClassify("aple", "apple", "enUS"), nil, "Disabled: no shadow log")
YAS:PushUndo({ pos = 1, original = "a", applied = "b" })
assert_eq(YAS._undoRing, nil, "Disabled: no undo writes")
YapperTable.Config.Spellcheck.YASEnabled = nil
YapperTable.Config.Spellcheck.YASAutocorrectShadow = nil

print("\nAll YAS extended tests passed successfully.")
