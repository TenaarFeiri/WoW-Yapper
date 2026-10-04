# TODO

Nothing outstanding.

## Resolved

- Real-dictionary smoke suite: added `tools/2.0testsuites/test_dict_smoke.lua`
  (gating). Covers high-frequency word presence per shipped locale (enUS,
  enGB, enAU, deDE), affix-resolved forms, known typo->correction cases
  ("tihs"->"this", "doign"->"doing" [reshuffle starvation regression],
  "udn"->"und", "nihct"->"nicht"), and the every-word-suggestion-is-correct
  invariant. Loads real dicts + engines through the actual registration
  path, so a malformed or regressed dictionary generation fails the gate.
