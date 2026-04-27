# Bar

A full status bar built in Quickshell, replacing Waybar.

## Core

- [1] ✅ Plugin authoring — `.qml` plugins wired via Nix at eval time
- [2] ✅ Per-plugin IPC targets via `ipcName` (e.g. `bar.volume`)
- [3] ✅ Dropdown IPC — `toggle`/`open`/`close`/`isOpen`
- [4] ✅ `BarGroup` — container plugin grouping children behind one dropdown button
- [5] ✅ Hierarchical IPC prefix — propagates through containers; nested targets like `bar.controlcenter.tailscale` fall out automatically
- [6] ⬜ Plugin error surface — standard mechanism for plugins to report failures visibly (subprocess non-zero is currently silently ignored)
- [7] ✅ Multi-monitor — `programs.kh-ui.bar.instances.<ipcName>` declares any number of bars; per-bar root IPC; silent-skip-on-disconnect
- [7a] ⬜ Bars on non-top edges (bottom, left, right) — extends [7] with an `edge` field; bottom is simplest, left/right need orientation-aware primitives
- [8] ✅ Root bar IPC — `getHeight()`/`getWidth()` returning visible footprint including any open dropdown popup
- [9] ✅ Service env injection — `programs.kh-ui.bar.environment` and `environmentFiles` (sops/agenix-friendly); plugins read via `Quickshell.env()`

## Building Blocks

Authoring primitives that make up a bar structure. Plugins compose these
rather than raw QtQuick types so layout, IPC prefix propagation, and theme
access stay consistent.

- [1] ✅ `BarPlugin` base — sizes itself, walks parent chain for `barWindow` and `ipcPrefix`
- [2] ✅ `BarRow` — full-width `RowLayout`, carries `ipcPrefix`
- [3] ✅ `BarSpacer` — flexible spacer (CSS space-between equivalent)
- [4] ✅ `BarPipe` — thin vertical separator; theme-aware default
- [5] ✅ `BarGroup` — dropdown wrapping arbitrary children (see Core [4])
- [6] ✅ `BarDropdown` — generic dropdown primitive used by `BarGroup`
- [7] ✅ `BarText` — theme-styled text with `normalColor`/`warnColor`/`errorColor`/`mutedColor`
- [8] ✅ `BarIcon` — `BarText` contract but loads bundled nerd-font for deterministic PUA codepoints
- [9] ✅ `BarTooltip` — generic hover tooltip (300 ms delay), edge-clamped; optional `ipcName` exposes `pin`/`unpin`/`togglePin` for keyboard/IPC visibility
- [10] ✅ `BarHorizontalDivider` — 1 px theme-aware separator; configurable colour/height
- [11] ✅ `BarControlTile` — toggle-pill primitive with active/pending states; used in Tailscale/Ethernet panels
- [12] ✅ `BarDropdownHeader`/`BarDropdownItem` — section heading + dot-and-two-labels row primitives

## Workspaces

- [1] ✅ Workspace display — show Hyprland workspaces, highlight active
- [2] ✅ Click to switch workspace
- [3] ✅ Hover preview popup (300 ms delay)
- [4] ✅ Preview thumbnails — composite `ScreencopyView` per window at IPC positions; 240 px wide
- [5] ✅ Preview badge — workspace name in corner of thumbnail
- [6] ⬜ Click-through — clicking a window in the thumbnail focuses that window
- [7] ⬜ Submap indicator — show non-default Hyprland submap name; sourced from `submap` IPC event
- [8] ⬜ Scratchpad indicator — count of hidden scratchpad windows; click cycles via `togglespecialworkspace`
- [9] ✅ Per-delegate preview popup via `BarTooltip` — addressable at `<ipcPrefix>.workspaces.ws<name>` for direct pin/unpin
- [10] ✅ Fan-out layout for multi-pinned previews — anchors live in a sibling overlay so coexisting pins don't stack at the same x
- [11] ✅ Background-workspace preview geometry — reads `workspace.monitor` directly so workspaces on inactive outputs still produce correctly-sized thumbnails

## Active Window

- [1] ⬜ Active window title — focused window's app name and title

## Clock

