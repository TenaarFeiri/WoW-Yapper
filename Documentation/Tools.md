# Developer Tools

Maintenance and verification tools for the Yapper repository. Unless noted
otherwise, commands are run from the repository root. On Windows, `py -3` can
be used in place of `python3`.

## Verification

### `tools/run_tests.sh`

Runs the repository gate:

```sh
tools/run_tests.sh
```

The runner performs these phases:

1. Syntax-checks every shipped Lua file in the repository root, `Src/`, and
   `Dictionaries/` with `luac -p`.
2. Checks documentation line references with `tools/check_doc_refs.py` when
   `python3` is available.
3. Runs the gating suites listed in `GATING_FROM_ROOT` and
   `GATING_FROM_SUITEDIR`.
4. Runs `tools/contract-tests/run.sh`.

Use `--syntax` to run only the Lua syntax phase:

```sh
tools/run_tests.sh --syntax
```

The `LUA` and `LUAC` environment variables select the interpreters. CI runs
with Lua 5.1:

```sh
LUA=lua5.1 LUAC=luac5.1 tools/run_tests.sh
```

The gating-suite manifest and classifications are documented in
`tools/2.0testsuites/README.md`. Diagnostic and quarantined suites are not run
by the default gate.

### Chat contract tests

```sh
tools/contract-tests/run.sh
```

Runs the deterministic fake WoW runtime/server tests independently. The runner
syntax-checks the contract fixtures before executing them. `tools/run_tests.sh`
also runs this suite.

## Documentation

### `tools/sync.sh`

Release-oriented wrapper for the documentation synchronizer:

```sh
tools/sync.sh
```

It runs `sync_all_docs.py --inject`.

### `tools/sync_all_docs.py`

Synchronizes source line references in `Documentation/*.md` and optionally
injects newly discovered public methods:

```sh
python3 tools/sync_all_docs.py
python3 tools/sync_all_docs.py --inject
```

Without `--inject`, existing links are updated and ambiguous links are
reported. With `--inject`, undocumented methods are added with a `[NEW]`
marker for review. The synchronizer does not replace that review step.

### `tools/check_doc_refs.py`

Read-only documentation reference checker:

```sh
python3 tools/check_doc_refs.py
```

It verifies `#L<n>` links in `Documentation/*.md` and exits non-zero for
confident drift. `--fix` relocates references when exactly one matching source
definition exists; ambiguous references remain for manual review:

```sh
python3 tools/check_doc_refs.py --fix
```

### `tools/sync_api_docs.py`

API-only synchronizer for `YapperAPI:*` links in `Documentation/API.md`:

```sh
python3 tools/sync_api_docs.py
```

The general `sync_all_docs.py` workflow is the release-time synchronizer.

### Synchronizer regression tests

```sh
python3 tools/test_sync_all_docs.py
```

Tests symbol resolution and ambiguity handling in the documentation
synchronizer and reference checker.

## Dictionary management

### `tools/generate_phonetic_dict.py`

Regenerates the English dictionary base and locale deltas:

```sh
python3 tools/generate_phonetic_dict.py
```

The script scans English dictionaries under `Dictionaries/Yapper_Dict_en*`,
excluding `Engine.lua`. It computes the shared `enBase` word set, writes
`Dictionaries/Yapper_Dict_en/Dict_enBase.lua`, and rewrites each locale file as
a delta extending `enBase`. Phonetic hashes are generated with
`tools/phonetics_en.py`.

Generated dictionaries must pass the syntax phase of `tools/run_tests.sh`.

### `tools/sanitize_dictionaries.py`

Removes words matching the sanitization list from every
`Dictionaries/Yapper_Dict_*` dictionary, creates or updates each dictionary's
`backup/` directory, and rewrites the dictionary with phonetics cleared.

The script uses paths relative to `tools/`, so run it from that directory:

```sh
cd tools
python3 sanitize_dictionaries.py
```

