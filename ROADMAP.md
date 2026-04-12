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
- ✅ Modal insert/normal mode — opens in insert mode (search focused); Escape → normal mode with `j`/`k` navigation, `G` bottom, `/` or printable → insert; Escape closes
- ✅ Full IPC control (`toggle`, `setMode`, `nav`, `key`, `type`)
- ✅ `gg` top, `G` bottom, `Ctrl+D`/`Ctrl+U` half-page scroll
- ⬜ Detail panel — `l` to open, `h` to close; text preview with char/word/line count; image preview with dimensions and file size
- ⬜ Fullscreen view — `Enter` from detail; `Escape` back
- ⬜ Help overlay — `?` toggles a searchable list of keybinds
- ⬜ Asynchronous search — filtering is currently synchronous and blocks the UI while typing
- ⬜ Timestamp on entries
- ⬜ Source app attribution — record active Hyprland window (`hyprctl activewindow`) at copy time, stored in a side-store alongside the cliphist entry (needs a storage solution that doesn't corrupt binary clipboard data)
- ⬜ Auto-paste — close the window and simulate Ctrl+V into the previously focused app via `wtype`
- ⬜ Delete from UI — remove individual entries via Delete key, delegating to `cliphist delete`
- ⬜ Pinned entries — star entries to keep them permanently at the top, surviving clipboard history rotation

---

## Launcher

Searchable application launcher (`quickshell -c kh-launcher`).

- ✅ Fuzzy search over installed apps by name and description
- ✅ Search filters: `'` exact match, `^` prefix, `$` suffix, `!` negation; space-separated tokens combine with AND
- ✅ App icon and description shown in list
- ✅ Up/Down to navigate; Enter to launch (to be replaced by `j`/`k`)
- ✅ Ctrl+1–9 launches the selected app on workspace 1–9
- ✅ Tab enters actions mode for the selected app (to be replaced by `l`; shown only when actions exist)
- ✅ Up/Down to navigate actions; Enter to launch selected action (to be replaced by `j`/`k`)
- ✅ Tab or Esc returns from actions mode to app list (to be replaced by `h`/Esc)
- ✅ Apps with `Terminal=true` run wrapped in kitty
- ✅ Window closes automatically after launching
- ✅ Flash animation when an app or action is launched
- ✅ `?` toggles a searchable help overlay listing all keybinds
- ⬜ Window switcher mode — fuzzy search over all open windows by app name or title, across all workspaces and monitors; Enter focuses the window and switches to its workspace
- ⬜ Emoji picker mode — fuzzy search emoji by name; Enter copies to clipboard
- ⬜ Snippets mode — text expansion triggered by abbreviation
- ⬜ System commands mode — lock, sleep, reboot, etc. as searchable actions
- ⬜ Color picker *(long term)* — screen dropper; Enter copies hex/rgb to clipboard
- ⬜ File search *(long term)* — fd/fzf over `$HOME`; Enter opens in default app

---

## Bar

A full status bar built in Quickshell, replacing Waybar.

- ⬜ Workspaces — show Hyprland workspaces, highlight active, click to switch
- ⬜ Active window title — display the focused window's app name and title
- ⬜ Audio controls — volume level and mute toggle via PipeWire/WirePlumber
- ⬜ MPRIS media controls — play/pause, track title from any MPRIS-compatible player
- ⬜ Calendar — clock with dropdown calendar on click
- ⬜ Taskbar icons — tray icons for running apps via system tray protocol
- ⬜ Tailscale — connection status; click to open a panel showing connected peers, their IPs, and online/offline state
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

## Undecided

Features that make sense on laptops but have unclear value on a desktop.

- **Bluetooth manager** — list paired devices, connect/disconnect, toggle Bluetooth on/off. Replaces reaching for `bluetoothctl` or a tray app.
- **WiFi picker** — list nearby networks, connect (with password prompt for new ones), show signal strength. Replaces `nm-applet` / `nmtui`.
