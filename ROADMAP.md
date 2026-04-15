# Quickshell Roadmap

Features to implement. Each entry becomes its own Quickshell component or launcher mode.

**UX principles:**

- Overlays are reachable from multiple entry points: bar widgets open their
  corresponding overlay on click, and all overlays are searchable and
  openable from the launcher.
- Overlays are modal, following vim bindings as closely as the UI context allows.
- Everything controllable via keyboard must also be controllable via IPC, so
  overlays can be driven programmatically (automation, agentic development).
- Keyboard-first. Mouse support is a future concern.

---

## Configuration / Portability

Hardcoded assumptions that should be user-configurable.

- [1] ✅ **Configurable terminal** — `programs.kh-ui.launcher.terminal` option (defaults to `pkgs.kitty`); injected as `bin.terminal` into the launcher's `NixBins.qml` via `extraBins`; `kh-launcher.qml` uses `bin.terminal` instead of `bin.kitty`
- [2] ✅ **`kitty` removed from universal `ffi.nix` bins** — moved to launcher-specific `extraBins` as `terminal`; no longer injected into bar, cliphist, or view configs
- [3] ⬜ **Hyprland-only `exec-once` wiring** — `hm-module.nix` only adds apps to `exec-once` when `wayland.windowManager.hyprland.enable` is true; users on Sway or other compositors get no autostart integration; needs a generic autostart mechanism or at minimum a `programs.kh-ui.autostart` option the user can wire up themselves

---

## Clipboard History

Standalone Quickshell daemon (`quickshell -c kh-cliphist`) with a searchable
list of clipboard entries from `cliphist`. SUPER+V toggles it via IPC.

### Core

- [4] ✅ Searchable list — all text entries pre-decoded on open so search matches full content
- [5] ✅ Text entries shown as-is; image entries shown as thumbnails
- [6] ✅ Enter copies the selected entry via `cliphist decode | wl-copy`; entry flashes on copy
- [7] ✅ Search filters — `img:` / `text:` type filter, `'` exact substring match
- [8] ✅ Entry counter in footer
- [9] ✅ Fast search — haystacks pre-processed at load time; filter debounced at 80 ms; full-text cache updated via O(1) index lookup as decode streams in
- [10] ✅ IPC — `toggle`, `setMode`, `nav`, `key`, `type`

### Navigation

- [11] ✅ Modal insert/normal mode — opens in normal mode; `j`/`k` navigate, `G` bottom, `/` → insert (search focused); Escape → normal mode or closes
- [12] ✅ `gg` top, `G` bottom, `Ctrl+D`/`Ctrl+U` half-page scroll
- [13] ✅ Emacs bindings in insert mode — `Ctrl+A`/`E` start/end, `Ctrl+F`/`B` forward/back char, `Ctrl+D` delete forward, `Ctrl+K` delete to end, `Ctrl+W` delete word, `Ctrl+U` delete to line start

### Detail Panel

- [14] ✅ Detail panel layout — always-visible side pane (40/60 split); auto-loads selected entry on navigation (120 ms debounce)
- [15] ✅ Detail panel text metadata — char/word/line count shown for text entries
- [16] ✅ Detail panel image metadata — dimensions and file size shown for image entries
- [17] ✅ Detail panel navigation — `Tab`/`l` enters the panel; `Tab`/`Esc` returns to the list
- [18] ✅ Detail panel cursor and motions — `hjkl`/`w`/`b`/`e`/`W`/`B`/`E`; `0`/`$`/`^` line
- [19] ✅ Detail panel visual select — `v`/`V`/`Ctrl+V` char/line/block; word motions extend char selection; `o`/`O` swap anchor corner; `y` copies selection
- [20] ⬜ Insert mode in detail panel — edit text content inline before copying; vim operator bindings (`ciw`, `dw`, etc.); `i`/`a`/`I`/`A`/`o`/`O` to enter insert; Escape back to normal; `y` copies the modified content

### Fullscreen View

