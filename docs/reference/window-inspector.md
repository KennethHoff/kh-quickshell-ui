# Window Inspector (`kh-window-inspector`)

Hyprland-only. Pick-first overlay over open windows; toggle to enter pick
mode (cursor-over-window draws an outline + floating tag), freeze with
`f`, copy a `windowrulev2` line with `y` + variant.

## IPC

| Target | Functions / Properties |
|---|---|
| `window-inspector` | `toggle()`, `open()`, `close()`, `setMode(m)`, `key(k)`, `freeze()`, `unfreeze()`, `inspectActive()`, `inspectByAddress(addr)`, `inspectByPid(pid)`, `focusWindow()`, `closeWindow()`, `toggleFloating()`, `togglePinned()`, `moveToWorkspace(n)` |
| | **Props:** `showing` -> bool, `mode` -> string (`pick` / `frozen`), `pickedAddress` -> string |

```bash
qs ipc -c kh-window-inspector call window-inspector toggle
qs ipc -c kh-window-inspector call window-inspector inspectActive
qs ipc -c kh-window-inspector prop get window-inspector pickedAddress
```

## Keybinds (in pick mode)

| Key | Action |
|---|---|
| `f` | Freeze / unfreeze the picked window |
| `?` | Toggle help overlay |
| `Esc` / `q` | Close inspector |
| `y` | Copy `windowrulev2` (default: `initialClass`) — chord with `c`/`t`/`p`/`a`/`w`/`m` |
| `Y` | Copy full `hyprctl clients -j` record as JSON |
| `X` | Close window |
| `F` | Focus window |
| `t` / `T` | Toggle floating / pinned |
| `m1`–`m9` | Move window to workspace 1–9 |
