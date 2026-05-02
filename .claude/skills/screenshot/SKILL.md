---
name: screenshot
description: Capture headless screenshots of a quickshell app (kh-bar, kh-launcher, kh-cliphist, kh-osd, kh-window-inspector, kh-view) by driving a persistent NixOS microvm via the kh-headless host CLI. Use when the user asks for a screenshot / "take a shot", for visual verification after .qml or theme changes, to debug UI regressions, to compare revisions side-by-side ("it worked earlier" / "why does this look different"), or to compare multiple unimplemented variations/plans ("screenshot all three designs"). This skill only captures — to display the captured shots back to the user, use the separate `show-image` skill.
allowed-tools: Bash, Read
---

# Screenshot skill

Screenshots come from a persistent VM running Hyprland on a vkms virtual
DRM device. The host-side `kh-headless` CLI sends primitive operations
(load / call / prop / show / list / grim / status / kill) over a virtiofs
share. The harness inside the VM dispatches them.

Output files are written to `/tmp/kh-headless/out/<name>` by the harness;
client commands echo absolute paths back. Move them to a timestamped
subdir under `/tmp/qs-screenshots/<ts>/` if you want the historical
on-disk convention.

## Default behaviour

After capture, print the file paths back to the user. Do **not** open
`kh-view` — paths alone are enough. If the user asks to see the shots
("show me", "open them", "view the screenshots"), hand off to the
`show-image` skill.

## Prerequisite: the daemon must be running

Every command below assumes one daemon is alive:

```bash
nix run .#kh-headless-daemon
```

It boots the VM and holds the foreground; Ctrl-C tears down. The
daemon writes `/tmp/kh-headless/state/daemon.pid` as a lock and
refuses to start a second instance.

If `nix run .#kh-headless` reports `daemon not ready (no
/tmp/kh-headless/state/ready)`, start the daemon in a separate
terminal first.

## Primitive flow

The whole API is six operations driven by `nix run .#kh-headless --`:

| Op | Args | Effect |
|---|---|---|
| `load` | `<config-store-path>` | Kill+respawn quickshell with that config. |
| `kill` | — | Stop quickshell. |
| `call` | `<target> <method> [args...]` | Invoke an IPC method. |
| `prop` | `<target> <prop> [<value>]` | Read (no value) or write a prop. |
| `show` | `[<target>]` | Print IPC surface — every method/prop on every target. Filters when given a target. |
| `list` | — | Just target names (one per line). |
| `grim` | `"<x,y wxh>" [name]` | Capture region. Returns absolute host path. |
| `status` | — | `running <config>` or `idle`. |

Discovery flow ("screenshot kh-bar with the volume muted"):

```bash
cfg=$(nix build .#kh-bar-headless --no-link --print-out-paths)
nix run .#kh-headless -- load "$cfg"
nix run .#kh-headless -- list                # find testbar.* targets
nix run .#kh-headless -- show testbar.volume # methods on the volume tile
nix run .#kh-headless -- call testbar.volume setMuted true
nix run .#kh-headless -- grim "0,0 3840x32" muted-bar.png
```

The final command echoes `/tmp/kh-headless/out/muted-bar.png`.

## App config table

| App | Test config package | IPC target prefix | Notes |
|---|---|---|---|
| kh-bar | `.#kh-bar-headless` | `testbar` (root) + `testbar.<plugin>` | Dropdowns are addressable as `testbar.stats`, `testbar.controlcenter`. See [references/kh-bar.md](references/kh-bar.md) for crop sizing and dropdown variants. |
| kh-cliphist | `.#kh-cliphist` | `cliphist` (`toggle`) | Reuses the dev config (no test overrides needed). |
| kh-launcher | `.#kh-launcher-headless` | `launcher` (`toggle`) | All three plugins (`apps`, `emoji`, `hyprland-windows`) populate via fixtures. See [references/kh-launcher.md](references/kh-launcher.md) for crop, plugin variants, and gotchas. |
| kh-osd | `.#kh-osd` | `osd` (`showVolume N`, `showMuted`) | OSD popup at bottom-center, fades after 2s. Crop suggestion: `1720,2000 400x100`. |
| kh-window-inspector | `.#kh-window-inspector` | `window-inspector` (`toggle`) | Hyprland-only — finally captureable in this VM. |
| kh-view | `.#kh-view` | — | Used as the *display* target by `show-image`; rarely needs to be screenshotted. |

For most apps the *dev* config is the test config. `kh-bar` and
`kh-launcher` need overrides — see their reference docs.

## Settling

For dropdowns and other content with dynamic geometry, poll a height
property until two consecutive reads agree before grim'ing. See
[references/kh-bar.md](references/kh-bar.md) for the kh-bar pattern.
For OSD-style popups that animate via opacity, a 0.4 s sleep is
enough — they don't change size.

## References

| Task | Reference |
|---|---|
| Screenshot kh-bar (dynamic crop, dropdown variants) | [kh-bar.md](references/kh-bar.md) |
| Screenshot kh-launcher (per-plugin variants, crop) | [kh-launcher.md](references/kh-launcher.md) |
| Compare how the UI looked across git revisions | [compare-revisions.md](references/compare-revisions.md) |
| Compare uncommitted plan variations (A/B/C) | [compare-plans.md](references/compare-plans.md) |
| Display captured shots to the user | Use the `show-image` skill. |
