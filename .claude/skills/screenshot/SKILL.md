---
name: screenshot
description: Take a headless screenshot of kh-launcher or kh-cliphist using the nix screenshot app, then display it inline.
allowed-tools: Bash(nix run .#screenshot:*), Read
---

Take a screenshot using the headless screenshot app, then read and display the result.

## Command

```bash
nix run .#screenshot -- <app> <name> [<ipc-call>...]
```

- `<app>` — a package name from `packages.x86_64-linux` in `flake.nix` (e.g. `kh-launcher`, `kh-cliphist`); check the flake for the current list
- `<name>` — output filename without extension; saved to `/tmp/qs-screenshots/<timestamp>/<name>.png`
- `<ipc-call>` — each argument is a function name with an optional argument, space-separated in a single string

The window is **opened automatically** (toggle is implicit). Only pass calls beyond the initial open.

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
