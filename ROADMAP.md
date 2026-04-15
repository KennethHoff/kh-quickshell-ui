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

- ⬜ **Configurable terminal** — `kh-launcher` hardcodes `bin.kitty` for apps with `Terminal=true`; should be a Nix option (e.g. `programs.kh-ui.launcher.terminal`) defaulting to nothing, forcing the user to set it
- ⬜ **`kitty` removed from universal `ffi.nix` bins** — `kitty` is injected into every app's `NixBins.qml` even for apps that never launch a terminal (bar, cliphist, view); move it to the launcher-specific `extraBins` instead
- ⬜ **Hyprland-only `exec-once` wiring** — `hm-module.nix` only adds apps to `exec-once` when `wayland.windowManager.hyprland.enable` is true; users on Sway or other compositors get no autostart integration; needs a generic autostart mechanism or at minimum a `programs.kh-ui.autostart` option the user can wire up themselves

---

## Clipboard History

Standalone Quickshell daemon (`quickshell -c kh-cliphist`) with a searchable
list of clipboard entries from `cliphist`. SUPER+V toggles it via IPC.

- ✅ Searchable list; all text entries pre-decoded on open so search matches full content
- ✅ Text entries shown as-is; image entries shown as thumbnails
- ✅ Enter copies the selected entry via `cliphist decode | wl-copy`; entry flashes on copy
- ✅ Search filters: `img:` / `text:` type filter, `'` exact substring match
- ✅ Entry counter in footer
- ✅ Modal insert/normal mode — opens in normal mode; `j`/`k` navigate, `G` bottom, `/` → insert (search focused); Escape → normal mode or closes
- ✅ Full IPC control (`toggle`, `setMode`, `nav`, `key`, `type`)
- ✅ `gg` top, `G` bottom, `Ctrl+D`/`Ctrl+U` half-page scroll
- ✅ Emacs bindings in insert mode — `Ctrl+A`/`E` start/end, `Ctrl+F`/`B` forward/back char, `Ctrl+D` delete forward, `Ctrl+K` delete to end, `Ctrl+W` delete word, `Ctrl+U` delete to line start
- ✅ Detail panel — always-visible side pane (40/60 split); auto-loads selected entry on navigation (120 ms debounce); text with char/word/line count; image with dimensions and file size; `Tab`/`l` enters, `Tab`/`Esc` returns to list; `hjkl`/`w`/`b`/`e`/`W`/`B`/`E` cursor; `0`/`$`/`^` line; `v`/`V`/`Ctrl+V` char/line/block visual select; `h`/`l`/word motions extend char selection; `o`/`O` swap anchor corner; `y` copies selection
- ✅ Fullscreen view — `Enter` from detail (when focused); `Escape` back; full text/image view filling the panel; `y` copies; `hjkl`/`w`/`b`/`e`/`W`/`B`/`E` cursor; `0`/`$`/`^` line; `gg`/`G`/`Ctrl+D`/`U` navigate; `v`/`V`/`Ctrl+V` char/line/block visual select; word motions extend char selection; `o`/`O` swap anchor corner; `y` copies selection
- ✅ Help overlay — `?` opens a popup showing all mode bindings (normal / visual / insert) at once; `/` filters rows inline; popup shrinks to fit matches
- ⬜ Make the help overlay context-aware — visually highlight the section that corresponds to the current mode (e.g. accent the header or show an indicator arrow), so all sections remain visible but the active one is called out
- ✅ Fast search — haystacks pre-processed at load time; filter debounced at 80 ms; full-text cache updated via O(1) index lookup as decode streams in
- ⬜ Insert mode in preview/fullscreen — edit the text content of an entry inline before copying; vim operator bindings (`ciw`, `dw`, `cit`, etc.); `i`/`a`/`I`/`A`/`o`/`O` to enter insert; Escape back to normal; `y` copies the (modified) content
- ✅ Timestamp on entries — first-seen time shown right-aligned on each row ("just now" / "5m ago" / "3h ago" / "2d ago" / "4w ago"); persisted to `$XDG_DATA_HOME/kh-cliphist/meta/timestamps` (id‹TAB›unix_seconds per line); stale IDs pruned on each load; refreshes when the overlay is reopened
- ⬜ Source app attribution — record the active Hyprland window at copy time and show it on each row. Attempted via `wl-paste --watch` + `hyprctl activewindow`, but accuracy is poor: (1) copying from within the cliphist overlay (a WlrLayershell layer surface) always reports the last regular window instead of nothing; (2) every copy-from-overlay creates a new cliphist entry that gets mis-attributed. A reliable implementation would need either a Hyprland plugin/event hook that fires on actual clipboard writes, or a wayland protocol that exposes the source client of a clipboard change.
- ⬜ Auto-paste — close the window and simulate Ctrl+V into the previously focused app via `wtype`
- ✅ Delete from UI — `d` in normal mode deletes the selected entry; `d` in visual mode deletes the selected range; confirms via popup before executing; fade-out animation on deleted entries; cursor repositions to the entry above the deleted one; executed via `cliphist delete`
- ✅ Pinned entries — `p` toggles pin on the selected entry; pinned entries sort to the top of the list (both unfiltered and search-filtered); persisted to `$XDG_DATA_HOME/kh-cliphist/pins` (one entry ID per line); deleting a pinned entry removes it from the pin set; 3 px coloured bar on the left edge of each pinned delegate row
- ⬜ Batch pin in visual mode — `p` in visual mode toggles pin on all entries in the selected range; `handleVisualKey` currently does not handle `p`

