# Window Inspector

Overlay showing detailed information about open windows (class, title, PID,
geometry, workspace, monitor, etc.). Useful for writing Hyprland window
rules, debugging focus or scale issues, and confirming what an app reports
itself as. Spiritual sibling of AutoHotkey's *Window Spy* and browser
DevTools' element inspector, adapted for Hyprland. Triggered via keybind
or IPC.

## Core

- [1] ⬜ Window list from `hyprctl clients -j` — class, title, PID, address, workspace, monitor, geometry, floating/fullscreen
- [2] ⬜ Detail panel — full property dump for the selected window
- [3] ⬜ Surface `initialClass`/`initialTitle` alongside `class`/`title` — labelled "rule-stable" since matchers almost always want the initial values; main reason this overlay exists
- [4] ⬜ Geometry block — `at`/`size` in global AND monitor-local coords with monitor name + scale + transform
- [5] ⬜ Live updates from Hyprland IPC events (`openwindow`, `closewindow`, `windowtitle`, `movewindow`, `activewindow`)
- [6] ⬜ IPC — `target: "window-inspector"`; toggle/open/close/inspectActive/inspectByAddress/inspectByPid

## Navigation

- [1] ⬜ Modal normal/insert — `j`/`k` navigate, `/` filter, `Enter` opens detail, `Esc`/`q` closes
- [2] ⬜ Pick mode — `p` enters; cursor-over-window draws outline overlay + floating tag; click/`Enter` locks. DevTools-inspector UX
- [3] ⬜ Freeze toggle — `f` freezes the panel so the cursor can move off the target. AutoHotkey Window Spy's defining trick
- [4] ⬜ View toggle — `Tab` between flat list and tree view (monitor → workspace → window)

## Copy & Actions

- [1] ⬜ Copy as Hyprland rule — `y` copies a ready-to-paste `windowrulev2` line built from `initialClass`/`initialTitle`; menu offers `pid`/`address`/`workspace`/`monitor` variants
- [2] ⬜ Copy as JSON — `Y` copies the full `hyprctl clients -j` record
- [3] ⬜ Dispatch actions — `F` focus, `X` close, `m<n>` move-to-workspace, `t` toggle floating, `T` toggle pinned
