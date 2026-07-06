# Yapper test suites

Run everything that gates a commit with:

```
tools/run_tests.sh
```

CI (`.github/workflows/tests.yml`) runs the same script on every push/PR
using Lua 5.1, which matches WoW's runtime semantics. The gating manifest
lives in `tools/run_tests.sh` — that script is the single source of truth
for what must pass.

## Categories

### Gating tests (run by `run_tests.sh` and CI)

These load **real `Src/` modules** under a mocked WoW environment, assert,
and exit non-zero on failure.

| Suite | Covers | cwd |
|---|---|---|
| test_state | State machine transitions | repo root |
| test_utils | Utils helpers | repo root |
| test_history | Draft/history persistence | repo root |
| test_migrations | SavedVariables migrations | repo root |
| test_router | Chat routing / BNet resolution | repo root |
| test_chunking | Message chunking | repo root |
| test_emotes | Emote picker | repo root |
| test_channel_policy_chat_modes | Open-selection policy | repo root |
| test_channel_policy_stress_sim | Policy stress (seeded RNG) | repo root |
| test_editbox_pipeline_stress_sim | Pipeline stress (seeded RNG) — see caveat | repo root |
| test_icon_gallery_api | Icon gallery API | repo root |
| test_queue_stall | Queue + real State machine, stall/ack/cancel | repo root |
| test_lockdown_fsm | Lockdown handoff FSM, focus-override lifecycle | repo root |
| test_api_error | Error API | suite dir |
| test_api_features | Public API surface | suite dir |
| test_yallm_logic | Adaptive spellcheck (YAS) core logic | suite dir |
| test_yallm_extended | YAS refactor coverage | suite dir |
| test_yallm_pruning_decay_pipeline | YAS pruning/decay/end-to-end | suite dir |
| test_autocomplete_api | Autocomplete suggestion API | suite dir |

**Caveat:** the two `*_stress_sim` suites partially *reimplement* pipeline
logic locally rather than loading all of it from `Src/`. They validate the
intended semantics (and are seeded, so deterministic), but a drift in
`Src/EditBox/Handlers.lua` will not necessarily fail them. Treat them as
executable specifications, not regression nets.

### Diagnostic harnesses (run manually; never gate)

Measure and report rather than assert.

- `test_editbox_pipeline_adversarial_fault_injection` — fault-injection
  campaign; prints divergence/recovery stats to prioritise mitigations.
- `test_editbox_pipeline_breakpoint_sweep` — parameter sweep (~4 s).
- `test_cache_optimization` — cache benchmark (~8 s).
- `word_game` / `word_game_auto` — interactive/automated spellcheck toys.

### Quarantined (broken by source drift; do not gate until repaired)

All broke when their mocks fell behind `Src/` refactors, most notably the
Spellcheck hub/Engine/Dictionary LOD split and the `YAS.lua` →
`Adaptive.lua` rename. Each needs its environment stubs modernised the way
`test_queue_stall` and the two `test_yallm_*` suites were in July 2026.

- `test_breakdown`, `test_breakdown_de`, `test_breakdown_de_warm`,
  `test_production`, `test_moby_dick_adversarial`,
  `test_moby_dick_noisy_env`, `test_moby_dick_profanity`,
  `test_moby_dick_stress`, `test_moby_german_extreme`
  — crash in `Engine.lua` (`GetMaxCandidates` missing from their env).
- `test_spam_cannon`, `test_cache_stress`
  — load the deleted `Src/Spellcheck/YAS.lua` (now `Adaptive.lua`).
- `test_spellcheck_en_variant_inheritance`, `test_gc_dictionary_lifecycle`
  — `Dictionary.lua` now requires `GetEngine` (Engine LOD split).
- `test_autocomplete_sim` — `GetPhoneticHash` moved/renamed.
- `test_german_harness` — dictionary registry drift; also a diagnostic
  (typist simulator) rather than a strict test.

## Conventions

- New tests: follow the `check()`/counter house style, load real `Src/`
  modules, print a `Results: N/M passed` footer, and `os.exit(1)` on any
  failure. Run from the **repo root** and use `loadfile("Src/...")`.
- Add new gating suites to the manifest in `tools/run_tests.sh`.
- The syntax phase of `run_tests.sh` (`luac -p` over every shipped `.lua`,
  dictionaries included) exists because a generated dictionary once shipped
  with a syntax error and failed silently in-game. Keep it.
