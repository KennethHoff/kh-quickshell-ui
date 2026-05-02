# Window Inspector (`kh-window-inspector`)

Hyprland-only. Pick-first overlay over open windows; toggle to enter
pick mode (cursor-over-window draws an outline + floating tag), freeze
with `f`, open the details panel with `Enter` to navigate fields and
yank values. `Esc` cascades (closes details first, then the inspector);
`q` always closes the inspector.

## IPC

| Target | Functions / Properties |
|---|---|
| `window-inspector` | `toggle()`, `open()`, `close()`, `setMode(m)`, `key(k)`, `freeze()`, `unfreeze()`, `openDetails()`, `closeDetails()`, `selectNext()`, `selectPrev()`, `selectNextSection()`, `selectPrevSection()`, `toggleMark()`, `clearMarks()`, `yank()`, `inspectActive()`, `inspectByAddress(addr)`, `inspectByPid(pid)` |
| | **Props:** `showing` -> bool, `mode` -> string (`pick` / `frozen`), `pickedAddress` -> string, `detailsShowing` -> bool, `panelSelected` -> int, `panelMarkCount` -> int, `yankTick` -> int |

```bash
qs ipc -c kh-window-inspector call window-inspector toggle
qs ipc -c kh-window-inspector call window-inspector inspectActive
qs ipc -c kh-window-inspector call window-inspector openDetails
qs ipc -c kh-window-inspector call window-inspector selectNext
qs ipc -c kh-window-inspector call window-inspector yank
```

`yank()` copies whatever the highlighted row's *yank value* is. For
matcher-capable fields (initialClass / initialTitle / pid / address /
workspace / monitor) that's a `windowrulev2 = <action>, …` line; for
raw fields (live class/title, geometry) it's the displayed value.
`full record` yanks the full `hyprctl clients -j` JSON.

When one or more rows are marked (Yazi-style — `Space` toggles), `yank()`
copies the **union** instead: matcher-capable marked rows are AND'd
into a single `windowrulev2 = <action>, m1, m2` line so you can build
multi-matcher rules (e.g. `initialClass:^steam_app_0$, initialTitle:^Battle\.net$`)
in one keystroke. Marks reset on every `openDetails()`.

## Keybinds

### Pick / frozen mode

| Key | Action |
|---|---|
| `f` | Freeze / unfreeze the picked window |
| `Enter` | Open details panel for the picked window |
| `Esc` / `q` | Close inspector |

### Details panel

| Key | Action |
|---|---|
| `j` / `↓` | Next row |
| `k` / `↑` | Previous row |
| `l` / `→` | Jump to first row of next section |
| `h` / `←` | Jump to first row of current section, or previous section if already there |
| `Space` | Toggle mark on the highlighted row (Yazi-style multi-select) |
| `y` | Yank the highlighted row, or the union of marked rows if any |
| `Esc` | Close panel, return to pick/frozen mode |
| `q` | Close inspector entirely |
