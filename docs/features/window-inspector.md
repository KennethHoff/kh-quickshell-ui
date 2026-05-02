# Window Inspector

Pick-first overlay for inspecting open windows — class, title, PID,
geometry, workspace, monitor, etc. AutoHotkey's *Window Spy* adapted for
Hyprland: point at a window, read what it calls itself, act on it (close,
focus, copy as a `windowrulev2` line). Triggered via keybind or IPC.

The launcher's [Hyprland window switcher](launcher/window-switcher.md) is
the multi-window browser; this one is single-target by design.

## Core

- [1] ✅ Window data from `hyprctl clients -j` — class, title, PID, address, workspace, monitor, geometry, floating/fullscreen
- [2] ✅ `initialClass`/`initialTitle` shown side-by-side with `class`/`title` and labelled "rule-stable" — the educational payload, visible in the hover tag without any extra keypress
- [3] ⬜ Geometry block — `at`/`size` in global AND monitor-local coords with monitor name + scale + transform
- [4] ✅ Live updates from Hyprland IPC (`openwindow`, `closewindow`, `windowtitle`, `movewindow`, `activewindow`, `changefloatingmode`, `fullscreen`)
- [5] ⬜ Layer-shell coverage via `hyprctl layers -j` — bars/notifications/lockscreens; only reachable from list view since the cursor can't grab them
- [6] ✅ IPC — `target: "window-inspector"`; `toggle`/`open`/`close` land in pick mode; `inspectActive`/`inspectByAddress`/`inspectByPid` open locked to a specific window

## Pick Mode (primary)

- [1] ✅ Inspector opens here by default. Cursor-over-window draws outline overlay + floating tag with `initialClass`/`class`/`initialTitle`/`title`/geometry
- [2] ✅ Freeze — `f` pins the tag so the cursor can move off the target. Window Spy's defining trick; needed any time the window dismisses on focus loss (tooltips, popups)
- [3] ⬜ `l` toggles into list view for windows the cursor can't grab
- [4] ✅ `?` opens the help overlay; `Esc`/`q` closes the inspector

## Copy & Actions

Act on the picked (or list-selected) window directly — no separate
"select" step. Expected fast path: point, read, `X`, done.

- [1] ✅ Copy as Hyprland rule — `y` then variant emits a ready-to-paste `windowrulev2` line: bare `y` / `yc` initial-class (default), `yt` initial-title, `yp` pid, `ya` address, `yw` workspace, `ym` monitor
- [2] ✅ Copy as JSON — `Y` copies the full `hyprctl clients -j` record
- [3] ✅ Dispatch — `X` close, `F` focus, `m<1-9>` move to workspace, `t` toggle floating, `T` toggle pinned

## List View (secondary)

Fallback for windows the cursor can't easily target — layer-shell entries,
windows hidden behind others, freshly-spawned-but-not-mapped. The launcher
window switcher is the better surface when you want to *find* a window;
this view exists mainly to expose the layer-shell pane.

- [1] ⬜ Flat list of windows + layer-shell entries; `j`/`k` navigate, `Enter` locks the hover tag onto the selected row, `l`/`Esc` returns to pick mode
- [2] ⬜ Plain substring filter via `/` — matches against `class`/`title`/`initialClass`/`initialTitle`. No fancy operators; the launcher is the place for that

## Notes

**Address / PID / initialClass for rules.** Hyprland window addresses
(`0x...`) change every relaunch, so they're fine for ad-hoc `hyprctl
dispatch` but useless in `windowrulev2`. PIDs change every launch too.
Persistent rules want `initialClass` / `initialTitle`; the live `class` /
`title` fields drift at runtime (browser tab titles being the obvious
case). Calling out that distinction at a glance is the inspector's main
job — the alternative is reading `hyprctl clients -j` by hand and
remembering which fields stay stable.
