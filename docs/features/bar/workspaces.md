# Workspaces

Hyprland workspaces with hover-preview thumbnails.

- [1] ✅ Workspace display — show Hyprland workspaces, highlight active
- [2] ✅ Click to switch workspace
- [3] ✅ Preview thumbnails — composite `ScreencopyView` per window at IPC positions; 240 px wide
- [4] ✅ Preview badge — workspace name in corner of thumbnail
- [5] ⬜ Click-through — clicking a window in the thumbnail focuses that window
- [6] ⬜ Submap indicator — show non-default Hyprland submap name; sourced from `submap` IPC event
- [7] ⬜ Scratchpad indicator — count of hidden scratchpad windows; click cycles via `togglespecialworkspace`
- [8] ✅ Per-delegate preview popup via `BarTooltip` — addressable at `<ipcPrefix>.workspaces.ws<name>` for direct pin/unpin
