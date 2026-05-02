---
name: screenshot
description: Capture and crop screenshots of quickshell apps from the headless VM via `kh-headless grim`, with app-specific crop sizing and settling. Use when the user asks for a screenshot / "take a shot", for visual verification after .qml or theme changes, to debug UI regressions, to compare revisions side-by-side ("it worked earlier" / "why does this look different"), or to compare multiple unimplemented variations/plans ("screenshot all three designs"). Assumes the VM is running and an app loaded — see the `headless` skill for the daemon, primitives, and app loading. Captures only — prints absolute file paths and stops.
allowed-tools: Bash, Read
---

# Screenshot skill

Captures come from the persistent VM via `nix run .#kh-headless -- grim "<x,y wxh>" [name]`.
Output files written to `/tmp/kh-headless/out/<name>`; the command
echoes the absolute host path back. Move them to a timestamped subdir
under `/tmp/qs-screenshots/<ts>/` if you want the historical on-disk
convention.

For VM setup, primitives, and app loading, see the `headless` skill.

## Default behaviour

After capture, print absolute file paths back to user and stop.
Do not auto-open any viewer — paths alone are enough.

## Settling

Before `grim`, wait for content to be stable.

For dropdowns and other dynamic-geometry content, poll a height
property until two consecutive reads agree. See
[references/kh-bar.md](references/kh-bar.md) for the kh-bar pattern.

For populated lists (e.g. kh-launcher plugins), poll the `itemCount`
prop until non-zero. See [references/kh-launcher.md](references/kh-launcher.md).

For OSD-style popups that animate via opacity, a 0.4 s sleep is
enough — they don't change size.

## Crop sizing

**Default to dynamic.** Pull width/height from live IPC so the shot
auto-resizes when popups open/close and survives any future VM
resolution change:

```bash
h=$(nix run .#kh-headless -- call testbar getHeight)
w=$(nix run .#kh-headless -- call testbar getWidth)
nix run .#kh-headless -- grim "0,0 ${w}x${h}" bar.png
```

See [references/kh-bar.md](references/kh-bar.md) for the kh-bar pattern.

**Fallback: fixed crop** when the target doesn't expose geometry on
IPC (popups with stable on-screen size). The VM's vkms output is
currently 3840×2160; verify with `nix run .#kh-headless -- call
<root> getWidth` before relying on these:

| App | Crop suggestion |
|---|---|
| kh-osd | `1720,2000 400x100` (bottom-center, fades after ~2 s) |
| kh-launcher (panel) | `1110,170 1620x1410` (centred panel, full) |
| kh-launcher (chrome only) | `1110,170 1620x140` (search box + chip row, 120 may clip) |

See [references/kh-launcher.md](references/kh-launcher.md) for the
launcher crop derivation from `panel.width`/`panel.height`.

## References

| Task | Reference |
|---|---|
| Screenshot kh-bar (dynamic crop, dropdown variants) | [kh-bar.md](references/kh-bar.md) |
| Screenshot kh-launcher (per-plugin variants, crop) | [kh-launcher.md](references/kh-launcher.md) |
| Compare how UI looked across git revisions | [compare-revisions.md](references/compare-revisions.md) |
| Compare uncommitted plan variations (A/B/C) | [compare-plans.md](references/compare-plans.md) |