---

## Launcher

Searchable application launcher (`quickshell -c kh-launcher`).

### Core

- ✅ Fuzzy search over installed apps by name and description; haystacks are `name + comment`
- ✅ Search filters: `'` exact match, `^` prefix, `$` suffix, `!` negation; space-separated tokens combine with AND
- ✅ Description shown in list (one line below app name)
- ✅ `j`/`k` navigate, `Enter` launch; opens in insert mode (search field focused)
- ✅ Ctrl+1–9 launches the selected app on workspace 1–9 via `hyprctl dispatch exec [workspace N]`
- ✅ `l` / Tab enters actions mode for the selected app (only switches if the app has actions)
- ✅ `j`/`k` navigate actions; `Enter` launches selected action
- ✅ `h` / Esc returns from actions mode to app list
- ✅ Apps with `Terminal=true` run wrapped in kitty
- ✅ Window closes automatically after launching
- ✅ Flash animation (green) when an app or action is launched
- ✅ `?` toggles a searchable help overlay listing all keybinds; help sections are mode-aware (actions vs. normal/insert)
- ✅ App icons — display the icon image (not just name) in the list row
- ✅ App icons in actions mode — show the parent app's icon next to each desktop action entry
- ⬜ Frequency-weighted results — track launch counts per app in a local counter file; blend match score with usage frequency so frequently-launched apps surface higher; decays over time so stale counts don't dominate
- ⬜ Script mode — any external process can push a list of items (label, description, icon, callback command) into the launcher via IPC and receive the user's selection back; makes the launcher infinitely extensible without baking in every mode; Nix option to register named script modes that appear alongside built-in modes

### Modes

- ⬜ Window switcher mode — fuzzy search over all open windows by app name or title, across all workspaces and monitors; Enter focuses the window and switches to its workspace
- ⬜ Emoji picker mode — fuzzy search emoji by name; Enter copies to clipboard
- ⬜ Snippets mode — text expansion triggered by abbreviation
- ⬜ System commands mode — lock, sleep, reboot, etc. as searchable actions
- ⬜ Color picker *(long term)* — screen dropper; Enter copies hex/rgb to clipboard
- ⬜ File search *(long term)* — fd/fzf over `$HOME`; Enter opens in default app

---

## Bar

A full status bar built in Quickshell, replacing Waybar.

### Core

- ✅ Plugin system — plugins are authored as `.qml` files and wired in via Nix (`structure`/`extraPluginDirs`); `BarRow` + `BarSpacer` replace `BarLeft`/`BarRight` for flexible space-between layout; built at eval time so no runtime module import is needed
- ✅ IPC support — each plugin exposes its own IPC target (`bar.volume`, `bar.media`, `bar.workspaces`); dropdowns with `ipcName` set expose `bar.<name>` with `toggle`/`open`/`close`/`isOpen`
- ✅ `BarGroup` plugin — a container plugin that groups any number of child plugins behind a single dropdown button; children are declared inline in `structure` exactly like top-level plugins; any plugin (Volume, Workspaces, custom) can appear inside a group or directly in the bar — placement is independent of plugin type; the button shows a configurable label or icon; implement before hierarchical IPC
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
- ⬜ Hierarchical IPC prefix — add `ipcPrefix` to `BarPlugin` propagated through the parent chain (same mechanism as `barHeight`/`barWindow`); each container appends its segment so a plugin automatically gets a target like `bar1.grouping1.tailscale` without manually specifying it; the root prefix comes from the bar's Nix config entry (e.g. `Bar { ipcName: "top" }`); implement before multi-bar support
- ⬜ Multi-bar support — allow N bars at arbitrary screen edges (top, bottom, left, right); `mkBarConfig` accepts a list of `{ edge, structure }` entries; each bar gets its own `PanelWindow` and generated `BarLayout`; `BarDropdown` opens its popup toward the screen interior so it works on any edge

