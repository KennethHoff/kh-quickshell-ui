---
name: screenshot
description: Take one or more headless screenshots of a quickshell app, with optional tmux + kitty integration to display them inline.
allowed-tools: Bash(nix run .#screenshot:*), Bash(tmux:*), Bash(kitty:*)
---

Take screenshots using the headless screenshot app. If running inside tmux with a kitty terminal, display them inline; otherwise just report the file paths.

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

## Step 2 — Display (optional, requires tmux + kitty)

If running inside tmux with a kitty-compatible terminal, open a new pane in the **current window** and render the images there using `kitty +kitten icat`. Otherwise, skip this step and report the screenshot file paths to the user.

```bash
PANE=$(tmux split-window -h -P -F '#{pane_id}') && tmux send-keys -t "$PANE" 'tmux set-option -p allow-passthrough on && for f in <paths...>; do echo "$(basename $f .png)"; tmp=$(mktemp /tmp/icat-XXXXXX.png); nix run nixpkgs#imagemagick -- "$f" -resize x320 "$tmp" 2>/dev/null; kitty +kitten icat "$tmp"; rm "$tmp"; done' Enter
```

- Capture the new pane ID with `-P -F '#{pane_id}'` so `send-keys` targets it precisely
- `allow-passthrough` is set on the new pane so kitty graphics sequences reach the terminal
- Each image is resized to 320px tall via ImageMagick so multiple shots fit on screen without scrolling
  - Note: `kitty +kitten icat --place` uses absolute screen coordinates and breaks inside a tmux pane
- Each image is preceded by its name (filename without extension) as a label
- After sending the command, read the pane with `tmux capture-pane -p -t "$PANE"` to verify rendering before reporting back

## Example (two comparison shots)

```bash
# Capture
nix run .#screenshot -- kh-launcher shot-a 'type chrm' -- shot-b "type 'chrm"
# → /tmp/qs-screenshots/20260412-140000/shot-a.png
# → /tmp/qs-screenshots/20260412-140000/shot-b.png

# Display
PANE=$(tmux split-window -h -P -F '#{pane_id}') && tmux send-keys -t "$PANE" 'tmux set-option -p allow-passthrough on && for f in /tmp/qs-screenshots/20260412-140000/shot-a.png /tmp/qs-screenshots/20260412-140000/shot-b.png; do echo "$(basename $f .png)"; tmp=$(mktemp /tmp/icat-XXXXXX.png); nix run nixpkgs#imagemagick -- "$f" -resize x320 "$tmp" 2>/dev/null; kitty +kitten icat "$tmp"; rm "$tmp"; done' Enter
```
