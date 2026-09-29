# TODO

## Spellcheck engine: decouple English from core, enforce the language-engine contract

Core (`Src/Spellcheck*`) still assumes English throughout — the per-locale engine
slot (`RegisterLanguageEngine`, `Dictionaries/Yapper_Dict_*/Engine.lua`) was added
later and `en` was only a proof of concept. Before German (`deDE`) work starts:

- Core owns mechanics only: edit-distance scoring, suggestion ranking, caching,
  YAS feedback, dictionary lifecycle.
- Engine contract owns all language judgment: tokenisation, normalisation,
  casing rules, affix model, phonetics, word-shape validation.
- Extend the existing `_RegisterLanguageEngine` security check
  (`BlockedHashes`/`HashWord`) into a full contract check — required methods
  fail loudly at registration, no silent English fallbacks.
- Known English-isms to migrate: `NormaliseVowels` fallback, keyboard-distance
  layouts, affix/prefix assumptions, phonetic rules (see `tools/phonetics_en.py`
  vs `phonetics_de.py` groundwork).
- Acceptance test: `deDE` engine plugs in with zero changes to `Src/Spellcheck`.
  German stress cases: ä/ö/ü, ß↔ss folding, mandatory noun capitalization,
  compound nouns breaking strip-to-stem.

## Deferred from forever-support review (revisit after more in-game testing)

- Enter fallback commits unverifiable partial target when extractor returns nil
  (`Src/EditBox/Handlers.lua` ~L331).
- UnitPopup fallback not byte-identical to Blizzard's `GetFullPlayerName`
  (rare fallback-only paths).
- Retail intent matching can equate differing realm suffixes after
  normalisation (`20_EditBoxHooks.lua` ~L293).
- `Utils:IsForeverClient()` currently unused — keep or cut.
- Missing coverage: Enter-padding and nil-adoption paths.
