# Custom Dictionaries & Language Engines

How to build a dictionary addon for Yapper's spellcheck system.

> The engine contract is strict. Yapper rejects malformed engines and
> dictionaries loudly rather than falling back to English behaviour. Read the
> [Contract](#the-language-engine-contract) section before shipping.

## 1. Addon layout

A dictionary addon is a normal WoW addon that depends on `Yapper` and registers
itself through `_G.YapperAPI`:

```
Yapper_Dict_xxYY/
    Yapper_Dict_xxYY.toc
    Engine.lua          -- language engine (contract table)
    Dict_xxYY.lua       -- dictionary data / lazy builder
```

Example `.toc`:

```toc
## Interface: 110107
## Title: Yapper Dictionary: xxYY
## Dependencies: Yapper
## LoadOnDemand: 1

Engine.lua
Dict_xxYY.lua
```

- `## Dependencies: Yapper` guarantees `YapperAPI` exists before your files run.
- `## LoadOnDemand: 1` keeps the dictionary out of memory until the user
  selects the locale. Yapper calls `C_AddOns.LoadAddOn` when needed.
- `Engine.lua` must load before `Dict_xxYY.lua` (toc order): the dictionary is
  rejected if its language family has no registered engine.

## 2. Two registration calls

```lua
-- 1. Register the language engine FIRST (in Engine.lua):
local ok = YapperAPI:RegisterLanguageEngine("xx", engineTable)

-- 2. Then register the dictionary (in Dict_xxYY.lua), binding it to the family:
YapperAPI:RegisterDictionary("xxYY", {
    languageFamily = "xx",
    words = { ... },
    phonetics = { ... },   -- optional phonetic index, see §5
})
```

`familyId` is a short identifier shared by dialects of the same language
(`"en"` serves `enUS`, `enGB`, `enAU`, `enBase`). `locale` is the concrete
dictionary key the user selects in settings.

You may also bundle the engine inside the dictionary table as `data.engine`;
it is registered with the same owner before the dictionary is validated. When
bundling, ship engine and dictionary **from the same addon** — the owner lock
(§7) rejects a bundled engine that tries to claim a family owned by another
addon.

## 3. The language engine contract

An engine is a plain table. The table is **deep-copied** on registration
(functions stay shared), then validated. Any failure rejects the registration.

### Required fields

| Field | Type | Contract |
|---|---|---|
| `NormaliseWord` | `function(word) -> string` | Canonical dictionary-lookup form (e.g. lowercase). Must be **idempotent**: `f(f(w)) == f(w)`. Output capped at 256 bytes. |
| `NormaliseVowels` | `function(word) -> string` | Vowel-neutral form: replace each vowel with `*`. Powers the n-gram index and the vowel-match scoring bonus. |
| `GetPhoneticHash` | `function(word) -> string` | Phonetic index key matching your `phonetics` table. Return `""` for unmappable words. Output capped at 128 bytes. |
| `HashWord` | `function(word) -> number` | uint32 integer hash (e.g. DJB2) used for blocklist lookups. Input is already `NormaliseWord`-canonical. |
| `BlockedHashes` | `table` | `{ [HashWord(word)] = true }` — mandatory. A dictionary without blocklist data is considered unsafe and is refused. Capped at 250 000 entries. |
| `WordBytes` | `table` | `{ [byte] = true }` — bytes that may *continue* a word token (0–255 keys only). |
| `WordStartBytes` | `table` | `{ [byte] = true }` — bytes that may *start* a word token. `'{'` (byte 123) is always added by core (raid icons). |

### Optional fields

| Field | Type | Contract |
|---|---|---|
| `StripAffixes` | `function(engine, word, dict) -> string|nil` | Colon-called convention: invoked as `engine:StripAffixes(word, dict)`. Return the dictionary root for an inflected form, or `nil`. |
| `ShouldCheckWord` | `function(word, minLen) -> boolean` | Full override of the "is this token worth checking" gate. Default drops sub-`minLen` words, digits and ALL-CAPS. |
| `MatchCase` | `function(input, suggestion) -> string` | Maps a suggestion to the casing the language expects given the user's raw input (e.g. capitalise nouns). Default: ASCII capitalise-first when input starts uppercase. |
| `IsSaneWord` | `function(word) -> boolean` | Additional veto applied to YAS auto-learning, on top of core length/consonant/bigram checks. |
| `HasVariantRules` | `boolean` | Must be `true` when `VariantRules` is present. |
| `VariantRules` | `table` | Array of `{ from, to }` string pairs (≤64 rules, ≤32 bytes per side, `from ≠ to`). Dialect spelling variants, e.g. `{ "or", "our" }`. Used for scoring bonus and direct injection. |
| `ScoreWeights` | `table` | Subset of the core weight keys (`lenDiff`, `longerPenalty`, `prefix`, `letterBag`, `bigram`, `kbProximity`, `firstCharBias`, `vowelBonus`), finite numbers with |v| ≤ 1000. |
| `KBLayouts` | `table` | `{ LAYOUTNAME = { char = { x, y } } }` — up to 16 layouts, ≤256 keys each, coords within ±64. |
| `DefaultLayout` | `string` | Name of a key in `KBLayouts`; used when the user's saved layout is absent. |
| `Locales` | `table` | Array of locale ids this engine serves (≤64). Lets core resolve the family before a dictionary loads. |
| `DisplayName` | `string` | ≤64 bytes; shown in docs/debug output. |
| `Autocorrect` | `table` | Optional block feeding the autocorrect decision scaffold. All sub-fields optional — see below. |

#### `Autocorrect` sub-fields

| Field | Type | Contract |
|---|---|---|
| `SplitCompounds` | `function(word) -> {w1, w2, ...}\|nil` | Compound decomposition (e.g. German `"ichhabe"` → `{"ich","habe"}`). Probed at registration; must return `nil` or 2–8 non-empty strings. |
| `ConfusionPairs` | `table` | `{ ["a>b"] = count }` — language-known confusables that seed the user's error profile. ≤256 entries, keys literally `x>y` (3 bytes), counts finite numbers in [0, 10000]. |
| `AutocorrectVeto` | `function(word, suggestion) -> boolean` | Language veto: never auto-apply this correction (e.g. case-semantic languages where a surface form is a proper noun). Probed; must return a boolean. |
| `MaxConfidence` | `number` | Per-language ceiling on endorsed confidence, [0, 1]. `0` = the language never endorses autocorrection. |

The `Autocorrect` block is **scaffold today** — no code applies corrections
silently yet. It exists so engines can ship language knowledge before the
feature lands, and so `YAS:ClassifySuggestion` tiering already honours
engine vetoes and confidence ceilings.

**Strict rules**

- Unknown top-level keys are rejected. Engine-private extras must use an
  `X_` prefix (e.g. `X_PhonemeTable`); they are ignored by core.
- Required functions are *probed* at registration over representative inputs
  (`"hello"`, `"Don't"`, `"Straße"`, `"a"`). A function that errors, returns
  a wrong type, or breaks idempotency fails the whole registration.
- `ShouldCheckWord`/`IsSaneWord` must return real booleans; `MatchCase` must
  return a string; `StripAffixes` must return a string or `nil`.
- Table caps: `VariantRules` ≤ 64; `KBLayouts` ≤ 16 layouts × 256 keys;
  `BlockedHashes` ≤ 250 000 entries; `Locales` ≤ 64 ids;
  `Autocorrect.ConfusionPairs` ≤ 256 entries.

## 4. Failure, replacement and purge semantics

- **Registration failure** prints a red `Yapper Error:` line naming the
  violated rule, records the reason in `Spellcheck._failedEngines[familyId]`,
  and returns `false` from `RegisterLanguageEngine`. Nothing is stored.
- **Runtime failure**: engine entry points that can run user-facing hot paths
  (`GetPhoneticHash`, `StripAffixes`, `ShouldCheckWord`, `MatchCase`,
  `IsSaneWord`, top-level `NormaliseWord`) are called through a protected
  boundary. If engine code throws, the engine is **purged**: removed from the
  registry, every dictionary bound to its family is unloaded, all derived
  caches (suggestions, keyboard distances, user-word sets, dict metadata) are
  wiped, and the affected locales are marked `ENGINE_PURGED`. Re-enabling the
  locale in settings retries the load; a still-broken engine fails
  registration again with the same loud error.
- **Re-registration** by the owning addon replaces the engine and purges all
  derived caches, so changed normalisers/hashes take effect immediately.

## 5. The dictionary data bundle

`RegisterDictionary(locale, data)` accepts:

| Field | Type | Notes |
|---|---|---|
| `languageFamily` | `string` | **Required** (or inherited via `extends`). Must name a registered engine family. |
| `words` | `table` | Array of dictionary words (canonical casing is up to you; `engine.NormaliseWord` decides the lookup form). |
| `phonetics` | `table` | `{ [GetPhoneticHash(word)] = { wordId, ... } }` — wordIds are **1-based indices into this bundle's own `words` array** (a delta does NOT offset by the base length). Must be produced by the same hash rules the engine ships (see `tools/phonetics_en.py`/`generate_phonetic_dict.py` for the English pipeline and parity protocol). |
| `extends` | `string` | Base locale id for a delta dictionary (see below). |
| `affixRules` | `table` | Optional `{ Strip = function(self, word, dict) ... end }` consulted before the engine's default affix rules. |
| `engine` | `table` | Optional embedded engine, registered with this bundle's owner. |
| `isPreBuilt` | `boolean` | Skip indexing when the bundle already contains `set`/`index`. |

`data` may also be a **builder function** `function() return dataTable end`,
invoked lazily the first time the locale is loaded. Registration keeps the
caller's addon name as the owner for any embedded engine.

### Inheritance (`extends`)

A regional dictionary declares `extends = "<base locale>"`. The base is
load-on-demand: core ensures it loads first. The delta's `set`, `words`,
`phonetics` and n-gram indices inherit the base tables via metatables, so a
small delta gets the full base vocabulary without duplicating memory. If the
delta omits `languageFamily`, it inherits the base's family.

```
Yapper_Dict_enUS   → RegisterDictionary("enUS", { extends = "enBase", words = {...} })
Yapper_Dict_en     → provides "enBase" + registers the "en" engine
```

## 6. Owner lock and safety

- Registration is **owner-locked**: the first addon folder name seen calling
  `RegisterLanguageEngine` for a family becomes its owner; later registrations
  for that family from a *different* addon are rejected. Ownerless
  registrations (internal/test callers) don't claim a family.
- Owner capture is best-effort attribution via `debug.getinfo` — **not** a
  security boundary. WoW addons share one Lua state: a dictionary addon can
  technically read `_G.Yapper` and other globals. There is no practical way
  to sandbox a peer addon in-process. The supported integration surface is
  `_G.YapperAPI` only; anything read off Yapper internals is private by
  convention and may change without notice.
- For the same reason there is no `pcall` around dictionary data tables'
  *contents* beyond the contract checks: be honest in what you ship — a
  hostile or sloppy addon can still allocate arbitrarily via its own code.

## 7. Minimal example

```lua
-- Yapper_Dict_xxYY/Engine.lua
local function NormaliseWord(w) return type(w) == "string" and w:lower() or "" end
local function NormaliseVowels(w) return (w:lower():gsub("[aeiou]", "*")) end
local function GetPhoneticHash(w) return (w:upper():gsub("[AEIOU]", "")) end

local function HashWord(w)
    local h = 5381
    for i = 1, #w do h = (h * 33 + w:byte(i)) % 4294967296 end
    return h
end

local WORD_BYTES, WORD_START_BYTES = {}, {}
for b = 65, 90 do WORD_BYTES[b] = true; WORD_START_BYTES[b] = true end
for b = 97, 122 do WORD_BYTES[b] = true; WORD_START_BYTES[b] = true end
for b = 128, 255 do WORD_BYTES[b] = true end -- UTF-8 continuation bytes
WORD_BYTES[39] = true -- apostrophe

if not _G.YapperAPI then return end

local ok = YapperAPI:RegisterLanguageEngine("xx", {
    NormaliseWord   = NormaliseWord,
    NormaliseVowels = NormaliseVowels,
    GetPhoneticHash = GetPhoneticHash,
    HashWord        = HashWord,
    BlockedHashes   = { [HashWord("badword")] = true },
    WordBytes       = WORD_BYTES,
    WordStartBytes  = WORD_START_BYTES,
    Locales         = { "xxYY" },
    DisplayName     = "Example",
})
if not ok then return end
```

```lua
-- Yapper_Dict_xxYY/Dict_xxYY.lua
if not _G.YapperAPI then return end
YapperAPI:RegisterDictionary("xxYY", {
    languageFamily = "xx",
    words = { "alpha", "beta", "gamma" },
})
```

Tell Yapper which addon to load for the locale (either in the dict file or at
install time):

```lua
YapperAPI:RegisterLocaleAddon("xxYY", "Yapper_Dict_xxYY")
```

Then select the locale in Yapper settings → Spellcheck. Watch for the
`Yapper Error:` notification — every contract violation names its rule.

## 8. Testing a custom dictionary

- `luac -p` every `.lua` file (Lua 5.1 — no `goto`, no bitwise ops, no `//`).
- `lua tools/2.0testsuites/test_engine_contract.lua` exercises the contract
  against the real core modules; use it as a harness pattern.
- In-game: enable the locale, type deliberately misspelled words, check that
  suggestions appear and that learning (YAS) respects your `NormaliseWord`.
- If the engine errors at runtime, the engine + its dictionaries are purged
  and a chat error is printed — fix the engine and `/reload`.

## 9. Phonetic-index parity

`dict.phonetics` must be generated with the **same** rules as the engine's
`GetPhoneticHash`, or phonetic suggestions silently never match. The English
engine and `tools/phonetics_en.py` (driven by `tools/generate_phonetic_dict.py`)
are kept in lockstep via the protocol in `Dictionaries/Yapper_Dict_en/Engine.lua`;
do the same for your generator. Note Lua 5.1 gotchas the pipeline hit for real:
`string.upper`/`lower` are ASCII-only (lowercase UTF-8 umlauts need explicit
byte mappings), and `string.gsub` cannot quantify a `%n` backreference — a
"collapse repeated runs" rule must loop single-pair collapses until stable.

Indices are **local to each bundle**: a delta's postings index into its own
`words` array starting at 1 — the loader chains `dict.words` to the base via
metatable, so do not add the base's length. Candidate lookup walks the whole
`extends` chain and unions postings, so a delta may safely reuse a hash the
base also defines. Postings are validated at registration: every id must be a
1-based index into the bundle's own `words` array — an out-of-range or
non-integer posting rejects the dictionary outright.

## 10. Translating Yapper's UI

Dictionary addons may also ship UI strings for their language via
`YapperAPI:RegisterStrings(locale, strings)`. The table is a sparse map of
canonical keys (see `Src/Strings.lua` for the full list) to translated text;
anything you omit falls back to English. UI strings follow the **client**
locale (`GetLocale()`), not the spellcheck locale — a German client gets
German labels even while spellchecking in English.

```lua
YapperAPI:RegisterStrings("deDE", {
    ["ui.spellcheck.more"]      = "%d. Weitere Vorschläge »",
    ["ui.spellcheck.backtotop"] = "%d. « Zurück zum Anfang",
    ["ui.emotes.hint"]          = "Tab: Emotes durchsuchen",
})
```

Registration is owner-captured and validated (keys must exist in the
canonical English table; lengths are bounded), fires `STRINGS_UPDATED` so
open UI can re-render, and re-registration replaces your contribution
wholesale. Because dictionary addons are load-on-demand, strings can arrive
after the UI exists — call sites resolve at render time, so this works.