- [21] ✅ Fullscreen view — `Enter` from detail opens; `Escape` returns; full text/image filling the panel
- [22] ✅ Fullscreen navigation — `hjkl`/`w`/`b`/`e`/`W`/`B`/`E` cursor; `0`/`$`/`^` line; `gg`/`G`/`Ctrl+D`/`U` navigate
- [23] ✅ Fullscreen visual select — `v`/`V`/`Ctrl+V` char/line/block; word motions extend; `o`/`O` swap anchor corner; `y` copies selection
- [24] ⬜ Insert mode in fullscreen — same as detail panel insert mode, for the fullscreen view

### Help

- [25] ✅ Help overlay — `?` opens a popup showing all mode bindings (normal / visual / insert) at once; `/` filters rows inline; popup shrinks to fit matches
- [26] ⬜ Context-aware help — visually highlight the section corresponding to the current mode; all sections remain visible but the active one is called out

### Entry Management

- [27] ✅ Delete single entry — `d` in normal mode; confirmation popup; executes via `cliphist delete`; cursor repositions to the entry above
- [28] ✅ Delete range in visual mode — `d` deletes all entries in the selected range; confirmation popup before executing
- [29] ✅ Delete animation — fade-out on deleted entries
- [30] ✅ Pin toggle — `p` toggles pin on the selected entry
- [31] ✅ Pinned entries sort to top — pinned entries appear at the top of both unfiltered and search-filtered lists
- [32] ✅ Pin persistence — persisted to `$XDG_DATA_HOME/kh-cliphist/pins` (one entry ID per line); deleting a pinned entry removes it from the pin set
- [33] ✅ Pin visual indicator — 3 px coloured bar on the left edge of each pinned delegate row
- [34] ⬜ Batch pin in visual mode — `p` in visual mode toggles pin on all entries in the selected range

### Metadata

- [35] ✅ Timestamp on entries — first-seen time shown right-aligned on each row ("just now" / "5m ago" / "3h ago" / "2d ago" / "4w ago"); persisted to `$XDG_DATA_HOME/kh-cliphist/meta/timestamps`; stale IDs pruned on each load; refreshes on reopen
- [36] ⬜ Source app attribution — record the active Hyprland window at copy time and show it on each row. Attempted via `wl-paste --watch` + `hyprctl activewindow`, but accuracy is poor: (1) copying from within the cliphist overlay always reports the last regular window; (2) every copy-from-overlay creates a mis-attributed entry. Needs a Hyprland plugin/event hook or a Wayland protocol that exposes the source client of a clipboard change.

### Integration

- [37] ⬜ Auto-paste — close the window and simulate Ctrl+V into the previously focused app via `wtype`

---

## Launcher

Searchable application launcher (`quickshell -c kh-launcher`).

### Core

- [38] ✅ Fuzzy search over installed apps by name and description; haystacks are `name + comment`
- [39] ✅ Search filters: `'` exact match, `^` prefix, `$` suffix, `!` negation; space-separated tokens combine with AND
- [40] ✅ Description shown in list (one line below app name)
- [41] ✅ `j`/`k` navigate, `Enter` launch; opens in insert mode (search field focused)
- [42] ✅ Ctrl+1–9 launches the selected app on workspace 1–9 via `hyprctl dispatch exec [workspace N]`
- [43] ✅ `l` / Tab enters actions mode for the selected app (only switches if the app has actions)
- [44] ✅ `j`/`k` navigate actions; `Enter` launches selected action
- [45] ✅ `h` / Esc returns from actions mode to app list
- [46] ✅ Apps with `Terminal=true` run wrapped in the configured terminal (`bin.terminal`)
- [47] ✅ Window closes automatically after launching
- [48] ✅ Flash animation (green) when an app or action is launched
- [49] ✅ `?` toggles a searchable help overlay listing all keybinds; help sections are mode-aware (actions vs. normal/insert)
- [50] ✅ App icons — display the icon image (not just name) in the list row
- [51] ✅ App icons in actions mode — show the parent app's icon next to each desktop action entry
- [52] ⬜ Frequency-weighted results — track launch counts per app in a local counter file; blend match score with usage frequency so frequently-launched apps surface higher; decays over time so stale counts don't dominate
- [53] ⬜ Script mode — any external process can push a list of items (label, description, icon, callback command) into the launcher via IPC and receive the user's selection back; makes the launcher infinitely extensible without baking in every mode; Nix option to register named script modes that appear alongside built-in modes

