# Chat contract tests

These suites exercise Yapper's real chat pipeline against a deterministic fake WoW
runtime and fake server. They are intentionally separate from the smaller unit
suites in `tools/2.0testsuites/`.

Run from the repository root:

```sh
tools/contract-tests/run.sh
```

The normal project gate runs this script too:

```sh
tools/run_tests.sh
```

## What this models

- Router dispatch and target preservation across standard, whisper, BNet,
  channel, guild, officer, raid, and party sends.
- Canonical message handling, including legacy and modern named-colour links.
- Link-aware chunking through the real `Chunking` module.
- Queue ordering, delayed acknowledgements, silent drops, stalls, requeues,
  continuation prompts, cancellation, hard API errors, and hardware-gated
  open-world sends.
- Strict acknowledgement text checks and rejection of unrelated event types.

## What the fake server does not claim

The UI source cannot establish production server throttle limits, burst sizes,
latency guarantees, or whether a specific server-side rejection emits an event.
The fake server therefore exposes explicit outcomes (`echo`, `delayed`, `drop`,
`wrong-text`, `wrong-event`, and `error`) so client-side invariants are tested
without encoding guesses about server internals.

## Extension rules

- Load real `Src/` modules whenever the contract is about Yapper behaviour.
- Keep the fake runtime deterministic; advance timers explicitly.
- Add fixtures for every newly observed WoW link or chat event shape.
- Test both the success path and the absence/delay of the expected server echo.
- Do not turn a server unknown into a production assumption merely to make a
  test pass.
