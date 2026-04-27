# Window switcher

Compositor-specific — each compositor needs its own data source and focus
dispatch, so they ship as separate plugins.

- [1] ✅ **Hyprland window switcher** — IPC key `hyprland-windows`, chip label `Windows`. Fuzzy search over all open windows; Enter focuses via `hyprctl dispatch focuswindow address:<addr>`; sorted by `focusHistoryID`; icons via `StartupWMClass`
- [2] ⬜ Per-item lifecycle keybinds — Quit, Force Quit, move-to-workspace