### Workspaces

- ✅ Workspaces — show Hyprland workspaces, highlight active, click to switch
- ✅ Workspace preview — hovering a workspace button for 300 ms renders a thumbnail popup; composites per-window `ScreencopyView` captures at Hyprland IPC positions scaled to 240 px wide; disappears on mouse leave; workspace name badge in corner
- ⬜ Workspace preview click-through — clicking a window inside the preview thumbnail focuses that specific window directly, not just the workspace
- ⬜ Submap indicator — show the active Hyprland submap name (e.g. `resize`, `passthrough`) in the bar when a non-default submap is active; hidden during normal operation; sourced from the `submap` Hyprland IPC event
- ⬜ Scratchpad indicator — show a count of hidden scratchpad windows; click cycles through them via `hyprctl dispatch togglespecialworkspace`; hidden when scratchpad is empty

### Active Window

- ⬜ Active window title — display the focused window's app name and title

### Clock

- ✅ Clock — live HH:mm display, updates every second
- ⬜ Calendar — clock with dropdown calendar on click; month grid with `h`/`j`/`k`/`l` navigation; unit converter tab (length, weight, temperature, etc.) accessible from the same dropdown
- ⬜ Stopwatch — start/stop/reset via click or IPC; elapsed time shown in the bar while running; hidden when stopped; supports multiple named concurrent stopwatches, each shown as a separate chip in the bar

### Audio

- ✅ Audio controls — volume level (scroll to adjust) and mute toggle (click) via PipeWire; hidden when no sink is available
- ⬜ Microphone mute toggle — mutes the configured virtual PipeWire source node (not the physical device); the setup uses virtual sinks and sources that physical devices and apps route through, so mute targets the virtual node to silence all inputs simultaneously; configured via Nix with the target node name
- ⬜ Output device quick switch — right-click or dropdown on the volume widget to select between available PipeWire sinks without opening the full Audio Mixer

### Media (MPRIS)

- ✅ MPRIS media controls — prev/play-pause/next buttons + artist/title display; shows first active player, hidden when none
- ⬜ MPRIS multi-source — when more than one player is active, show a dropdown (or similar) to select which source is displayed rather than always picking the first one
- ⬜ Seek bar — progress indicator showing position within the current track; click or drag to seek; sourced from MPRIS `Position` and `Length` metadata
- ⬜ Album art — thumbnail of the current track's artwork sourced from MPRIS `mpris:artUrl`; shown alongside artist/title
- ⬜ Shuffle / repeat toggles — buttons reflecting and toggling the MPRIS `Shuffle` and `LoopStatus` properties

### System Tray

- ✅ Taskbar icons — tray icons via StatusNotifierItem protocol; left click activates, right click shows native context menu via `display()`; hidden when no items present
- ⬜ Overflow bucket — when icon count exceeds a configured limit, least-recently-interacted icons collapse into an expander chip; click expander to reveal the overflow tray

### Tailscale

- ✅ Tailscale tile — `TailscalePanel` toggles `tailscale up`/`down` on click; status updates reactively after the command completes; exposes `connected`, `selfIp`, and `peers` for use in `TailscalePeers`
- ⬜ Exit node selection — list exit-node-capable peers; click one to run `tailscale set --exit-node=<ip>`; highlight active exit node; click again (or a clear button) to disable
- ⬜ Advertise exit node toggle — button to run `tailscale set --advertise-exit-node` on/off for the local machine
- ⬜ Shields-up toggle — toggle `tailscale set --shields-up` to block incoming connections; reflected in the tile UI

### Sonarr

- ⬜ Sonarr — badge when new episodes are downloaded; click to open a panel showing recently grabbed episodes and upcoming releases (polls Sonarr API)

