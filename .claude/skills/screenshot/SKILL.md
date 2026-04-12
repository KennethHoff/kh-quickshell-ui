---
name: screenshot
description: Take one or more headless screenshots of a quickshell app using the nix screenshot app, then display them inline.
allowed-tools: Bash(nix run .#screenshot:*), Read
---

Take screenshots using the headless screenshot app, then read and display the results.

## Command

```bash
nix run .#screenshot -- <app> <name> [<ipc-call>...] [-- <name> [<ipc-call>...]]...
```

- `<app>` — a package name from `packages.x86_64-linux` in `flake.nix`; check the flake for the current list
- `<name>` — output filename without extension; saved to `/tmp/qs-screenshots/<timestamp>/<name>.png`
- `<ipc-call>` — function name with optional argument, space-separated in a single string
- `--` — separates multiple shots; all shots share one sway instance and one run directory

The window is **opened automatically** (toggle is implicit) for each shot. Only pass calls beyond the initial open.

## IPC calls

| Call | Effect |
|---|---|
| `setView <view>` | Switch to a named view (e.g. `help`, `detail`) |
| `type <text>` | Type characters into the search box (one char at a time; `?` toggles help) |
| `nav down` / `nav up` | Move selection |
| `key escape` | Close / go back |

## Examples

Single shot:
```bash
nix run .#screenshot -- kh-launcher launcher-help 'setView help'
```

Multiple related shots in one run:
```bash
nix run .#screenshot -- kh-launcher shot-a 'type chrm' -- shot-b "type 'chrm"
```

## After running

Read each output path printed to stdout and display the images using the Read tool.
