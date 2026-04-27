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
- [5] ✅ `BarDropdown` — generic dropdown primitive used by `BarGroup` (see Core [4])
- [6] ✅ `BarText` — theme-styled text with `normalColor`/`warnColor`/`errorColor`/`mutedColor`
- [7] ✅ `BarIcon` — `BarText` contract but loads bundled nerd-font for deterministic PUA codepoints
- [8] ✅ `BarTooltip` — generic hover tooltip (300 ms delay), edge-clamped; optional `ipcName` exposes `pin`/`unpin`/`togglePin` for keyboard/IPC visibility
- [9] ✅ `BarHorizontalDivider` — 1 px theme-aware separator; configurable colour/height
- [10] ✅ `BarControlTile` — toggle-pill primitive with active/pending states; used in Tailscale/Ethernet panels
- [11] ✅ `BarDropdownHeader`/`BarDropdownItem` — section heading + dot-and-two-labels row primitives

## Plugins

- [Workspaces](bar/workspaces.md) — Hyprland workspaces with hover-preview thumbnails
- [Active Window](bar/active-window.md) — focused window's app and title
- [Clock](bar/clock.md) — live time, calendar dropdown, stopwatch
- [Audio](bar/audio.md) — volume, mute, sink switching
- [Media](bar/media.md) — MPRIS playback controls and track info
- [System Tray](bar/system-tray.md) — StatusNotifierItem icons
- [Tailscale](bar/tailscale.md) — status, peer ping, exit-node selection
- [Ethernet](bar/ethernet.md) — wired interface state via `nmcli`
- [System Stats](bar/system-stats.md) — CPU/RAM/GPU/Disk/Temp data sources
- [Docker](bar/docker.md) — container count, lifecycle, log tail
- [Aspire](bar/aspire.md) — service count, list, log tail
- [Notifications](bar/notifications.md) — bell icon, unread badge, DND
- [Home Assistant](bar/home-assistant.md) — surface Home Assistant entity state
