# Window Inspector (`kh-window-inspector`)

Hyprland-only. Pick-first overlay over open windows; toggle to enter
pick mode (cursor-over-window draws an outline + floating tag), freeze
with `f`, open the details panel with `Enter` to copy / act on the
window. `Esc` cascades (closes details first, then the inspector); `q`
always closes the inspector.

## IPC

| Target | Functions / Properties |
|---|---|
| `window-inspector` | `toggle()`, `open()`, `close()`, `setMode(m)`, `key(k)`, `freeze()`, `unfreeze()`, `openDetails()`, `closeDetails()`, `copyRule(variant)`, `copyJson()`, `inspectActive()`, `inspectByAddress(addr)`, `inspectByPid(pid)` |
| | **Props:** `showing` -> bool, `mode` -> string (`pick` / `frozen`), `pickedAddress` -> string, `detailsShowing` -> bool |

```bash
qs ipc -c kh-window-inspector call window-inspector toggle
qs ipc -c kh-window-inspector call window-inspector inspectActive
qs ipc -c kh-window-inspector call window-inspector openDetails
qs ipc -c kh-window-inspector call window-inspector copyRule c
qs ipc -c kh-window-inspector prop get window-inspector pickedAddress
```

`copyRule(variant)` accepts `c` (initialClass), `t` (initialTitle), `p`
(pid), `a` (address), `w` (workspace), `m` (monitor). The emitted line
is `windowrulev2 = <action>, <matcher>` so you can fill in the action
on paste.

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
| `c` | Copy `windowrulev2` matching `initialClass` |
| `t` | Copy `windowrulev2` matching `initialTitle` |
| `p` | Copy `windowrulev2` matching `pid` |
| `a` | Copy `windowrulev2` matching `address` |
| `w` | Copy `windowrulev2` matching `workspace` |
| `m` | Copy `windowrulev2` matching `monitor` |
| `J` | Copy full `hyprctl clients -j` record as JSON |
| `Esc` | Close panel, return to pick/frozen mode |
| `q` | Close inspector entirely |
