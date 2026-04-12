---
name: screenshot
description: Take one or more headless screenshots of a quickshell app, then display them in a new tmux pane using the kitty image protocol.
allowed-tools: Bash(nix run .#screenshot:*), Bash(nix run nixpkgs#timg:*), Bash(tmux:*)
---

Take screenshots using the headless screenshot app, then render them in a new tmux pane.

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

After capturing, open a new tmux pane and render the images there using timg with the kitty image protocol:

```bash
tmux split-window -h "tmux set-option -p allow-passthrough on && nix run nixpkgs#timg -- <paths...>; echo; read -rp ''"
```

- Pass all output paths from step 1 as arguments to timg
- `allow-passthrough` is set on the new pane so kitty graphics sequences reach the terminal
- The pane stays open until the user presses Enter

## Example (two comparison shots)

```bash
# Capture
nix run .#screenshot -- kh-launcher shot-a 'type chrm' -- shot-b "type 'chrm"
# → /tmp/qs-screenshots/20260412-140000/shot-a.png
# → /tmp/qs-screenshots/20260412-140000/shot-b.png

# Display
tmux split-window -h "tmux set-option -p allow-passthrough on && nix run nixpkgs#timg -- /tmp/qs-screenshots/20260412-140000/shot-a.png /tmp/qs-screenshots/20260412-140000/shot-b.png; echo; read -rp ''"
```