### Network

- ⬜ Network status — show active wired interface name and link state via nmcli; hidden when disconnected

### System Stats

- ⬜ CPU usage — utilisation % across all cores; updates on a short interval; hidden when idle below a threshold
- ⬜ RAM usage — used/total memory; sourced from `/proc/meminfo`
- ⬜ GPU stats — utilisation % and VRAM used/total for AMD (`/sys/class/drm`) or Nvidia (`nvml`); hidden when idle below a threshold
- ⬜ Disk usage — used/total for one or more configured mount points (e.g. `/`, `/home`)
- ⬜ Temperature — CPU and GPU temps via `/sys/class/hwmon`; colour-coded (cool → warm → hot); shown alongside the corresponding CPU/GPU stat

### Docker

- ⬜ Docker status — running container count badge; click opens a panel listing all containers with name, image, and status
- ⬜ Container actions — start/stop/restart individual containers from the panel
- ⬜ Log tail — select a container in the panel and stream its logs inline (`docker logs -f`)

### Aspire

- ⬜ Aspire status — running service count badge sourced from `aspire ps`; hidden when no Aspire session is active
- ⬜ Aspire panel — click to open a list of all services with their state, endpoint URLs, and health; click a URL to open in browser
- ⬜ Resource drill-down — select a service to tail its structured logs inline

### Notifications

- ⬜ Notifications indicator — unread badge count in the bar; click opens the Notification Center panel

---

## Notification Center

Standalone Quickshell daemon replacing `mako`/`dunst`. Shows incoming toasts
and a persistent history panel (toggle via SUPER or bar button). Groups
notifications by app, supports action buttons, and integrates a Do Not
Disturb toggle.

- ⬜ Incoming toasts — transient popup per notification with app icon, summary, and body; auto-dismisses after timeout
- ⬜ Persistent history panel — toggle via SUPER or bar button; all notifications since last clear, grouped by app; dismiss individual or all
- ⬜ Action buttons — render notification action buttons; click executes the action via DBus reply
- ⬜ Do Not Disturb toggle — suppress toasts while enabled; history still accumulates; togglable from the bar and the panel
- ⬜ Urgency handling — `critical` notifications ignore DND and persist until dismissed; `low` notifications skip the toast entirely

---

## Audio Mixer

Per-app volume mixing UI, replacing `pavucontrol`. Shows all active audio
streams grouped by app, with per-app volume sliders, mute toggles, and live
visualizations indicating which apps are currently producing audio. Toggle via
IPC/keybind.

- ⬜ Stream list — all active PipeWire audio streams grouped by app, with app icon and name
- ⬜ Per-app volume slider — drag or scroll to adjust individual stream volume
- ⬜ Per-app mute toggle — click to mute/unmute a stream
- ⬜ Live activity indicator — VU meter or pulse animation showing which streams are currently producing audio
- ⬜ Output device selector — choose the default sink from a list of available PipeWire sinks

---

## OSD

Transient overlay that appears briefly when volume or brightness changes via
keyboard shortcuts, replacing SwayOSD or mako-based notifications. Shows a
progress bar and icon, then fades out automatically.

- ⬜ Volume OSD — appears on volume up/down/mute shortcuts; shows icon and progress bar reflecting the new level
- ⬜ Brightness OSD — appears on brightness shortcuts; same layout as volume OSD
- ⬜ Auto-dismiss — fades out after ~2 s; timer resets if the value changes again before dismissal
- ⬜ IPC trigger — `qs ipc call osd show --value <0–100> --icon <name>` so any keybind daemon can drive it

---

## File Viewer

One-shot viewer for arbitrary text or image files. Accepts N file arguments
or stdin; shows all files side-by-side with Tab to cycle focus between panes.

