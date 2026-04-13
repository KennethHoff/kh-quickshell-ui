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

---

## Launcher

Searchable application launcher (`quickshell -c kh-launcher`).

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
- ⬜ Window switcher mode — fuzzy search over all open windows by app name or title, across all workspaces and monitors; Enter focuses the window and switches to its workspace
- ⬜ Window switcher mode — fuzzy search over all open windows by app name or title, across all workspaces and monitors; Enter focuses the window and switches to its workspace
- ⬜ Emoji picker mode — fuzzy search emoji by name; Enter copies to clipboard
- ⬜ Snippets mode — text expansion triggered by abbreviation
- ⬜ System commands mode — lock, sleep, reboot, etc. as searchable actions
- ⬜ Color picker *(long term)* — screen dropper; Enter copies hex/rgb to clipboard
- ⬜ File search *(long term)* — fd/fzf over `$HOME`; Enter opens in default app

---

## Bar

A full status bar built in Quickshell, replacing Waybar.

- ✅ Workspaces — show Hyprland workspaces, highlight active, click to switch
- ✅ Workspace preview — hovering a workspace button for 300 ms renders a thumbnail popup; composites per-window `ScreencopyView` captures at Hyprland IPC positions scaled to 240 px wide; disappears on mouse leave; workspace name badge in corner
- ✅ Clock — live HH:mm display, updates every second
- ✅ Plugin system — plugins are authored as `.qml` files and wired in via Nix (`leftPlugins`/`rightPlugins`/`extraPluginDirs`); built at eval time so no runtime module import is needed
- ⬜ IPC support — expose a `bar` IPC target so plugins (or external scripts) can query or mutate bar state; useful for things like toggling a dropdown panel from a keybind
- ⬜ Active window title — display the focused window's app name and title
- ✅ Audio controls — volume level (scroll to adjust) and mute toggle (click) via PipeWire; hidden when no sink is available
- ✅ MPRIS media controls — prev/play-pause/next buttons + artist/title display; shows first active player, hidden when none
- ⬜ Calendar — clock with dropdown calendar on click
- ⬜ Taskbar icons — tray icons for running apps via system tray protocol
- ✅ Tailscale — connection status (`ts: on (N)` / `ts: off`); click to open a dropdown panel showing this machine's IP, all peers with hostname, Tailscale IP, and online/offline indicator; polls `tailscale status --json` every 10 s
- ⬜ Sonarr — badge when new episodes are downloaded; click to open a panel showing recently grabbed episodes and upcoming releases (polls Sonarr API)
- ⬜ Other candidates: network status, battery, notifications indicator

---

## Notification Center

Standalone Quickshell daemon replacing `mako`/`dunst`. Shows incoming toasts
and a persistent history panel (toggle via SUPER or bar button). Groups
notifications by app, supports action buttons, and integrates a Do Not
Disturb toggle.

---

## Audio Mixer

Per-app volume mixing UI, replacing `pavucontrol`. Shows all active audio
streams grouped by app, with per-app volume sliders, mute toggles, and live
visualizations indicating which apps are currently producing audio. Toggle via
IPC/keybind.

---

## OSD

Transient overlay that appears briefly when volume or brightness changes via
keyboard shortcuts, replacing SwayOSD or mako-based notifications. Shows a
progress bar and icon, then fades out automatically.

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
- ⬜ Monitor selection — `--monitor <name|index>` flag to open the window on a specific monitor; defaults to the monitor containing the active window

---

## Undecided

Features that make sense on laptops but have unclear value on a desktop.

- **Bluetooth manager** — list paired devices, connect/disconnect, toggle Bluetooth on/off. Replaces reaching for `bluetoothctl` or a tray app.
- **WiFi picker** — list nearby networks, connect (with password prompt for new ones), show signal strength. Replaces `nm-applet` / `nmtui`.