The input list is `tools/scratch/filtered-word-lists/bad-word-list-full`.
Run `generate_phonetic_dict.py` afterward to regenerate phonetic tables.

### `tools/import_wooorm.py`

Converts a wooorm/Hunspell `.dic` and `.aff` pair into a Yapper dictionary:

```sh
python3 tools/import_wooorm.py \
  --locale enGB \
  --family en \
  --dic path/to/dictionary.dic \
  --aff path/to/dictionary.aff \
  --base Dictionaries/Yapper_Dict_en/Dict_enBase.lua
```

`--base` is optional. When supplied, only words not present in the base are
written and the output is marked as a delta. The output path is selected by the
script as `Dictionaries/Yapper_Dict_<locale>/Dict_<locale>.lua`.

The conversion requires the `unmunch` command from `hunspell-tools` and a
matching `tools/phonetics_<family>.py` module.

## Blocklist management

### `tools/generate_blocklist.py`

Reads a newline-delimited text file or CSV, normalizes each value, and prints a
DJB2 hash table to standard output:

```sh
python3 tools/generate_blocklist.py path/to/words.txt > blocked_hashes.lua
```

Copy the generated `BLOCKED_HASHES` table into the target language engine's
`BlockedHashes` field. The current English engine is
`Dictionaries/Yapper_Dict_en/Engine.lua`.

## Static audits

### `tools/find_orphans.py`

Performs a regex-based structural audit of production Lua sources and reports
function/variable definitions with no additional references. It skips `tools/`,
`scratch/`, `.release/`, dictionary `backup/` directories, and test/fixture
directories. It also reports a small British-English naming consistency check:

```sh
python3 tools/find_orphans.py
```

### `tools/dead_code_scanner.py`

Performs a TOC-aware static analysis of Lua symbols, table members, undefined
references, and likely dead code:

```sh
python3 tools/dead_code_scanner.py
```

Options:

- `--path PATH` / `-p`: directory to scan; default `Src`
- `--toc PATH` / `-t`: TOC load-order file; default `Yapper.toc`
- `--verbose` / `-v`: include low-confidence findings
- `--output PATH` / `-o`: report path; default `dead_code_report.md`
- `--no-cache`: rebuild the WoW API cache

When a `wow-ui-source` checkout is available, the scanner uses it to build the
WoW API whitelist. The cache is stored in `.wow_api_cache.json`.

## Release packaging

### `tools/release.sh`

Bash release builder:

```sh
./tools/release.sh
```

It reads the version from `Yapper.toc`, runs `tools/sync.sh`, recreates
`.release/`, stages the core addon under `.release/stage/Yapper/`, copies the
English dictionary addons (`Yapper_Dict_en`, `Yapper_Dict_enAU`,
`Yapper_Dict_enGB`, and `Yapper_Dict_enUS`), and writes:

```text
.release/Yapper-<version>.zip
```

The script does not increment the version. `Yapper_Dict_deDE` is not included
by the current release configuration.

### `tools/release.ps1`

PowerShell release builder for Windows:

```powershell
.\tools\release.ps1
```

It performs the same staging and packaging flow, resolves a non-Windows-Store
Python executable for documentation synchronization, and writes the same
`.release/Yapper-<version>.zip` naming scheme. The PowerShell implementation
also includes `Changelogs.md` in the core addon package; the Bash allowlist does
not currently include it.

## Package layout

The release contains sibling addons so Blizzard can load dictionaries on
demand:

```text
AddOns/
├── Yapper/
│   ├── Src/
│   ├── Yapper.lua
│   ├── Yapper.toc
│   └── ...
├── Yapper_Dict_en/
├── Yapper_Dict_enAU/
├── Yapper_Dict_enGB/
└── Yapper_Dict_enUS/
```

The core addon registers dictionaries through `YapperAPI`; dictionary addons are
separate top-level folders rather than subdirectories of `Yapper`.
