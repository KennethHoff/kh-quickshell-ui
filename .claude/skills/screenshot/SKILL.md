---
name: screenshot
description: Take a headless screenshot of kh-launcher or kh-cliphist using the nix screenshot app, then display it inline.
allowed-tools: Bash(nix run .#screenshot:*), Read
---

Take a screenshot using the headless screenshot app, then read and display the result.

## Command

```bash
nix run .#screenshot -- [--run <dir>] <app> <name> [<ipc-call>...]
```

- `--run <dir>` — optional; reuse an existing run directory so multiple shots land in the same folder. If omitted, a new timestamped directory is created.
- `<app>` — a package name from `packages.x86_64-linux` in `flake.nix` (e.g. `kh-launcher`, `kh-cliphist`); check the flake for the current list
- `<name>` — output filename without extension; saved to `<dir>/<name>.png`
- `<ipc-call>` — each argument is a function name with an optional argument, space-separated in a single string

The window is **opened automatically** (toggle is implicit). Only pass calls beyond the initial open.

## Taking multiple related screenshots

When taking more than one screenshot for comparison, share a run directory so all shots land in the same folder. Capture the directory from the first call's output path and pass it via `--run` to subsequent calls:

```bash
# First shot — note the run dir from the output path
nix run .#screenshot -- kh-launcher shot-a 'type chrm'
# → /tmp/qs-screenshots/20260412-140000/shot-a.png

# Subsequent shots — reuse the same dir
nix run .#screenshot -- --run /tmp/qs-screenshots/20260412-140000 kh-launcher shot-b "type 'chrm"
```

## IPC calls

| Call | Effect |
|---|---|
| `setView <view>` | Switch to a named view (e.g. `help`, `detail`) |
| `type <text>` | Type characters into the search box (one char at a time; `?` toggles help) |
| `nav down` / `nav up` | Move selection |
| `key escape` | Close / go back |

## Example

```bash
nix run .#screenshot -- kh-launcher launcher-help-workspace 'setView help' 'type workspace'
```

## After running

Read the output path printed to stdout and display the image using the Read tool.
