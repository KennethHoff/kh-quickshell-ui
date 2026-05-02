# Window Inspector (`kh-window-inspector`)

Hyprland-only. Pick-first overlay over open windows; toggle to enter pick
mode (cursor-over-window draws an outline + floating tag), freeze with
`f`, close with `Esc`/`q`.

Top-level keybinds are intentionally minimal — window actions and copy
variants will land in a details panel rather than the global keymap.

## IPC

| Target | Functions / Properties |
|---|---|
| `window-inspector` | `toggle()`, `open()`, `close()`, `setMode(m)`, `key(k)`, `freeze()`, `unfreeze()`, `inspectActive()`, `inspectByAddress(addr)`, `inspectByPid(pid)` |
| | **Props:** `showing` -> bool, `mode` -> string (`pick` / `frozen`), `pickedAddress` -> string |

```bash
qs ipc -c kh-window-inspector call window-inspector toggle
qs ipc -c kh-window-inspector call window-inspector inspectActive
qs ipc -c kh-window-inspector prop get window-inspector pickedAddress
```

## Keybinds (in pick / frozen mode)

| Key | Action |
|---|---|
| `f` | Freeze / unfreeze the picked window |
| `Esc` / `q` | Close inspector |
