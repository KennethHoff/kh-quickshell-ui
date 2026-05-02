# QML structure

## How an app is structured

Each app is a single `ShellRoot` with:

```
ShellRoot (root)
  NixConfig { id: cfg }   ← colors + font (generated at build time)
  NixBins   { id: bin }   ← absolute store-path binaries
  <lib components>        ← imported from ./lib
  <state properties>      ← showing, view, helpFilter, etc.
  IpcHandler              ← external control via quickshell ipc call
  WlrLayershell (win)     ← the actual window
    <UI tree>
```

## Views

Both apps use a `property string view` to switch between named views. The active view controls which content is visible via `visible: root.view === "..."`. Check the top of each file for the current list of valid view names.

## Styling

All styling flows through `cfg` (the `NixConfig` instance):

- `cfg.color.baseXX` — colors from the configured palette (base00 = darkest, base05 = primary text, higher = accents)
- `cfg.fontFamily` — applied to all text elements
- `cfg.fontSize` — base font size in pixels; secondary and hint text uses small negative offsets (e.g. `cfg.fontSize - 2`)

Never hardcode colors or font sizes — always derive from `cfg`.

## Help overlay

Both apps define the help overlay as an inline `Column` with two inline components:

- **`ShortcutRow`** — one row: shortcut (right-aligned fixed width) + description. Filtered by `root.helpFilter`.
- **`SectionLabel`** — section heading, hidden when `helpFilter` is active.

## IPC

Apps are controlled externally via `quickshell ipc call <target> <function>`. Each app declares an `IpcHandler` with a `target` string and functions for `toggle`, `setView`, `nav`, `type`, and `key`. The `headless` skill uses these to set up UI state, which the `screenshot` skill then captures.
