---
name: screenshot
description: Capture headless screenshots of a quickshell app (kh-bar, kh-launcher, kh-cliphist, kh-osd, kh-view) via a sway + quickshell + grim pipeline. Use when the user asks for a screenshot / "show me" / "take a shot", for visual verification after .qml or theme changes, to debug UI regressions, to compare revisions side-by-side ("it worked earlier" / "why does this look different"), or to compare multiple unimplemented variations/plans ("show me both options", "screenshot all three designs").
allowed-tools: Bash, Read
---

# Screenshot skill

Output files go to `/tmp/qs-screenshots/<timestamp>/<name>.png`.

**Default behaviour:** after capture, print the file paths back to the
user. Do **not** open `kh-view` unless the user explicitly asks to see
the shots (e.g. "show me", "open them", "view the screenshots") — the
paths alone are enough for the user to inspect them on their own. When
they do ask, see [references/kh-view.md](references/kh-view.md).

## App table

| App | Config package | IPC target | Default crop | Notes |
|---|---|---|---|---|
| kh-bar | `.#kh-bar` | `dev-bar` (root + per-plugin) | dynamic | See [references/kh-bar.md](references/kh-bar.md) for crop sizing, settling, and readiness probe. |
| kh-cliphist | `.#kh-cliphist` | `cliphist` (`toggle`) | full screen | |
| kh-launcher | `.#kh-launcher` | `launcher` (`toggle`) | full screen | |
| kh-osd | `.#kh-osd` | `osd` (`showVolume N`, `showMuted`) | `1720,2000 400x100` | OSD fades; screenshot before it disappears. |
| kh-view | `.#kh-view` | — | full screen | Accepts file **or directory** paths. See [references/kh-view.md](references/kh-view.md). |

## References

Read the reference for the specific task — don't load them all up front.

| Task | Reference |
|---|---|
| Capture one or more shots of a single app | [pipeline.md](references/pipeline.md) — bash pipeline, readiness probe, timing table, multi-shot, fonts |
| Screenshot kh-bar (dynamic crop, popup settling) | [kh-bar.md](references/kh-bar.md) |
| Label panes or open the gallery for the user | [kh-view.md](references/kh-view.md) |
| Compare how the UI looked across git revisions | [compare-revisions.md](references/compare-revisions.md) |
| Compare multiple **uncommitted** plan variations (A/B/C) | [compare-plans.md](references/compare-plans.md) — includes worktree layout and Agent parallelisation |