### Modes

- [54] ⬜ Window switcher mode — fuzzy search over all open windows by app name or title, across all workspaces and monitors; Enter focuses the window and switches to its workspace
- [55] ⬜ Emoji picker mode — fuzzy search emoji by name; Enter copies to clipboard
- [56] ⬜ Snippets mode — text expansion triggered by abbreviation
- [57] ⬜ System commands mode — lock, sleep, reboot, etc. as searchable actions
- [58] ⬜ Color picker *(long term)* — screen dropper; Enter copies hex/rgb to clipboard
- [59] ⬜ File search *(long term)* — fd/fzf over `$HOME`; Enter opens in default app

---

## Bar

A full status bar built in Quickshell, replacing Waybar.

### Core

- [60] ✅ Plugin authoring system — plugins are `.qml` files wired in via Nix (`structure`/`extraPluginDirs`); built at eval time so no runtime module import is needed
- [61] ✅ `BarRow` and `BarSpacer` layout types — `BarRow` is a full-width row; `BarSpacer` fills remaining space (CSS space-between equivalent)
- [62] ✅ Per-plugin IPC targets — each plugin exposes its own named target (e.g. `bar.volume`, `bar.workspaces`)
- [63] ✅ Dropdown IPC — dropdowns with `ipcName` set expose `bar.<name>` with `toggle`/`open`/`close`/`isOpen`
- [64] ✅ `BarGroup` plugin — a container plugin that groups any number of child plugins behind a single dropdown button; children are declared inline in `structure` exactly like top-level plugins; any plugin (Volume, Workspaces, custom) can appear inside a group or directly in the bar — placement is independent of plugin type; the button shows a configurable label or icon; implement before hierarchical IPC
  ```qml
  // Network + audio behind one button
  BarGroup {
      label: "●●●"
      EthernetPanel {}
      TailscalePanel { id: ts }
      TailscalePeers { source: ts }
      Volume {}
  }

  // Wrap any existing plugin — no changes to the plugin itself
  BarGroup {
      label: "media"
      MediaPlayer {}
  }

  // Mix grouped and ungrouped freely in the same bar
  BarRow {
      Workspaces {}
      BarSpacer {}
      BarGroup { label: "●●●"; EthernetPanel {}; TailscalePanel {} }
      Clock {}
  }
  ```
- [65] ✅ Hierarchical IPC prefix — `ipcPrefix` propagates through `BarPlugin` → `BarRow` → `BarDropdown.col` via parent chain walk; each `BarGroup`/`BarDropdown` appends its `ipcName` segment so plugins get targets like `bar.controlcenter.tailscale` automatically; root prefix is `ipcName` from `mkBarConfig` (default `"bar"`), exposed as `programs.kh-ui.bar.ipcName` in the hm-module; `EthernetPanel` and `TailscalePanel` converted from `ControlTile` to `BarPlugin` base so they join the prefix chain regardless of popup nesting depth
- [66] ⬜ Plugin error surface — a standard mechanism for plugins to report failures to the user; currently any subprocess that exits non-zero is silently ignored and the plugin stays in its last known state; needs a shared primitive (e.g. a visual error state on `ControlTile`, a toast, or a bar-level error badge) so plugins like `TailscalePanel` can surface "toggle failed" instead of doing nothing
- [67] ⬜ Multi-bar support — allow N bars at arbitrary screen edges (top, bottom, left, right); `mkBarConfig` accepts a list of `{ edge, structure }` entries; each bar gets its own `PanelWindow` and generated `BarLayout`; `BarDropdown` opens its popup toward the screen interior so it works on any edge; currently kh-bar uses a single `PanelWindow` with no screen binding (multi-screen removed pending this entry)

