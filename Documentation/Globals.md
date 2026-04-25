# Global surface quick reference

## `_G.Yapper`

- Global addon namespace; set in [`Yapper.lua#L64`](../Yapper.lua#L64).
- It is the same table passed as `YapperTable` to all `Src/*.lua` modules.
- Full internal reference: [Internals.md](Internals.md).

## `_G.YapperAPI`

- Public integration API created in [`Src/API.lua#L540-L543`](../Src/API.lua#L540-L543).
- Full public reference: [API.md](API.md).

## SavedVariables globals

These are guaranteed only after Yapper handles `ADDON_LOADED`:

- `_G.YapperDB` (account-wide) — initialised in [`Src/Core.lua#L362`](../Src/Core.lua#L362).
- `_G.YapperLocalConf` (per-character config) — initialised in [`Src/Core.lua#L363`](../Src/Core.lua#L363).
- `_G.YapperLocalHistory` (per-character history/drafts) — initialised in [`Src/Core.lua#L364`](../Src/Core.lua#L364).

See SavedVariables layout in [Architecture.md](Architecture.md#savedvariables-layout).

## Other `_G.*` registrations and mutations

- `_G.YAPPER_UTILS = Utils` for debug/dev access ([`Src/Utils.lua#L94`](../Src/Utils.lua#L94)).
- `_G.ChatEdit_InsertLink` is replaced by overlay-aware compatibility logic ([`Src/EditBoxCompat.lua#L86`](../Src/EditBoxCompat.lua#L86)).
- `function Yapper_FromCompartment(...)` creates `_G.Yapper_FromCompartment` implicitly ([`Src/Interface.lua#L789`](../Src/Interface.lua#L789)).

## Slash commands

Declared in [`Yapper.lua#L68-L102`](../Yapper.lua#L68-L102):

- `/yapper`
  - no args / `toggle` → toggle settings window
  - `open` / `show` → show settings window
  - `close` / `hide` → close settings window
  - `help` / `?` → open Help page

## Key bindings

From [`Bindings.xml`](../Bindings.xml):

- `Bypass Yapper` (default `SHIFT-ENTER`) → calls `Yapper.EditBox:OpenBlizzardChat()`.

Commented/NYI bindings exist in `Bindings.xml` but are not registered live.