- [1] ✅ Live HH:mm display, updates every second
- [2] ⬜ Calendar dropdown — month grid with `hjkl` navigation
- [3] ⬜ Stopwatch — start/stop/reset; multiple named concurrent stopwatches as separate chips

## Audio

- [1] ✅ Volume scroll on widget; hidden when no sink
- [2] ✅ Click to toggle mute
- [3] ⬜ Mic mute — targets virtual PipeWire source node; configured via Nix
- [4] ⬜ Output device quick switch — right-click/dropdown to choose sink

## Media (MPRIS)

- [1] ✅ Playback controls — prev/play-pause/next
- [2] ✅ Track display — artist and title
- [3] ✅ Visibility — shows first active player; hidden otherwise
- [4] ⬜ Multi-source — dropdown when more than one player is active
- [5] ⬜ Seek bar — click/drag to seek; from MPRIS Position/Length
- [6] ⬜ Album art — thumbnail from MPRIS `mpris:artUrl`
- [7] ⬜ Shuffle/repeat toggles — reflect MPRIS `Shuffle`/`LoopStatus`

## System Tray

- [1] ✅ StatusNotifierItem icons; left activate, right native menu; hidden when empty
- [2] ⬜ Overflow bucket — collapse least-recently-used into expander chip

## Tailscale

- [1] ✅ Status polling — `tailscale status --json` every 10 s; exposes `connected`/`selfIp`/`peers`
- [2] ✅ Tile appearance — `BarControlTile` pill with IP sublabel; highlights when connected
- [3] ✅ Toggle on click — runs `tailscale up`/`down` and re-polls; requires user as operator (see [Notes](#notes))
- [4] ✅ IPC — `bar.tailscale` exposes `isConnected`/`getSelfIp`/`toggle`
- [5] ✅ Pending state — pulses opacity, `…` sublabel; double-clicks ignored
- [6] ⬜ Toggle error feedback — surface non-zero exit visibly; common cause is operator not configured
- [7] ✅ Peer ping — click peer row to run `tailscale ping -c 1 <ip>`; latency shown inline in `base0E` for 5 s
- [8] ✅ Exit node selection — exit-capable peers in separate section; click to set/clear; active highlighted in `base0A`
- [9] ⬜ Advertise exit node toggle
- [10] ⬜ Shields-up toggle
- [11] ✅ Hover highlight on peer rows; suppressed during pending operations

## Network

- [1] ⬜ Wired interface name and link state via nmcli; hidden when disconnected

## System Stats

Stats plugins are **data-only**: each polls a source and exposes readable
properties; users compose them with a sibling `BarText` to render the value.

- [1] ✅ `CpuUsage` — samples `/proc/stat`; exposes `usage: int`
- [2] ✅ `RamUsage` — reads `/proc/meminfo`; exposes Kb props and `percent`
- [3] ✅ AMD `GpuUsage` — reads `/sys/class/drm/<card>/device/*`; exposes busy/VRAM. Nvidia deferred
- [4] ✅ `DiskUsage` — `df -B1` every 60 s; per-mount used/total
- [5] ✅ `CpuTemp`/`GpuTemp` — walk `/sys/class/hwmon/*` for matching sensor; expose `temp: int` (°C)

## Docker

- [1] ⬜ Container count badge; panel lists all containers
- [2] ⬜ Start/stop/restart from panel
- [3] ⬜ Log tail (`docker logs -f`) inline

## Aspire

- [1] ⬜ Service count badge from `aspire ps`; hidden when no session
- [2] ⬜ Service list panel — state, endpoint URLs, health
- [3] ⬜ Resource drill-down — tail structured logs inline

## Notifications

- [1] ✅ Bell icon; hidden when unread count is zero
- [2] ⬜ Unread badge from `Quickshell.Services.Notifications`
- [3] ⬜ DND indicator — muted icon variant when DND active
- [4] ⬜ Click toggles [Notification Center](notification-center.md) panel

## Notes

**Tailscale operator setup** *(Tailscale [3])* — toggling Tailscale via
`tailscale up`/`down` requires the user to be set as operator once:

```
sudo tailscale up --operator=$USER
```

`tailscale set --operator` is [broken
upstream](https://github.com/tailscale/tailscale/issues/18294); the
NixOS module's `extraUpFlags` only applies when `authKeyFile` is set.
