---
name: headless
description: Drive the persistent NixOS microvm running the quickshell apps (kh-bar, kh-launcher, kh-cliphist, kh-osd, kh-window-inspector, kh-view) via the `kh-headless` host CLI — load configs, invoke IPC methods, read/write properties, list targets, inspect IPC surfaces. Use to swap an app's config in the VM, set up UI state, or poke at IPC from the host. For screenshot capture, see the `screenshot` skill.
allowed-tools: Bash, Read
---

# Headless skill

Drives a persistent VM running Hyprland on a vkms virtual DRM device.
The host-side `kh-headless` CLI sends primitive operations over a
virtiofs share. Harness inside VM dispatches them.

## Prerequisite: daemon must be running

Every command below assumes one daemon alive:

```bash
nix run .#kh-headless-daemon
```

Boots VM, holds foreground; Ctrl-C tears down. Daemon writes
`/tmp/kh-headless/state/daemon.pid` as a lock and refuses to start a
second instance.

If `nix run .#kh-headless` reports `daemon not ready (no
/tmp/kh-headless/state/ready)`, start daemon in a separate terminal
first.

## Primitive ops

Whole API driven by `nix run .#kh-headless --`:

| Op | Args | Effect |
|---|---|---|
| `load` | `<config-store-path>` | Kill+respawn quickshell with that config. |
| `kill` | — | Stop quickshell. |
| `call` | `<target> <method> [args...]` | Invoke an IPC method. |
| `prop` | `<target> <prop> [<value>]` | Read (no value) or write a prop. |
| `show` | `[<target>]` | Print IPC surface — every method/prop on every target. Filters when given a target. |
| `list` | — | Target names, one per line. |
| `grim` | `"<x,y wxh>" [name]` | Capture a screen region. See the `screenshot` skill. |
| `status` | — | `running <config>` or `idle`. |

For multi-call loops, resolve the binary once instead of `nix run` per
call:

```bash
khh=$(nix eval --raw .#apps.x86_64-linux.kh-headless.program)
"$khh" load "$cfg"
"$khh" call testbar.stats open
```

## Discovery flow

```bash
cfg=$(nix build .#kh-bar-headless --no-link --print-out-paths)
nix run .#kh-headless -- load "$cfg"
nix run .#kh-headless -- list                 # find testbar.* targets
nix run .#kh-headless -- show testbar.volume  # methods on volume tile
nix run .#kh-headless -- call testbar.volume setMuted true
```

## App config table

| App | Test config package | IPC target prefix |
|---|---|---|
| kh-bar | `.#kh-bar-headless` | `testbar` (root) + `testbar.<plugin>`, dropdowns: `testbar.stats`, `testbar.controlcenter` |
| kh-cliphist | `.#kh-cliphist` | `cliphist` (`toggle`) — dev config doubles as test config |
| kh-launcher | `.#kh-launcher-headless` | `launcher` (`toggle`, `activatePlugin <name>`, `type`, `key`) — plugins (lowercase): `apps`, `emoji`, `hyprland-windows` |
| kh-osd | `.#kh-osd` | `osd` (`showVolume <N>`, `showMuted`) |
| kh-window-inspector | `.#kh-window-inspector` | `window-inspector` (`toggle`) |
| kh-view | `.#kh-view` | — display target for `show-image` skill |

For most apps the dev config = test config. `kh-bar` and `kh-launcher`
need overrides — the `-headless` variants pin `screen = "Virtual-1"`
and wire fixtures for plugins that depend on real desktop state.