### Workspaces

- [68] ✅ Workspace display — show Hyprland workspaces; highlight the active workspace
- [69] ✅ Workspace click to switch — click a workspace button to switch to it
- [70] ✅ Workspace preview on hover — hovering a button for 300 ms shows a thumbnail popup; disappears on mouse leave
- [71] ✅ Workspace preview thumbnails — composites per-window `ScreencopyView` captures at Hyprland IPC positions; scaled to 240 px wide
- [72] ✅ Workspace preview badge — workspace name badge in the corner of the thumbnail
- [73] ⬜ Workspace preview click-through — clicking a window inside the preview thumbnail focuses that specific window directly, not just the workspace
- [74] ⬜ Submap indicator — show the active Hyprland submap name (e.g. `resize`, `passthrough`) in the bar when a non-default submap is active; hidden during normal operation; sourced from the `submap` Hyprland IPC event
- [75] ⬜ Scratchpad indicator — show a count of hidden scratchpad windows; click cycles through them via `hyprctl dispatch togglespecialworkspace`; hidden when scratchpad is empty

### Active Window

- [76] ⬜ Active window title — display the focused window's app name and title

### Clock

- [77] ✅ Clock — live HH:mm display, updates every second
- [78] ⬜ Calendar dropdown — clock opens a dropdown on click; month grid with `h`/`j`/`k`/`l` navigation
- [79] ⬜ Unit converter tab — accessible from the calendar dropdown; length, weight, temperature, etc.
- [80] ⬜ Stopwatch — start/stop/reset via click or IPC; elapsed time shown in the bar while running; hidden when stopped; supports multiple named concurrent stopwatches, each shown as a separate chip in the bar

### Audio

- [81] ✅ Volume scroll — scroll on the widget to adjust volume via PipeWire; hidden when no sink is available
- [82] ✅ Mute toggle — click the widget to toggle mute via PipeWire
- [83] ⬜ Microphone mute toggle — mutes the configured virtual PipeWire source node (not the physical device); the setup uses virtual sinks and sources that physical devices and apps route through, so mute targets the virtual node to silence all inputs simultaneously; configured via Nix with the target node name
- [84] ⬜ Output device quick switch — right-click or dropdown on the volume widget to select between available PipeWire sinks without opening the full Audio Mixer

### Media (MPRIS)

- [85] ✅ MPRIS playback controls — prev/play-pause/next buttons
- [86] ✅ MPRIS track display — artist and title shown alongside controls
- [87] ✅ MPRIS visibility — shows the first active player; hidden when no player is active
- [88] ⬜ MPRIS multi-source — when more than one player is active, show a dropdown (or similar) to select which source is displayed rather than always picking the first one
- [89] ⬜ Seek bar — progress indicator showing position within the current track; click or drag to seek; sourced from MPRIS `Position` and `Length` metadata
- [90] ⬜ Album art — thumbnail of the current track's artwork sourced from MPRIS `mpris:artUrl`; shown alongside artist/title
- [91] ⬜ Shuffle / repeat toggles — buttons reflecting and toggling the MPRIS `Shuffle` and `LoopStatus` properties

### System Tray

- [92] ✅ Taskbar icons — tray icons via StatusNotifierItem protocol; left click activates, right click shows native context menu via `display()`; hidden when no items present
- [93] ⬜ Overflow bucket — when icon count exceeds a configured limit, least-recently-interacted icons collapse into an expander chip; click expander to reveal the overflow tray

### Tailscale

