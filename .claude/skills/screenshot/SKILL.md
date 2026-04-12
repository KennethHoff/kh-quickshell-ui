---
name: screenshot
description: Take one or more headless screenshots of a quickshell app, then display them using kh-view.
allowed-tools: Bash(nix run .#screenshot:*), Bash(nix run .#kh-view:*)
---

Take screenshots using the headless screenshot app, then display them with `kh-view`.

## Step 1 — Capture

```bash
nix run .#screenshot -- [--run <dir>] <app> <name> [<ipc-call>...] [-- <name> [<ipc-call>...]]...
```

- `--run <dir>` — reuse an existing run directory (useful for iterating on the same shot)
- `<app>` — a package name from `packages.x86_64-linux` in `flake.nix`; check the flake for the current list
- `<name>` — output filename without extension; saved to `<run-dir>/<name>.png`
- `<ipc-call>` — function name with optional argument, space-separated in a single string
- `--` — separates multiple shots; all shots share one sway instance and one run directory

The window is **opened automatically** (toggle is implicit) for each shot.

### IPC calls

| Call | Effect |
|---|---|
| `setView <view>` | Switch to a named view (e.g. `help`, `detail`) |
| `type <text>` | Type characters into the search box (one char at a time; `?` toggles help) |
| `nav down` / `nav up` | Move selection |
| `key escape` | Close / go back |

## Step 2 — Display

Open the screenshots using the pinned known-good kh-view commit. Pass all paths as arguments — they open side-by-side.

```bash
nix run "git+file://$PWD?rev=9859d176d4db#kh-view" -- <path1> [<path2> ...]
```

Update the pinned commit hash whenever kh-view reaches a new stable state.

## Example (two comparison shots)

```bash
# Capture
nix run .#screenshot -- kh-launcher shot-a 'type chrm' -- shot-b "type 'chrm"
# → /tmp/qs-screenshots/20260412-140000/shot-a.png
# → /tmp/qs-screenshots/20260412-140000/shot-b.png

# Display side-by-side
nix run "git+file://$PWD?rev=9859d176d4db#kh-view" -- /tmp/qs-screenshots/20260412-140000/shot-a.png /tmp/qs-screenshots/20260412-140000/shot-b.png
```
