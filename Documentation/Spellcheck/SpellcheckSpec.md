# Yapper Spellcheck Engine Specification

With the introduction of Load-on-Demand (LOD) language addons, Yapper’s spellchecking system is decoupled from the English algorithmic rules. This document specifies the contract that all external language engines must satisfy.

## Language Engine Contract

Every language addon must register its rules and data with Yapper during the AddOn load sequence by calling:

```lua
YapperAPI:RegisterLanguageEngine(familyId, engineTable)
```

The `engineTable` is defined as:

### Required Fields
*   `GetPhoneticHash(word) -> string`: A deterministic function that converts normalized words into phonetic hash strings. This function **MUST MAINTAIN EXACT PARITY** with the Python script used to generate the static dictionary database.

### Optional Fields (Will use fallback if omitted)
*   `NormaliseVowels(word) -> string`: Function to fold vowels into a predictable character (e.g., `*`) for edit-distance scoring. If omitted, uses the English fallback `[AEIOUY] -> *`.
*   `HasVariantRules` (boolean): Set to `true` if this language provides variant spelling equivalence checks.
*   `VariantRules` (array of tuples): Table describing equivalent suffix or infix structures. Example: `{ {"or", "our"}, {"ize", "ise"} }`.
*   `ScoreWeights` (table): Optional overrides for the various penalty weights in the spelling suggestion scoring engine.
*   `KBLayouts` (table): Hardware keyboard locale layouts mapping lowercase characters to `[x,y]` coordinates for finger-travel distance tracking.

---

## Dictionary Pre-generation Protocol (Python)

To ensure the engine can search its dictionary in real time, all words in an LOD dictionary must pre-calculate their `phoneticHash` during out-of-band packaging.

When updating the logic inside a language's `GetPhoneticHash`, you **MUST**:
1.  Document the rule change in this Markdown file.
2.  Port the exact equivalent string-manipulation logic into `tools/generate_phonetic_dict_XX.py`.
3.  Run the Python script across the source wordlist to regenerate the LOD `.lua` dictionary files.
4.  Update `GetPhoneticHash` in the language's `Engine.lua`.

Failure to keep `GetPhoneticHash` identical between the Python build step and the Lua runtime will result in the Spellcheck Engine failing to retrieve hash-bucketed suggestions.

---

## Future Complex Languages (e.g., German)

German implementation differs fundamentally from English due to compound nouns and the Duden phoneme system. German engines should:
*   Supply a much more complex `GetPhoneticHash` that implements a modified Kölner Phonetik.
*   Update `ScoreWeights` heavily because keyboard proximity matters less on compound word typos than structural length disparity.
*   Register a unique set of `VariantRules` dealing with `ss`/`ß` and `ue`/`ü` permutations natively instead of only relying on exact matches.