- ✅ `nix run .#kh-view -- <file> [<file2> ...]` or `<cmd> | nix run .#kh-view`
- ✅ Image detection by extension (png/jpg/jpeg/gif/webp/bmp/svg)
- ✅ N files shown side-by-side in equal-width panes; Tab cycles focus; active divider highlights
- ✅ Per-pane: `hjkl`/`w`/`b`/`e`/`W`/`B`/`E` cursor; `0`/`$`/`^` line; `gg`/`G`/`Ctrl+D`/`U` scroll; `v`/`V`/`Ctrl+V` char/line/block visual select; word motions extend char selection; `y` copies selection
- ✅ `q`/`Esc` quits
- ✅ Fullscreen mode — `f` toggles single fullscreen pane; `h`/`l` steps through all loaded files; dot indicators at bottom center show position
- ✅ IPC support — `target: "viewer"`; `next()`/`prev()`/`seek(n)`/`quit()`/`setFullscreen(bool)`/`key(k)`; readable props `currentIndex`, `count`, `fullscreen`, `hasPrev`, `hasNext`; enables scripted slideshows and library review workflows
- ⬜ Optional pane labels — `kh-view` accepts label metadata alongside each file (e.g. via a sidecar format or extended list protocol); each pane optionally shows a header bar with a short name and description; used by the `screenshot` skill to annotate review sessions with context about what each shot shows and what to look for *(implement together with Dev Tooling → screenshot skill labels)*
- ⬜ Monitor selection — `--monitor <name|index>` flag to open the window on a specific monitor; defaults to the monitor containing the active window
- ⬜ Syntax highlighting — detect language from file extension and apply token-level colouring using Tree-sitter or `bat` themes; code files become significantly easier to read
- ⬜ Directory and glob input — `kh-view ./images/` opens all recognised media files in a directory; `kh-view ./images/*.png` expands the glob; files sorted by name by default
- ⬜ Image gallery mode — when all panes are images, `g` toggles a grid thumbnail view; `h`/`j`/`k`/`l` navigate the grid; Enter opens the selected image in fullscreen; natural entry point when opening a directory of images

---

## Process Manager

Keyboard-driven process viewer, replacing `htop`. Shows running processes
sortable by CPU, RAM, or name; `k` kills the selected process. Toggle via
keybind or IPC, or open by clicking a System Stats bar widget.

- ⬜ Process list — all running processes with PID, name, CPU %, and RAM usage; sourced from `/proc`
- ⬜ Sort — cycle sort column with `s`; toggle ascending/descending with `S`
- ⬜ Filter — `/` to search by process name
- ⬜ Kill — `k` sends SIGTERM to the selected process; `K` sends SIGKILL; confirmation popup before executing
- ⬜ Tree view — `t` toggles parent/child process tree layout
- ⬜ IPC trigger — openable from bar widget clicks on CPU or RAM

---

## Diff Viewer

Side-by-side two-pane file diff. `kh-diff file1 file2` or pipe from `git diff`
/ `diff`. Keyboard-driven; vim motion navigation. Natural sibling to File Viewer.

- ⬜ Two-pane diff — left/right panes showing old and new versions with added/removed/changed lines highlighted
- ⬜ Pipe input — `git diff | kh-diff` or `diff -u a b | kh-diff` reads unified diff from stdin and renders it
- ⬜ `]c` / `[c` jump to next/previous change hunk
- ⬜ `Tab` cycles focus between panes; `hjkl` scroll within a pane; `gg`/`G`/`Ctrl+D`/`U` navigate
- ⬜ `y` copies the selected hunk or visual selection
- ⬜ IPC support — same pattern as File Viewer

---

## Screenshot

Region/window/fullscreen capture tool, replacing Flameshot. Captures via
`grim`/`slurp`; result goes to clipboard or is saved to a file. Triggered
via keybind or IPC.

- ⬜ Region capture — `slurp` crosshair selection; result copied to clipboard via `wl-copy`
- ⬜ Fullscreen capture — capture the focused monitor immediately
- ⬜ Window capture — click to select a window; captures its geometry via Hyprland IPC
- ⬜ Save to file — write to `$XDG_PICTURES_DIR/Screenshots/` with a timestamp filename in addition to clipboard copy
- ⬜ Annotation layer — draw arrows, boxes, and text over the capture before copying/saving
- ⬜ IPC trigger — `qs ipc call screenshot <region|fullscreen|window>` so any keybind daemon can drive it

---

## Dev Tooling

Improvements to the Claude skills and agentic development workflow.

- ⬜ `screenshot` skill passes labels to `kh-view` — once kh-view supports optional pane labels, update the skill to supply a name and short description for each shot (what app/state it shows, what to look for); makes review sessions self-documenting without manual annotation *(implement together with File Viewer → optional pane labels)*
- ⬜ Headless Hyprland for workspace preview screenshots — `kh-bar`'s Workspaces plugin uses
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