- [94] ✅ Tailscale status polling — polls `tailscale status --json` every 10 s; parses `BackendState`, `TailscaleIPs`, and `Peer` map; exposes `connected`, `selfIp`, and `peers` for use in `TailscalePeers`
- [95] ✅ Tailscale tile appearance — `ControlTile`-based pill; label + IP sublabel; highlights when connected via `activeColor`
- [96] ✅ Tailscale toggle on click — click the tile to run `tailscale up`/`down` and re-poll on exit; requires `tailscale` added to `extraBins` for the bar config so it is available as a Nix store path; also requires the user to be set as operator once: `sudo tailscale up --operator=$USER` (note: `tailscale set --operator` is [broken upstream](https://github.com/tailscale/tailscale/issues/18294); `extraUpFlags` in the NixOS module only applies when `authKeyFile` is set)
- [97] ✅ IPC — `bar.tailscale` target exposes `isConnected()`, `getSelfIp()`, `toggle()`
- [98] ⬜ Toggle error feedback — when `tailscale up`/`down` exits non-zero, surface the failure visibly on the tile (e.g. flash red, show a brief error sublabel, or emit a notification); currently the tile silently stays in its previous state; the most common cause is the operator not being configured (`sudo tailscale up --operator=$USER`)
- [99] ⬜ Exit node selection — list exit-node-capable peers; click one to run `tailscale set --exit-node=<ip>`; highlight active exit node; click again (or a clear button) to disable
- [100] ⬜ Advertise exit node toggle — button to run `tailscale set --advertise-exit-node` on/off for the local machine
- [101] ⬜ Shields-up toggle — toggle `tailscale set --shields-up` to block incoming connections; reflected in the tile UI

### Sonarr

- [102] ⬜ Sonarr — badge when new episodes are downloaded; click to open a panel showing recently grabbed episodes and upcoming releases (polls Sonarr API)

### Network

- [103] ⬜ Network status — show active wired interface name and link state via nmcli; hidden when disconnected

### System Stats

- [104] ⬜ CPU usage — utilisation % across all cores; updates on a short interval; hidden when idle below a threshold
- [105] ⬜ RAM usage — used/total memory; sourced from `/proc/meminfo`
- [106] ⬜ GPU stats — utilisation % and VRAM used/total for AMD (`/sys/class/drm`) or Nvidia (`nvml`); hidden when idle below a threshold
- [107] ⬜ Disk usage — used/total for one or more configured mount points (e.g. `/`, `/home`)
- [108] ⬜ Temperature — CPU and GPU temps via `/sys/class/hwmon`; colour-coded (cool → warm → hot); shown alongside the corresponding CPU/GPU stat

### Docker

- [109] ⬜ Docker status — running container count badge; click opens a panel listing all containers with name, image, and status
- [110] ⬜ Container actions — start/stop/restart individual containers from the panel
- [111] ⬜ Log tail — select a container in the panel and stream its logs inline (`docker logs -f`)

### Aspire

- [112] ⬜ Aspire status — running service count badge sourced from `aspire ps`; hidden when no Aspire session is active
- [113] ⬜ Aspire panel — click to open a list of all services with their state, endpoint URLs, and health; click a URL to open in browser
- [114] ⬜ Resource drill-down — select a service to tail its structured logs inline

### Notifications

- [115] ⬜ Notifications indicator — unread badge count in the bar; click opens the Notification Center panel

---

## Notification Center

Standalone Quickshell daemon replacing `mako`/`dunst`. Shows incoming toasts
and a persistent history panel (toggle via SUPER or bar button). Groups
notifications by app, supports action buttons, and integrates a Do Not
Disturb toggle.

### Toasts

- [116] ⬜ Incoming toasts — transient popup per notification with app icon, summary, and body; auto-dismisses after timeout
- [117] ⬜ Urgency handling — `critical` notifications ignore DND and persist until dismissed; `low` notifications skip the toast entirely

### History Panel

- [118] ⬜ Persistent history panel — toggle via SUPER or bar button; all notifications since last clear, grouped by app; dismiss individual or all
- [119] ⬜ Action buttons — render notification action buttons; click executes the action via DBus reply
- [120] ⬜ Do Not Disturb toggle — suppress toasts while enabled; history still accumulates; togglable from the bar and the panel

---

## Audio Mixer

Per-app volume mixing UI, replacing `pavucontrol`. Shows all active audio
streams grouped by app, with per-app volume sliders, mute toggles, and live
visualizations indicating which apps are currently producing audio. Toggle via
IPC/keybind.

### Core

- [121] ⬜ Stream list — all active PipeWire audio streams grouped by app, with app icon and name
- [122] ⬜ Per-app volume slider — drag or scroll to adjust individual stream volume
- [123] ⬜ Per-app mute toggle — click to mute/unmute a stream
- [124] ⬜ Output device selector — choose the default sink from a list of available PipeWire sinks

### Visualization

- [125] ⬜ Live activity indicator — VU meter or pulse animation showing which streams are currently producing audio

---

## OSD

Transient overlay that appears briefly when volume or brightness changes via
keyboard shortcuts, replacing SwayOSD or mako-based notifications. Shows a
progress bar and icon, then fades out automatically.

### Core

- [126] ⬜ Volume OSD — appears on volume up/down/mute shortcuts; shows icon and progress bar reflecting the new level
- [127] ⬜ Brightness OSD — appears on brightness shortcuts; same layout as volume OSD
- [128] ⬜ Auto-dismiss — fades out after ~2 s; timer resets if the value changes again before dismissal
- [129] ⬜ IPC trigger — `qs ipc call osd show --value <0–100> --icon <name>` so any keybind daemon can drive it

---

## File Viewer

One-shot viewer for arbitrary text or image files. Accepts N file arguments
or stdin; shows all files side-by-side with Tab to cycle focus between panes.

### Core

- [130] ✅ `nix run .#kh-view -- <file> [<file2> ...]` or `<cmd> | nix run .#kh-view`
- [131] ✅ Image detection by extension (png/jpg/jpeg/gif/webp/bmp/svg)
- [132] ✅ N files shown side-by-side in equal-width panes; Tab cycles focus; active divider highlights
- [133] ✅ `q`/`Esc` quits
- [134] ✅ IPC — `target: "viewer"`; `next()`/`prev()`/`seek(n)`/`quit()`/`setFullscreen(bool)`/`key(k)`; readable props `currentIndex`, `count`, `fullscreen`, `hasPrev`, `hasNext`
- [135] ⬜ Optional pane labels — each pane optionally shows a header bar with a short name and description; `kh-view` accepts label metadata alongside each file via a sidecar format or extended list protocol *(implement together with Dev Tooling → screenshot skill labels)*
- [136] ⬜ Monitor selection — `--monitor <name|index>` flag; defaults to the monitor containing the active window

### Navigation

- [137] ✅ Per-pane cursor and motions — `hjkl`/`w`/`b`/`e`/`W`/`B`/`E`; `0`/`$`/`^` line; `gg`/`G`/`Ctrl+D`/`U` scroll
- [138] ✅ Per-pane visual select — `v`/`V`/`Ctrl+V` char/line/block; word motions extend; `y` copies selection
- [139] ✅ Fullscreen mode — `f` toggles single fullscreen pane; `h`/`l` steps through all loaded files; dot indicators at bottom center

### Content

- [140] ⬜ Syntax highlighting — detect language from file extension; apply token-level colouring using Tree-sitter or `bat` themes
- [141] ⬜ Directory and glob input — `kh-view ./images/` opens all recognised media files; `kh-view ./images/*.png` expands the glob; files sorted by name
- [142] ⬜ Image gallery mode — `g` toggles a grid thumbnail view when all panes are images; `hjkl` navigate; Enter opens selected image fullscreen

---

## Process Manager

Keyboard-driven process viewer, replacing `htop`. Shows running processes
sortable by CPU, RAM, or name; `k` kills the selected process. Toggle via
keybind or IPC, or open by clicking a System Stats bar widget.

### Core

- [143] ⬜ Process list — all running processes with PID, name, CPU %, and RAM usage; sourced from `/proc`
- [144] ⬜ Sort — cycle sort column with `s`; toggle ascending/descending with `S`
- [145] ⬜ Filter — `/` to search by process name
- [146] ⬜ IPC trigger — openable from bar widget clicks on CPU or RAM

### Actions

- [147] ⬜ Kill — `k` sends SIGTERM to the selected process; `K` sends SIGKILL; confirmation popup before executing

### Views

- [148] ⬜ Tree view — `t` toggles parent/child process tree layout

---

## Diff Viewer

Side-by-side two-pane file diff. `kh-diff file1 file2` or pipe from `git diff`
/ `diff`. Keyboard-driven; vim motion navigation. Natural sibling to File Viewer.

### Core

- [149] ⬜ Two-pane diff — left/right panes showing old and new versions with added/removed/changed lines highlighted
- [150] ⬜ Pipe input — `git diff | kh-diff` or `diff -u a b | kh-diff` reads unified diff from stdin and renders it
- [151] ⬜ IPC — same pattern as File Viewer

### Navigation

- [152] ⬜ `]c` / `[c` jump to next/previous change hunk
- [153] ⬜ `Tab` cycles focus between panes; `hjkl` scroll within a pane; `gg`/`G`/`Ctrl+D`/`U` navigate
- [154] ⬜ `y` copies the selected hunk or visual selection

---

## Screenshot

Region/window/fullscreen capture tool, replacing Flameshot. Captures via
`grim`/`slurp`; result goes to clipboard or is saved to a file. Triggered
via keybind or IPC.

### Core

- [155] ⬜ Region capture — `slurp` crosshair selection; result copied to clipboard via `wl-copy`
- [156] ⬜ Fullscreen capture — capture the focused monitor immediately
- [157] ⬜ Window capture — click to select a window; captures its geometry via Hyprland IPC
- [158] ⬜ IPC trigger — `qs ipc call screenshot <region|fullscreen|window>` so any keybind daemon can drive it

### Output

- [159] ⬜ Save to file — write to `$XDG_PICTURES_DIR/Screenshots/` with a timestamp filename in addition to clipboard copy
- [160] ⬜ Annotation layer — draw arrows, boxes, and text over the capture before copying/saving

---

## Dev Tooling

Improvements to the Claude skills and agentic development workflow.

- [161] ⬜ `screenshot` skill passes labels to `kh-view` — once kh-view supports optional pane labels, update the skill to supply a name and short description for each shot (what app/state it shows, what to look for); makes review sessions self-documenting without manual annotation *(implement together with File Viewer → optional pane labels)*
- [162] ⬜ Headless Hyprland for workspace preview screenshots — `kh-bar`'s Workspaces plugin uses
  `Quickshell.Hyprland` types and `ScreencopyView`, which require a live Hyprland session;
  Sway headless can't drive them.

  **Dead ends already tried** (don't bother):
  - `WLR_BACKENDS=headless` — ignored by Aquamarine
  - `AQ_BACKENDS=headless` — not a real env var
  - `hyprland --headless` — flag does not exist
  - Nesting (leaving `WAYLAND_DISPLAY` set) — renders visibly on the real session
  - `HYPRLAND_HEADLESS_ONLY=1` — used by Hyprland's own
    [`hyprtester`](https://github.com/hyprwm/Hyprland/tree/main/hyprtester) CI framework,
    but creates no Wayland display socket; Hyprland's IPC socket exists but Quickshell
    can't connect as a Wayland client. Only useful for testing Hyprland internals directly.

  **Fix:** `boot.kernelModules = [ "vkms" ]` in NixOS config. VKMS is a virtual kernel DRM
  device with no physical output; Hyprland's DRM backend accepts it and Aquamarine
  initialises fully, including creating a Wayland display socket for clients to connect.

  **Implementation sketch** (once VKMS is loaded): add `--compositor hyprland` to
  `nix run .#screenshot`; launch with `WAYLAND_DISPLAY`, `DISPLAY`, and
  `HYPRLAND_INSTANCE_SIGNATURE` unset; detect the Wayland socket at
  `$XDG_RUNTIME_DIR/wayland-*` and IPC sig at `$XDG_RUNTIME_DIR/hypr/<sig>/`;
  seed fake windows via `exec-once = [workspace N] weston-simple-shm` so
  `ScreencopyView` has something to capture.

---

## Possibly

Ideas with clear value but no committed timeline.

- **Scratchpad** — persistent floating notepad toggled by keybind; plain text, autosaved to `$XDG_DATA_HOME/kh-scratch`; vim bindings; `y` copies selection
- **SSH launcher mode** — Launcher mode that fuzzy-searches `~/.ssh/config` hosts; Enter opens kitty with `ssh <host>`
- **Log viewer** — tail `journalctl` or arbitrary log files with unit/level filter; keyboard-driven alternative to `kitty -e journalctl`
- **Ping + bandwidth monitor** (Bar) — rolling average latency to a configured host plus live upload/download throughput; colour-coded latency indicator; hidden when idle below threshold
- **Multiple time zones** (Bar) — show additional configured time zones alongside the main clock; click to expand a list of all configured zones
- **Web search prefixes** (Launcher mode) — configurable prefix → URL mappings (e.g. `g <q>` → Google, `gh <q>` → GitHub, `mdn <q>` → MDN); defined in Nix; Enter opens in default browser
- **Browser history** (Launcher mode) — fuzzy search Firefox/Chromium history by title and URL; reads from the browser's SQLite history database; Enter opens in browser; read-only, no write access to profile

---

## Probably Not

Considered and deprioritised. Kept here to avoid re-litigating.

- **Night light** — toggle `wlsunset`/`gammastep` on/off with a colour temperature slider
- **Pomodoro** — countdown timer in the bar; IPC controllable; notification on completion
- **Weather** — current conditions widget fetching from `wttr.in`; 3-day forecast dropdown
- **Calculator mode** — evaluate expressions in the Launcher search field; Enter copies result to clipboard
- **Recent files mode** — fuzzy search `recently-used.xbel`; Enter opens in default app
- **NixOS update notifier** — badge when `nix flake metadata` shows the system is behind upstream
- **Keyboard layout switcher** — bar widget showing current layout; click/scroll to cycle via `hyprctl switchxkblayout`
- **GitHub/GitLab notifications** — unread badge via API; click to list PRs/issues/mentions
- **Password generator** — generate and copy a random password from the Launcher
- **Crypto/stock ticker** — live price widget in the bar
- **Wallpaper picker** — browse and apply wallpapers via `swww`; no wallpapers in use
- **Git branch indicator** (Bar) — show active branch for the focused window's CWD; unclear what "focused window's repo" means in practice outside of a terminal
- **Font browser** — grid/list of installed fonts with live preview text
- **IDE project picker** — fuzzy search project directories and open in editor; terminal workflow already covers this
- **Dictionary** — inline word definition via WordNet; search engine covers the need
- **Clock timestamp copy** — click the clock to copy the current time to clipboard; too niche and a widget action with no visual feedback is confusing

---

## Future Laptop Support

Features deferred until the system runs on a laptop. No implementation timeline.

- **Battery bar module** — percentage + charging indicator via `/sys/class/power_supply`; dropdown with estimated time remaining and power profile selector
- **WiFi bar module** — connection name and signal strength in the bar; dropdown listing nearby networks with connect support (password prompt for new ones)
- **WiFi tile** — `WifiPanel`; toggle WiFi on/off and show connection status; pairs with the WiFi bar module
- **Power profiles** — cycle `power-profiles-daemon` profiles (power-saver / balanced / performance); show active profile as an icon
- **Bluetooth manager** — list paired devices, connect/disconnect, toggle Bluetooth on/off; replaces reaching for `bluetoothctl` or a tray app
