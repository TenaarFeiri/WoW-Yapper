# TODO

## Awaiting an answer

Should we add a real-dictionary smoke suite to the gating tests?

Shared harness loading each shipped dictionary + engine, with a
per-language typo->expected case table (enUS: "tihs" -> "this",
"doign" -> "doing"; deDE needs a QWERTZ-appropriate pair). The
reshuffle-starvation bug ("doign" never generating "doing") survived
because no gating test drove the full suggestion pipeline against a real
dictionary -- this would close that hole.

Answer: yes / no / later.
