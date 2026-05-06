# Developer Tools

This document describes the Python and Shell tools used to maintain the Yapper codebase, generate dictionaries, and manage documentation.

## Dictionary Management

### `sanitize_dictionaries.py`
Strips offensive words and slurs from all regional Lua dictionaries based on a provided word list.
- **Usage**: `python3 sanitize_dictionaries.py`
- **Logic**:
  - Scans all `Dictionaries/Yapper_Dict_*` directories.
  - Loads bad words from `tools/scratch/all_bad_words.txt`.
  - Backs up original dictionaries to `backup/`.
  - Filters words and writes sanitized `.lua` files (with phonetics cleared, requiring a re-run of `generate_phonetic_dict.py`).

### `generate_phonetic_dict.py`
Regenerates the phonetic lookup tables for all English-family dictionaries.
- **Usage**: `python3 generate_phonetic_dict.py`
- **Logic**:
  - Scans `Dictionaries/Yapper_Dict_en*`.
  - Calculates a "Universal Base" of words shared across all locales (stored in `enBase`).
  - Generates delta dictionaries for regional variants (`enGB`, `enAU`, `enUS`) containing only the locale-specific words.
  - Applies language-specific phonetic hashing (via `phonetics_en.py`).

### `import_wooorm.py`
Imports and converts [wooorm/dictionaries](https://github.com/wooorm/dictionaries) (Hunspell format) into Yapper's optimized Lua format.
- **Usage**: `python3 import_wooorm.py --locale enGB --family en --dic path/to.dic --aff path/to.aff --base Dict_enBase.lua`
- **Requirements**: Requires the `unmunch` command (from `hunspell-tools`).

---

## Blocklist Management

### `generate_blocklist.py`
Generates the DJB2 hash table used by the engine to identify and filter blocked words without storing the plain text of the words in the addon.
- **Usage**: `python3 generate_blocklist.py path/to/words.txt`
- **Normalization**: The tool automatically normalizes words (lowercase, stripping punctuation) before hashing to ensure consistent detection.
- **Integration**: The output table should be copied into `Dictionaries/Yapper_Dict_en/Engine.lua`.

---

## Documentation & Auditing

### `sync_all_docs.py`
Maintains the integrity of documentation by synchronizing line numbers in markdown files with the actual source code.
- **Usage**: `python3 sync_all_docs.py [--inject]`
- **Features**:
  - Updates `#LNNN` links in all `.md` files.
  - `--inject`: Automatically finds undocumented public methods and adds them to `Internals.md` or `API.md` with summaries extracted from Lua comments.

### `find_orphans.py`
Performs a structural audit of the Lua codebase to find unused functions, variables, and potential linguistic inconsistencies.
- **Usage**: `python3 find_orphans.py`
- **Verification**: Includes a "Linguistic Sync" check to ensure consistent British English naming (e.g., `NormaliseWord` vs `NormalizeWord`).

## Repository Structure

To ensure that `release.sh` and other maintenance tools function correctly, the development repository must follow this specific layout:

```text
. (Root)
├── Dictionaries/          (Source for LOD dictionaries)
│   ├── Yapper_Dict_en/
│   ├── Yapper_Dict_enGB/
│   └── ...
├── Documentation/         (Markdown documentation files)
├── Src/                   (Core Lua source code)
├── tools/                 (Python/Shell maintenance tools)
│   └── scratch/           (Working files for slurs and blocklists)
├── Bindings.xml
├── Changelogs.md
├── Yapper.lua             (Main entry point)
├── Yapper.toc             (Main TOC file - contains version info)
└── ...
```

---

## Release Workflow

### `release.sh`
The primary build script for packaging Yapper for distribution.
- **Usage**: `./tools/release.sh`
- **Workflow**:
  1. Runs `sync_all_docs.py` to ensure documentation is accurate.
  2. Increments version numbers where applicable.
  3. Packages `Yapper` and all `Yapper_Dict_*` folders into a `.release/Yapper-vX.Y.Z.zip` bundle.

### Expected Installation Layout
Yapper is a modular addon. To ensure the Load-on-Demand (LOD) dictionary system functions correctly, the following directory structure is expected in the WoW `Interface/AddOns/` folder:

```text
AddOns/
├── Yapper/               (Core engine, UI, and logic)
├── Yapper_Dict_en/       (Universal English Base + Phonetic Engine)
├── Yapper_Dict_enGB/      (British English Delta)
├── Yapper_Dict_enUS/      (American English Delta)
└── Yapper_Dict_...       (Other regional/language deltas)
```

**Note**: The dictionaries are separate top-level folders to allow WoW to load them individually only when the specific locale is active.
