# Quickshell Roadmap

Features to implement. Each entry becomes its own Quickshell component or launcher plugin.

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
- [3] ✅ **Compositor-agnostic autostart** — `hm-module.nix` registers each enabled component as a `systemd.user.services` unit bound to `graphical-session.target`; works on any compositor with systemd-user integration, adds `Restart=on-failure` for crash recovery, and benefits from Home Manager's `sd-switch` strategy (services auto-restart when the store path changes on rebuild)

---

## Clipboard History

Standalone Quickshell daemon (`quickshell -c kh-cliphist`) with a searchable
list of clipboard entries from `cliphist`. SUPER+V toggles it via IPC.

### Core

- [1] ✅ Searchable list — all text entries pre-decoded on open so search matches full content
- [2] ✅ Text entries shown as-is; image entries shown as thumbnails
- [3] ✅ Enter copies the selected entry via `cliphist decode | wl-copy`; entry flashes on copy
- [4] ✅ Search filters — `img:` / `text:` type filter, `'` exact substring match
- [5] ✅ Entry counter in footer
- [6] ✅ Fast search — haystacks pre-processed at load time; filter debounced at 80 ms; full-text cache updated via O(1) index lookup as decode streams in
- [7] ✅ IPC — `toggle`, `setMode`, `nav`, `key`, `type`

### Navigation

- [1] ✅ Modal insert/normal mode — opens in normal mode; `j`/`k` navigate, `G` bottom, `/` → insert (search focused); Escape → normal mode or closes
- [2] ✅ `gg` top, `G` bottom, `Ctrl+D`/`Ctrl+U` half-page scroll
- [3] ✅ Emacs bindings in insert mode — `Ctrl+A`/`E` start/end, `Ctrl+F`/`B` forward/back char, `Ctrl+D` delete forward, `Ctrl+K` delete to end, `Ctrl+W` delete word, `Ctrl+U` delete to line start

### Detail Panel

- [1] ✅ Detail panel layout — always-visible side pane (40/60 split); auto-loads selected entry on navigation (120 ms debounce)
- [2] ✅ Detail panel text metadata — char/word/line count shown for text entries
- [3] ✅ Detail panel image metadata — dimensions and file size shown for image entries
- [4] ✅ Detail panel navigation — `Tab`/`l` enters the panel; `Tab`/`Esc` returns to the list
- [5] ✅ Detail panel cursor and motions — `hjkl`/`w`/`b`/`e`/`W`/`B`/`E`; `0`/`$`/`^` line
- [6] ✅ Detail panel visual select — `v`/`V`/`Ctrl+V` char/line/block; word motions extend char selection; `o`/`O` swap anchor corner; `y` copies selection
- [7] ⬜ Insert mode in detail panel — edit text content inline before copying; vim operator bindings (`ciw`, `dw`, etc.); `i`/`a`/`I`/`A`/`o`/`O` to enter insert; Escape back to normal; `y` copies the modified content

### Fullscreen View

- [1] ✅ Fullscreen view — `Enter` from detail opens; `Escape` returns; full text/image filling the panel
- [2] ✅ Fullscreen navigation — `hjkl`/`w`/`b`/`e`/`W`/`B`/`E` cursor; `0`/`$`/`^` line; `gg`/`G`/`Ctrl+D`/`U` navigate
- [3] ✅ Fullscreen visual select — `v`/`V`/`Ctrl+V` char/line/block; word motions extend; `o`/`O` swap anchor corner; `y` copies selection
- [4] ⬜ Insert mode in fullscreen — same as detail panel insert mode, for the fullscreen view

### Help

- [1] ✅ Help overlay — `?` opens a popup showing all mode bindings (normal / visual / insert) at once; `/` filters rows inline; popup shrinks to fit matches
- [2] ⬜ Context-aware help — visually highlight the section corresponding to the current mode; all sections remain visible but the active one is called out

### Entry Management

- [1] ✅ Delete single entry — `d` in normal mode; confirmation popup; executes via `cliphist delete`; cursor repositions to the entry above
- [2] ✅ Delete range in visual mode — `d` deletes all entries in the selected range; confirmation popup before executing
- [3] ✅ Delete animation — fade-out on deleted entries
- [4] ✅ Pin toggle — `p` toggles pin on the selected entry
- [5] ✅ Pinned entries sort to top — pinned entries appear at the top of both unfiltered and search-filtered lists
- [6] ✅ Pin persistence — persisted to `$XDG_DATA_HOME/kh-cliphist/pins` (one entry ID per line); deleting a pinned entry removes it from the pin set
- [7] ✅ Pin visual indicator — 3 px coloured bar on the left edge of each pinned delegate row
- [8] ⬜ Batch pin in visual mode — `p` in visual mode toggles pin on all entries in the selected range

### Metadata

- [1] ✅ Timestamp on entries — first-seen time shown right-aligned on each row ("just now" / "5m ago" / "3h ago" / "2d ago" / "4w ago"); persisted to `$XDG_DATA_HOME/kh-cliphist/meta/timestamps`; stale IDs pruned on each load; refreshes on reopen
- [2] ⬜ Source app attribution — record the active Hyprland window at copy time and show it on each row. Attempted via `wl-paste --watch` + `hyprctl activewindow`, but accuracy is poor: (1) copying from within the cliphist overlay always reports the last regular window; (2) every copy-from-overlay creates a mis-attributed entry. Needs a Hyprland plugin/event hook or a Wayland protocol that exposes the source client of a clipboard change.

### Integration

- [1] ⬜ Auto-paste — close the window and simulate Ctrl+V into the previously focused app via `wtype`

---

## Launcher

Extensible modal launcher (`quickshell -c kh-launcher`). Each **launcher plugin**
registers a named item source (apps, open windows, emoji, …); `]` / `[` cycles
between them, Enter picks an item. The built-in **Apps** plugin has no
special-casing — it is registered alongside user-defined plugins through the
same contract.

### Core

Plugin-agnostic infrastructure shared by every plugin.

- [1] ✅ Fuzzy search over item `label + description`
- [2] ✅ Search filters: `'` exact match, `^` prefix, `$` suffix, `!` negation; space-separated tokens combine with AND
- [3] ✅ Description shown in list (one line below the label)
- [4] ✅ `j`/`k` navigate, `Enter` confirm; opens in insert mode (search field focused)
- [5] ✅ Window closes automatically after a selection
- [6] ✅ Flash animation (green) on selection
- [7] ✅ `?` toggles a searchable help overlay listing all keybinds; help sections are state-aware (actions vs. normal/insert)
- [8] ✅ Per-item icons — display the icon image (not just the label) in the list row
- [9] ✅ Plugin switching — `]` / `[` cycle plugins; click a plugin chip to jump directly; `activatePlugin` / `nextPlugin` / `prevPlugin` / `returnToDefault` via IPC
- [10] ✅ Script plugins — any external process can push items (label, description, icon, callback, optional id) into a named plugin via TSV stdout or IPC and receive the user's selection back; makes the launcher infinitely extensible without baking in every plugin; Nix option `programs.kh-ui.launcher.scriptPlugins` registers named plugins that appear alongside built-in ones, and runtime IPC (`registerPlugin` / `addItem` / `itemsReady`) supports ad-hoc push-based plugins
- [11] ⬜ Combi plugin *(depends on 10)* — a named plugin that concatenates results from multiple sources (e.g. apps + open windows + system commands) into one unified search, rofi-`combi`-style; each source is tagged so rows show their origin (`[app]` / `[window]` / …) and can carry a per-source ranking bias; different Enter semantics per source (launch vs. focus vs. execute) routed by the source tag; opt-in — default plugins stay single-source to keep rankings and Enter behaviour coherent
- [12] ✅ Plugin-owned keybindings — Core (`PluginList.qml`) only handles navigation (`j`/`k`, `gg`, `G`, `Ctrl+D`/`U`, `[`/`]`, `/`, `?`, `Esc`/`q`) and emits `pluginActionRequested(kb)` when a plugin-declared keybinding matches. The orchestrator (`kh-launcher.qml`) owns the dispatcher: `run` substitutes `{callback}` in the plugin's shell template and pipes to bash; `enterActionsMode` / `enterNormalMode` / `close` are the only mode/lifecycle primitives. Apps plugin declares `Ctrl+1..9 → hyprctl dispatch exec [workspace N] {callback}` as plain shell templates — the hyprctl knowledge is entirely plugin-local; Core has no concept of workspaces. Emoji and window plugins declare only `Return → {callback}`. Each keybinding carries its own `?`-overlay help row inline via `helpKey` / `helpDesc`, so keybindings are the single source of truth per plugin (no parallel `helpEntries` list). IPC `launchOnWorkspace(n)` removed — plugin keybindings cover it declaratively. Docs: `docs/launcher-plugins.md` concept table + full IPC reference
- [13] ⬜ Plugin-owned ranking / frecency — the decayed-launch counter (`$XDG_DATA_HOME/kh-launcher/meta/frecency`, `3·log2(1+count)` boost, 14-day half-life) is currently the only ranking signal available and, in practice, only the apps plugin opts in. Other plugins want different semantics: window switcher should rank by recent-focus order sourced from Hyprland, system commands barely need ranking, snippets probably want alphabetical. Expose ranking as a plugin-provided hook (or a named strategy) rather than a single shared counter, so each plugin chooses its own scoring and tie-breaker
- [14] ✅ Plugin label distinct from IPC key — every plugin has a stable attribute-name *key* (what IPC targets: `activatePlugin`, `removePlugin`, `listPlugins` output) and a human-facing `label` that drives the chip text. Label defaults to the key when empty, so existing plugins need no change. Set it via the `label` field on Nix-registered plugins (built-in `apps.nix`, `hyprland-windows.nix`, or entries under `programs.kh-ui.launcher.scriptPlugins.<name>.label`) or as the 6th positional argument to `registerPlugin` at runtime. Motivating use case: a compositor-qualified key like `hyprland-windows` can present itself on the chip as simply `Windows`, leaving room for peer plugins (`sway-windows`, …) without an identifier collision. Docs: `docs/launcher-plugins.md` concept table + IPC reference

### Plugins

#### Apps *(default, built-in)*

Fuzzy search over installed `.desktop` applications; Enter launches.

- [1] ✅ Haystack is `name + comment` from each `.desktop` entry
- [2] ✅ App icons in the list row — XDG icon resolution with SVG / PNG fallback via the scan script; fallback glyph is the label's first letter
- [3] ✅ Apps with `Terminal=true` run wrapped in the configured terminal (`bin.terminal`)
- [4] ✅ Ctrl+1–9 launches the selected app on workspace 1–9 via `hyprctl dispatch exec [workspace N] <command>` *(currently wired into Core's launch path — see Core [12])*
- [5] ✅ Frecency ranking — per-app decayed launch counter persisted at `$XDG_DATA_HOME/kh-launcher/meta/frecency` (via shared `MetaStore`); fuzzy score gets a `3·log2(1+count)` boost so frequently-launched apps surface higher without swamping strong prefix matches; each count decays with a 14-day half-life; empty query sorts by decayed count then name *(currently the only ranking hook any plugin can use — see Core [13])*
- [6] ✅ `l` / Tab enters actions state for the selected app (only switches if the app has desktop actions)
- [7] ✅ `j`/`k` navigate actions; `Enter` launches the selected action; `h` / Esc returns to the app list
- [8] ✅ Action rows show the parent app's icon next to each desktop action

#### Window switcher

Plugins in this section are compositor-specific — each compositor needs its own
data source and focus dispatch, so they ship as separate plugins rather than
one abstracted "window switcher".

- [1] ✅ **Hyprland window switcher** — Hyprland-only. IPC key `hyprland-windows`, chip label `Windows` (via the new plugin-`label` concept — stable key stays compositor-qualified for future peers, but the UI stays terse). Fuzzy search over all open windows by app name or title, across all workspaces and monitors; Enter runs `hyprctl dispatch focuswindow address:<addr>` which focuses the window and switches to its workspace; windows are listed most-recently-focused first (Hyprland `focusHistoryID`); icons resolved from each window's WM class via `StartupWMClass` in `.desktop` files with a fallback to the class name and then `application-x-executable`; exits cleanly with no items outside a Hyprland session
- [2] ⬜ Per-item keybinds for window lifecycle actions — `Quit` (graceful close via `hyprctl dispatch closewindow address:<addr>`), `Force Quit` (send `SIGKILL` to the window's PID), and similar (e.g. minimize, move to workspace). Surfaced either as desktop-action-style rows entered via `l` / Tab, or as direct shortcuts from the window list

#### Emoji picker

- [1] ✅ Fuzzy search emoji by name; Enter copies to clipboard — built-in plugin keyed `emoji`, chip label `Emoji`. Glyph list sourced from `pkgs.unicode-emoji` (`emoji-test.txt`, v17.0, `fully-qualified` status only) joined with `pkgs.cldr-annotations` (`en.xml`, v48.2) for authoritative multilingual keywords; same data source GNOME/GTK pickers use. The join happens once at Nix eval time into a TSV so the plugin scan script is a trivial `cat`. The emoji glyph renders in the 32 px icon slot via a new plugin-owned `iconDelegate` mechanism: each plugin names a QML component (here `LauncherIconGlyph.qml`, shared alongside `LauncherIconFile.qml` for file-path plugins), and `PluginList.qml` instantiates it through a `Loader` with `iconData` / `labelText` bound from the item. Label holds just the canonical name; keywords flow through the description field. Callback copies to the Wayland clipboard via `printf '%s' '<emoji>' | wl-copy` (no trailing newline). Frecency enabled so frequently-copied emoji surface first. ~3944 items under Unicode 17.0

#### Snippets

- [1] ⬜ Text expansion triggered by abbreviation

#### System commands

- [1] ⬜ Lock, sleep, reboot, etc. as searchable actions

#### Color picker *(long term)*

- [1] ⬜ Screen dropper; Enter copies hex/rgb to clipboard

#### File search *(long term)*

- [1] ⬜ `fd`/`fzf` over `$HOME`; Enter opens in default app

---

## Bar

A full status bar built in Quickshell, replacing Waybar.

### Core

- [1] ✅ Plugin authoring system — plugins are `.qml` files wired in via Nix (`structure`/`extraPluginDirs`); built at eval time so no runtime module import is needed
- [2] ✅ Per-plugin IPC targets — each plugin sets `ipcName: "<segment>"` and writes `IpcHandler { target: ipcPrefix }`; `BarPlugin` scopes `ipcPrefix = parentPrefix + "." + ipcName` so the target resolves via QML lexical scope (e.g. `bar.volume`, `bar.workspaces`)
- [3] ✅ Dropdown IPC — dropdowns with `ipcName` set expose `bar.<name>` with `toggle`/`open`/`close`/`isOpen`
- [4] ✅ `BarGroup` plugin — a container plugin that groups any number of child plugins behind a single dropdown button; children are declared inline in `structure` exactly like top-level plugins; any plugin (Volume, Workspaces, custom) can appear inside a group or directly in the bar — placement is independent of plugin type; the button shows a configurable label or icon; implement before hierarchical IPC
- [5] ✅ Hierarchical IPC prefix — `ipcPrefix` propagates through `BarPlugin` → `BarRow` → `BarDropdown.col` via parent chain walk; `BarPlugin`, `BarGroup`, `BarDropdown`, and `BarTooltip` each append their own `ipcName` segment via the shared `parentPrefix + "." + ipcName` pattern so nested targets like `bar.controlcenter.tailscale` or `bar.workspaces.ws1` fall out automatically; root prefix is `ipcName` from `mkBarConfig` (default `"bar"`), exposed as `programs.kh-ui.bar.ipcName` in the hm-module; `EthernetPanel` and `TailscalePanel` converted from `BarControlTile` to `BarPlugin` base so they join the prefix chain regardless of popup nesting depth
- [6] ⬜ Plugin error surface — a standard mechanism for plugins to report failures to the user; currently any subprocess that exits non-zero is silently ignored and the plugin stays in its last known state; needs a shared primitive (e.g. a visual error state on `BarControlTile`, a toast, or a bar-level error badge) so plugins like `TailscalePanel` can surface "toggle failed" instead of doing nothing
- [7] ✅ Multi-monitor support (one top-edge bar per screen) — `programs.kh-ui.bar.instances.<ipcName> = { screen; structure; }` declares any number of bars keyed by a lowercase identifier (regex `^[a-z][a-z0-9]*$`) that doubles as the bar's root IPC target. `bar-config.nix` emits one `BarLayout_<ipcName>.qml` per instance plus a single `BarInstances.qml` registry; `apps/kh-bar.qml` holds a reactive `liveInstances` list filtered against `Quickshell.screens`, and a `Variants` over that list spawns a `PanelWindow` for each matched screen — no null fallback, the delegate only exists when the configured output is actually present. Per-bar root IPC exposes `getHeight()` / `getWidth()` / `getScreen()`. Screen hotplug = silent-skip-and-appear-on-connect: a configured screen that isn't plugged in simply doesn't produce a delegate; plugging it in does. Eval-time validation: ipcName regex; unique `screen` across instances; non-empty screen (via `strMatching ".+"`); warning when `bar.enable = true` and `instances = {}`. Primitive fallbacks that used to silently default to `"bar"` (BarPlugin, BarRow, BarDropdown) now return `""` so `IpcHandler.enabled` guards fail loudly — there is no implicit root ipcName any more
- [7a] ⬜ Bars on non-top edges (bottom, left, right) — extend **[7]** with an `edge` field on each instance. Bottom is the simplest next step: just flip the `PanelWindow` anchors, the divider position, and `BarDropdown` / `BarTooltip` popup Y-anchor. Left / right need more — orientation-aware authoring primitives (`BarColumn` instead of `BarRow`, vertical `BarSpacer` / `BarPipe`, plugins that measure height as well as width) — so should land separately from bottom
- [8] ✅ Root bar IPC — `ipcPrefix` itself (e.g. `bar`, `dev-bar`) exposes `getHeight()`/`getWidth()` returning the visible footprint in pixels, with `getHeight()` summing the bar's own height and the tallest currently-open dropdown popup so callers can size overlays or screenshot crops without hardcoded values; implemented inside the generated `BarLayout.qml` by walking children for visible popups
- [9] ✅ Service environment injection — `programs.kh-ui.bar.environment` (plaintext attrset) and `programs.kh-ui.bar.environmentFiles` (list of paths, typically sops/agenix) pass env vars to the `kh-bar` systemd service; plugins read via `Quickshell.env()`; follows the nixpkgs convention used by nginx/gitea/servarr so new plugins needing secrets require no special Nix scaffolding

### Building Blocks

Authoring primitives that make up a bar structure. Plugins compose these
rather than raw QtQuick types so layout, IPC prefix propagation, and theme
access stay consistent.

- [1] ✅ `BarPlugin` base type — every plugin extends it; `implicitWidth` sizes the plugin, `implicitHeight` tracks `barHeight`, `barWindow` is inherited from the parent chain, and `ipcPrefix` walks the parent chain (skipping plain `Row`/`RowLayout`) then appends the plugin's own `ipcName` segment so nesting in any container produces a correctly scoped IPC target
- [2] ✅ `BarRow` — full-width `RowLayout` row; carries `ipcPrefix` so children resolve IPC targets correctly
- [3] ✅ `BarSpacer` — flexible spacer filling remaining width; place between plugin clusters to push them apart (CSS space-between equivalent)
- [4] ✅ `BarPipe` — thin vertical separator; defaults to `base03`, 18 px tall, 6 px side margins; `pipeColor` / `pipeHeight` / margin props override per use
- [5] ✅ `BarGroup` — dropdown button wrapping arbitrary children as panel content; any plugin (Volume, Workspaces, custom) can live inside a group or at the top level with no plugin-side changes; see **Core [4]** for composition semantics and hierarchical IPC behaviour
- [6] ✅ `BarDropdown` — generic dropdown primitive used under the hood by `BarGroup`; exposes `toggle`/`open`/`close`/`isOpen` via IPC when `ipcName` is set (see **Core [3]**)
- [7] ✅ `BarText` — theme-styled text primitive exposing `normalColor` / `warnColor` / `errorColor` / `mutedColor` so threshold colouring doesn't need a `NixConfig { id: cfg }` at every call site
- [8] ✅ `BarIcon` — same contract as `BarText` but loads the bundled nerd-font via `FontLoader` so PUA codepoints (bell, tv, etc.) render deterministically regardless of the user's system fontconfig
- [9] ✅ `BarTooltip` — generic hover tooltip primitive; default content slot accepts any QML children (text, icons, rich content), opens on hover-after-delay (default 300 ms, matches the workspace-preview convention) and closes on mouse leave via `HoverHandler` on its parent. Positions below the bar (anchored to the parent's horizontal centre, clamped to screen edges) so the bar chrome isn't occluded. `active: false` disables without removing from the tree (bind it to `hasError` etc. so a tooltip exists but only triggers when there's something worth saying). Optional `ipcName` exposes `<ipcPrefix>.<ipcName>` with `pin` / `unpin` / `togglePin` / `isPinned` / `isVisible` — pin is an independent visibility input (`visible = (hoverShown OR pinned) AND active`) so keyboard/IPC workflows can show a tooltip without a physical hover. Driving use case: make plugin errors (`hasError` / `getError()` on peers) readable at a glance instead of only through IPC; unblocks the visible half of **Core [6]** plugin error surface
- [10] ✅ `BarHorizontalDivider` — thin 1 px horizontal separator (formerly `DropdownDivider`, renamed and generalised). Spans the parent's width by default; theme-aware default colour (`_cfg.color.base02`), configurable via `dividerColor` and `dividerHeight`. Used between sections in `BarDropdown` panels (e.g. `TailscalePeers`) and between rows in `BarTooltip` content
- [11] ✅ `BarControlTile` — styled toggle-pill primitive for custom panel tiles (label, sublabel, active/pending states, theme colours); used by `TailscalePanel` and `EthernetPanel`. Formerly `ControlTile`, renamed for the `Bar*` prefix convention
- [12] ✅ `BarDropdownHeader` / `BarDropdownItem` — muted section heading + row-with-dot-and-two-labels primitives intended for `BarDropdown` panel content; formerly `DropdownHeader` / `DropdownItem`

### Workspaces

- [1] ✅ Workspace display — show Hyprland workspaces; highlight the active workspace
- [2] ✅ Workspace click to switch — click a workspace button to switch to it
- [3] ✅ Workspace preview on hover — hovering a button for 300 ms shows a thumbnail popup; disappears on mouse leave
- [4] ✅ Workspace preview thumbnails — composites per-window `ScreencopyView` captures at Hyprland IPC positions; scaled to 240 px wide
- [5] ✅ Workspace preview badge — workspace name badge in the corner of the thumbnail
- [6] ⬜ Workspace preview click-through — clicking a window inside the preview thumbnail focuses that specific window directly, not just the workspace
- [7] ⬜ Submap indicator — show the active Hyprland submap name (e.g. `resize`, `passthrough`) in the bar when a non-default submap is active; hidden during normal operation; sourced from the `submap` Hyprland IPC event
- [8] ⬜ Scratchpad indicator — show a count of hidden scratchpad windows; click cycles through them via `hyprctl dispatch togglespecialworkspace`; hidden when scratchpad is empty
- [9] ✅ Per-delegate preview popup via `BarTooltip` — each workspace delegate owns its own `BarTooltip` with the `ScreencopyView` thumbnail compositing + name badge as its content slot. The shared `PopupWindow` / `state.preview` / `state.pending` / `state.btnX` / hover Timer are all gone — hover delay, dismiss-on-leave, and positioning come from the primitive; multiple previews can coexist via pin. Each tooltip registers at `<ipcPrefix>.workspaces.ws<name>` (addressable directly with `pin` / `unpin` / `togglePin`), and the plugin-root `showPreview(name)` / `hidePreview()` IPC still works — they iterate the `Repeater` and call the matching tooltip's `pin()` / `unpin()` under the hood. ScreencopyView cost stays bounded because each per-delegate popup only captures while visible
- [10] ✅ Fan-out layout for multi-pinned previews — each workspace's `BarTooltip` anchor lives in a sibling overlay rather than inside the button. When not pinned the anchor tracks the button (hover still yields a centred popup above it); when pinned via `showPreview`, the anchor widens to popup width and slots into the next fan-out position driven by a plugin-owned `pinOrder` array. Without this, coexisting pins all fell under `BarTooltip`'s `Math.max(4, …)` clamp and stacked at the same x so only the topmost was visible. `BarTooltip` is unchanged — the primitive's centred-on-parent calc stays plugin-agnostic; the plugin shapes its own anchor geometry to get the popup where it wants
- [11] ✅ Background-workspace preview geometry — the preview monitor lookup now reads `workspace.monitor` directly instead of scanning `Hyprland.monitors.values.find(m => m.activeWorkspace === ws)`. The scan only matches a workspace that is currently active on some monitor; a workspace assigned to a monitor whose `activeWorkspace` is something else (common on multi-monitor setups where ws5 sits on HDMI-A-2 while HDMI-A-2 shows ws3) used to fall back to the 1920×1080 default and placed every thumbnail off-screen. Using the workspace's own monitor reference returns the correct geometry regardless of which workspace is currently rendered on that output

### Active Window

- [1] ⬜ Active window title — display the focused window's app name and title

### Clock

- [1] ✅ Clock — live HH:mm display, updates every second
- [2] ⬜ Calendar dropdown — clock opens a dropdown on click; month grid with `h`/`j`/`k`/`l` navigation
- [3] ⬜ Stopwatch — start/stop/reset via click or IPC; elapsed time shown in the bar while running; hidden when stopped; supports multiple named concurrent stopwatches, each shown as a separate chip in the bar

### Audio

- [1] ✅ Volume scroll — scroll on the widget to adjust volume via PipeWire; hidden when no sink is available
- [2] ✅ Mute toggle — click the widget to toggle mute via PipeWire
- [3] ⬜ Microphone mute toggle — mutes the configured virtual PipeWire source node (not the physical device); the setup uses virtual sinks and sources that physical devices and apps route through, so mute targets the virtual node to silence all inputs simultaneously; configured via Nix with the target node name
- [4] ⬜ Output device quick switch — right-click or dropdown on the volume widget to select between available PipeWire sinks without opening the full Audio Mixer

### Media (MPRIS)

- [1] ✅ MPRIS playback controls — prev/play-pause/next buttons
- [2] ✅ MPRIS track display — artist and title shown alongside controls
- [3] ✅ MPRIS visibility — shows the first active player; hidden when no player is active
- [4] ⬜ MPRIS multi-source — when more than one player is active, show a dropdown (or similar) to select which source is displayed rather than always picking the first one
- [5] ⬜ Seek bar — progress indicator showing position within the current track; click or drag to seek; sourced from MPRIS `Position` and `Length` metadata
- [6] ⬜ Album art — thumbnail of the current track's artwork sourced from MPRIS `mpris:artUrl`; shown alongside artist/title
- [7] ⬜ Shuffle / repeat toggles — buttons reflecting and toggling the MPRIS `Shuffle` and `LoopStatus` properties

### System Tray

- [1] ✅ Taskbar icons — tray icons via StatusNotifierItem protocol; left click activates, right click shows native context menu via `display()`; hidden when no items present
- [2] ⬜ Overflow bucket — when icon count exceeds a configured limit, least-recently-interacted icons collapse into an expander chip; click expander to reveal the overflow tray

### Tailscale

- [1] ✅ Tailscale status polling — polls `tailscale status --json` every 10 s; parses `BackendState`, `TailscaleIPs`, and `Peer` map; exposes `connected`, `selfIp`, and `peers` for use in `TailscalePeers`
- [2] ✅ Tailscale tile appearance — `BarControlTile`-based pill; label + IP sublabel; highlights when connected via `activeColor`
- [3] ✅ Tailscale toggle on click — click the tile to run `tailscale up`/`down` and re-poll on exit; requires `tailscale` added to `extraBins` for the bar config so it is available as a Nix store path; also requires the user to be set as operator once: `sudo tailscale up --operator=$USER` (note: `tailscale set --operator` is [broken upstream](https://github.com/tailscale/tailscale/issues/18294); `extraUpFlags` in the NixOS module only applies when `authKeyFile` is set)
- [4] ✅ IPC — `bar.tailscale` target exposes `isConnected()`, `getSelfIp()`, `toggle()`
- [5] ✅ Toggle pending state — while `tailscale up`/`down` is running, the tile pulses its opacity and shows `...` as the sublabel; double-clicks are ignored; opacity resets on completion
- [6] ⬜ Toggle error feedback — when `tailscale up`/`down` exits non-zero, surface the failure visibly on the tile (e.g. flash red, show a brief error sublabel, or emit a notification); currently the tile silently stays in its previous state; the most common cause is the operator not being configured (`sudo tailscale up --operator=$USER`)
- [7] ✅ Peer ping — click a peer row in `TailscalePeers` to run `tailscale ping -c 1 <ip>` and display the round-trip latency inline; secondary label shows `ping…` while in flight, then the latency (e.g. `24ms`) in `base0E`; clears back to IP after 5 s; double-click ignored while pending
- [8] ✅ Exit node selection — exit-node-capable peers shown in a separate section in `TailscalePeers`; click to run `tailscale set --exit-node <ip>`; active exit node highlighted in `base0A` with "active" sublabel; click again to clear; pending state blocks double-clicks and shows `…` on the active row
- [9] ⬜ Advertise exit node toggle — button to run `tailscale set --advertise-exit-node` on/off for the local machine
- [10] ⬜ Shields-up toggle — toggle `tailscale set --shields-up` to block incoming connections; reflected in the tile UI
- [11] ✅ Hover highlight in `TailscalePeers` — hovering a peer or exit node row shows a `base02` background rectangle; suppressed on exit node rows while a set/clear is pending

### Network

- [1] ⬜ Network status — show active wired interface name and link state via nmcli; hidden when disconnected

### System Stats

Stats plugins are **data-only**: each polls a source and exposes readable
properties; users compose them with a sibling `BarText` (or any other
component) to render the value. Plugins never know their parent and contain
no presentation logic.

- [1] ✅ CPU usage — `CpuUsage` samples `/proc/stat` and exposes `usage: int`
- [2] ✅ RAM usage — `RamUsage` reads `/proc/meminfo`; exposes `totalKb`, `availableKb`, `usedKb`, `percent`
- [3] ✅ AMD GPU stats — `GpuUsage` reads `/sys/class/drm/<card>/device/{gpu_busy_percent,mem_info_vram_used,mem_info_vram_total}` (configurable `cardPath`); exposes `busy`, `vramUsedB`, `vramTotalB`, `vramUsedMb`, `vramTotalMb`. Nvidia deferred — needs `nvidia-smi` via `extraBins`, no hardware on this host
- [4] ✅ Disk usage — `DiskUsage` shells out to `df -B1 <mounts>` every 60 s; exposes `results: [{ mount, usedB, totalB }]`
- [5] ✅ Temperature — `CpuTemp` and `GpuTemp` walk `/sys/class/hwmon/hwmon*` (via `bash`) matching their `sensor` property (defaults `"zenpower"` / `"amdgpu"`) against each `name` file and read `temp1_input`; expose `temp: int` (°C). Users colour-code in their `BarText` binding via `warnColor` / `errorColor`

### Docker

- [1] ⬜ Docker status — running container count badge; click opens a panel listing all containers with name, image, and status
- [2] ⬜ Container actions — start/stop/restart individual containers from the panel
- [3] ⬜ Log tail — select a container in the panel and stream its logs inline (`docker logs -f`)

### Aspire

- [1] ⬜ Aspire status — running service count badge sourced from `aspire ps`; hidden when no Aspire session is active
- [2] ⬜ Aspire panel — click to open a list of all services with their state, endpoint URLs, and health; click a URL to open in browser
- [3] ⬜ Resource drill-down — select a service to tail its structured logs inline

### Notifications

- [1] ✅ Notifications indicator — bar plugin showing a bell icon; hidden when unread count is zero
- [2] ⬜ Unread badge — numeric badge overlaid on the bell showing unread notification count; sourced from `Quickshell.Services.Notifications`
- [3] ⬜ Do Not Disturb indicator — bell icon reflects DND state (e.g. muted icon variant) when DND is active
- [4] ⬜ Click to open panel — clicking the indicator toggles the Notification Center panel (to be implemented in the Notification Center section)

---

## Notification Center

Standalone Quickshell daemon replacing `mako`/`dunst`. Shows incoming toasts
and a persistent history panel (toggle via SUPER or bar button). Groups
notifications by app, supports action buttons, and integrates a Do Not
Disturb toggle.

### Toasts

- [1] ⬜ Incoming toasts — transient popup per notification with app icon, summary, and body; auto-dismisses after timeout
- [2] ⬜ Urgency handling — `critical` notifications ignore DND and persist until dismissed; `low` notifications skip the toast entirely

### History Panel

- [1] ⬜ Persistent history panel — toggle via SUPER or bar button; all notifications since last clear, grouped by app; dismiss individual or all
- [2] ⬜ Action buttons — render notification action buttons; click executes the action via DBus reply
- [3] ⬜ Do Not Disturb toggle — suppress toasts while enabled; history still accumulates; togglable from the bar and the panel

---

## Audio Mixer

Per-app volume mixing UI, replacing `pavucontrol`. Shows all active audio
streams grouped by app, with per-app volume sliders, mute toggles, and live
visualizations indicating which apps are currently producing audio. Toggle via
IPC/keybind.

### Core

- [1] ⬜ Stream list — all active PipeWire audio streams grouped by app, with app icon and name
- [2] ⬜ Per-app volume slider — drag or scroll to adjust individual stream volume
- [3] ⬜ Per-app mute toggle — click to mute/unmute a stream
- [4] ⬜ Output device selector — choose the default sink from a list of available PipeWire sinks

### Visualization

- [1] ⬜ Live activity indicator — VU meter or pulse animation showing which streams are currently producing audio

---

## Patchbay

PipeWire graph editor, replacing `qpwgraph`/`Helvum`. Visualises all PipeWire
nodes (audio, MIDI, video) as boxes with input/output ports, and the links
between them. Keyboard-first — every connect/disconnect that can be done with
a mouse drag must also be doable with vim-style motion + action bindings and
via IPC. Toggle via IPC/keybind.

### Core

- [1] ⬜ Node graph — all PipeWire nodes rendered as boxes with their name, media class (Audio/Sink, Audio/Source, Stream/Output/Audio, Midi/Bridge, Video/Source, …), and port list; sourced from `pw-dump` or the `libpipewire` Quickshell bindings if available
- [2] ⬜ Port rows — each node shows input ports on the left edge and output ports on the right edge, labelled with channel/port name
- [3] ⬜ Links — bezier/orthogonal edges drawn between connected output and input ports; colour-coded by media type (audio / MIDI / video)
- [4] ⬜ Live updates — subscribe to PipeWire registry events so node add/remove/link/unlink is reflected in the graph without polling
- [5] ⬜ Media type filter — toggle audio / MIDI / video visibility independently; hidden types dim their nodes and links
- [6] ⬜ IPC — `target: "patchbay"`; `toggle()`, `open()`, `close()`, `nav(dir)`, `key(k)`, `connect(srcNode, srcPort, dstNode, dstPort)`, `disconnect(...)`, `listNodes()`, `listLinks()`

### Navigation

- [1] ⬜ Modal normal/insert — opens in normal mode; `j`/`k`/`h`/`l` move focus between nodes by spatial adjacency; `/` enters insert mode with a search field filtering nodes by name
- [2] ⬜ Port selection — once a node is focused, `Tab`/`Shift+Tab` cycles through its ports; selected port visually highlighted
- [3] ⬜ Follow link — `gd` on a connected port jumps focus to the peer port on the other side of the link
- [4] ⬜ Zoom and pan — `+`/`-` zoom, `Ctrl+hjkl` pan the viewport; `gg` centres the graph; `z.` centres on the focused node

### Editing

- [1] ⬜ Connect — with an output port selected, press `c` (or Enter) to enter "target mode"; navigate to an input port and confirm to create the link; Escape cancels
- [2] ⬜ Disconnect — `d` on a selected link deletes it; confirmation popup for bulk operations
- [3] ⬜ Visual link select — `v` enters visual mode; select multiple links by walking the graph; `d` disconnects all selected links
- [4] ⬜ Auto-layout — `=` re-runs the layout algorithm (topological left-to-right, sources → sinks) to untangle edges after heavy editing

### Layout

- [1] ⬜ Automatic layout — topological sort from sources to sinks with per-column stacking; collision-free edge routing
- [2] ⬜ Manual node positions — drag (or `m` + hjkl in normal mode) to move a node; positions persisted to `$XDG_DATA_HOME/kh-patchbay/layout.json` keyed by node name so reconnecting a device restores its position
- [3] ⬜ Group nodes — collapse all nodes belonging to the same application (e.g. Firefox streams, Chromium streams) into a single expandable group node to reduce clutter

### Patches

- [1] ⬜ Save patch — `:w <name>` writes the current link set to `$XDG_DATA_HOME/kh-patchbay/patches/<name>.json`; records each link as `(srcNode, srcPort, dstNode, dstPort)` so it can be restored even after a reboot
- [2] ⬜ Load patch — `:e <name>` (or fuzzy-searchable load dialog) re-creates saved links; missing nodes are reported via the plugin error surface
- [3] ⬜ Auto-apply on device reconnect — watch for node additions and re-apply any saved patch whose endpoints match; useful for USB audio interfaces that get different IDs on reconnect

---

## OSD

Transient overlay that appears briefly on system events such as volume
changes. Currently a single hardcoded volume display; the end goal is a
plugin architecture matching the bar — user-composable slots, each slot an
independent QML component with its own PipeWire/system bindings and IPC,
so any combination of indicators can be shown without forking the daemon.

### Core

- [1] ✅ Volume OSD — appears on volume up/down/mute; shows icon and progress bar reflecting the new level
- [2] ✅ Auto-dismiss — fades out after ~2 s; timer resets if the value changes again before dismissal
- [3] ✅ IPC trigger — `qs ipc call osd showVolume <0–100>` / `qs ipc call osd showMuted`
- [4] ⬜ Plugin system — replace hardcoded volume slot with user-composable OSD plugins, following the same pattern as the bar (`OsdPlugin` base type, `nix.osd.structure` config string, `extraPluginDirs`)
- [5] ⬜ Volume plugin — extract current volume display into a first-party `OsdVolume` plugin
- [6] ⬜ Per-plugin dismiss timer — each active plugin manages its own visibility and timer independently so multiple plugins can coexist without interfering

### Audio plugins

Each plugin is **reactive** — subscribes to its own signal source, self-triggers on a state transition, then dismisses. The daemon needs no upfront knowledge of individual plugins.

- **OsdVolume** *(first-party, extracted from current impl)* — volume level on up/down/mute; icon + progress bar via PipeWire
- **OsdMicMute** — microphone mute toggle indicator; useful for push-to-talk or global mute keys; via PipeWire input sink

### Connectivity plugins

- **OsdBluetooth** — device name + connected/disconnected icon on pairing events; via Quickshell Bluetooth bindings
- **OsdVpn** — VPN interface up/down; IPC-driven (no standard DBus signal)

---

## File Viewer

One-shot viewer for arbitrary text or image files. Accepts N file arguments;
shows all files side-by-side with Tab to cycle focus between panes.

### Core

- [1] ✅ `nix run .#kh-view -- <file> [<file2> ...]`
- [2] ✅ Image detection by extension (png/jpg/jpeg/gif/webp/bmp/svg)
- [3] ✅ N files shown side-by-side in equal-width panes; Tab cycles focus; active divider highlights
- [4] ✅ `q`/`Esc` quits
- [5] ✅ IPC — `target: "view"`; `next()`/`prev()`/`seek(n)`/`quit()`/`setFullscreen(bool)`/`key(k)`; readable props `currentIndex`, `count`, `fullscreen`, `hasPrev`, `hasNext`
- [6] ⬜ Optional pane labels — each pane optionally shows a header bar with a short name and description; `kh-view` accepts label metadata alongside each file via a sidecar format or extended list protocol *(implement together with Dev Tooling → screenshot skill labels)*
- [7] ⬜ Monitor selection — `--monitor <name|index>` flag; defaults to the monitor containing the active window
- [8] ⬜ Gallery history — persist recent sessions (file list + labels) to `$XDG_DATA_HOME/kh-view/history.jsonl`; recall a prior gallery via `--recall [N]` or IPC so a closed window can be reopened. Motivating case: "Show me the previous gallery please, I accidentally closed it"

### Navigation

- [1] ✅ Per-pane cursor and motions — `hjkl`/`w`/`b`/`e`/`W`/`B`/`E`; `0`/`$`/`^` line; `gg`/`G`/`Ctrl+D`/`U` scroll
- [2] ✅ Per-pane visual select — `v`/`V`/`Ctrl+V` char/line/block; word motions extend; `y` copies selection
- [3] ✅ Fullscreen mode — `f` toggles single fullscreen pane; `h`/`l` steps through all loaded files; dot indicators at bottom center

### Content

- [1] ⬜ Syntax highlighting — detect language from file extension; apply token-level colouring using Tree-sitter or `bat` themes
- [2] ⬜ Directory and glob input — `kh-view ./images/` opens all recognised media files; `kh-view ./images/*.png` expands the glob; files sorted by name
- [3] ⬜ Image gallery mode — `g` toggles a grid thumbnail view when all panes are images; `hjkl` navigate; Enter opens selected image fullscreen

---

## Process Manager

Keyboard-driven process viewer, replacing `htop`. Shows running processes
sortable by CPU, RAM, or name; `k` kills the selected process. Toggle via
keybind or IPC, or open by clicking a System Stats bar widget.

### Core

- [1] ⬜ Process list — all running processes with PID, name, CPU %, and RAM usage; sourced from `/proc`
- [2] ⬜ Sort — cycle sort column with `s`; toggle ascending/descending with `S`
- [3] ⬜ Filter — `/` to search by process name
- [4] ⬜ IPC trigger — openable from bar widget clicks on CPU or RAM

### Actions

- [1] ⬜ Kill — `k` sends SIGTERM to the selected process; `K` sends SIGKILL; confirmation popup before executing

### Views

- [1] ⬜ Tree view — `t` toggles parent/child process tree layout

---

## Window Inspector

Overlay showing detailed information about open windows (class, title, PID,
geometry, workspace, monitor, etc.). Useful for writing Hyprland window
rules, debugging focus or scale issues, and confirming what an app reports
itself as. Spiritual sibling of AutoHotkey's *Window Spy* and browser
DevTools' element inspector, adapted for Hyprland. Triggered via keybind
or IPC.

### Core

- [1] ⬜ Window list — all open windows with class, title, PID, address, workspace, monitor, geometry, floating/fullscreen state; sourced from `hyprctl clients -j`
- [2] ⬜ Detail panel — full property dump for the selected window covering every field `hyprctl clients -j` exposes (`address`, `mapped`, `hidden`, `pinned`, `xwayland`, `grouped`, `tags`, `swallowing`, `focusHistoryID`, `inhibitingIdle`, `xdgTag`, `xdgDescription`, `contentType`, `stableId`, …)
- [3] ⬜ Surface `initialClass` / `initialTitle` alongside `class` / `title` — explicit "rule-stable" label on the initial fields, since most apps mutate their title after launch and `windowrulev2` matchers almost always want the initial values; this is the single most common Hyprland-rule footgun and the inspector's main reason to exist
- [4] ⬜ Geometry block — `at` / `size` shown in both global layout coords AND monitor-local coords, with the containing monitor's name + scale + transform; geometry bugs almost always involve scale or coordinate-space confusion
- [5] ⬜ Live updates — subscribe to Hyprland IPC events (`openwindow`, `closewindow`, `windowtitle`, `movewindow`, `activewindow`) so titles/geometry stay fresh without polling
- [6] ⬜ IPC — `target: "window-inspector"`; `toggle()`, `open()`, `close()`, `inspectActive()`, `inspectByAddress(<addr>)`, `inspectByPid(<pid>)`

### Navigation

- [1] ⬜ Modal normal/insert — opens in normal mode; `j`/`k` navigate, `/` enters insert mode filtering by class/title/pid/address, `Enter` opens detail panel, `Esc`/`q` closes
- [2] ⬜ Pick mode — `p` enters pick mode; cursor-over-window draws a translucent outline overlay plus a floating tag with class/title/size; click or `Enter` locks selection. Browser-DevTools-inspector UX, adapted for Wayland
- [3] ⬜ Freeze toggle — `f` freezes the panel on the currently-targeted window so the cursor can move off the target to read the panel without the selection following the mouse; AutoHotkey Window Spy's defining UX trick — pick mode is unusable without it
- [4] ⬜ View toggle — `Tab` toggles between flat list (fast fuzzy filter, wmctrl-style) and tree view (monitor → workspace → window, sway-style); flat is fastest for "find that window", tree is best for spatial reasoning across multi-monitor setups

### Copy & Actions

- [1] ⬜ Copy as Hyprland rule — `y` copies the selected window as a ready-to-paste `windowrulev2` line built from `initialClass` / `initialTitle` (e.g. `windowrulev2 = float, class:^(foo)$, title:^(bar)$`); a small menu offers variants keyed on `pid`, `address`, `workspace`, or `monitor` so users don't have to remember matcher syntax
- [2] ⬜ Copy as JSON — `Y` copies the full `hyprctl clients -j` record for the selected window
- [3] ⬜ Dispatch actions from the panel — `F` focus, `X` close, `m<n>` move to workspace N, `t` toggle floating, `T` toggle pinned; thin wrappers around `hyprctl dispatch` so the inspector doubles as a lightweight window manager once you've found the target

---

## Diff Viewer

Side-by-side two-pane file diff. `kh-diff file1 file2` or pipe from `git diff`
/ `diff`. Keyboard-driven; vim motion navigation. Natural sibling to File Viewer.

### Core

- [1] ⬜ Two-pane diff — left/right panes showing old and new versions with added/removed/changed lines highlighted
- [2] ⬜ Pipe input — `git diff | kh-diff` or `diff -u a b | kh-diff` reads unified diff from stdin and renders it
- [3] ⬜ IPC — same pattern as File Viewer

### Navigation

- [1] ⬜ `]c` / `[c` jump to next/previous change hunk
- [2] ⬜ `Tab` cycles focus between panes; `hjkl` scroll within a pane; `gg`/`G`/`Ctrl+D`/`U` navigate
- [3] ⬜ `y` copies the selected hunk or visual selection

---

## Screenshot

Region/window/fullscreen capture tool, replacing Flameshot. Captures via
`grim`/`slurp`; result goes to clipboard or is saved to a file. Triggered
via keybind or IPC.

### Core

- [1] ⬜ Region capture — `slurp` crosshair selection; result copied to clipboard via `wl-copy`
- [2] ⬜ Fullscreen capture — capture the focused monitor immediately
- [3] ⬜ Window capture — click to select a window; captures its geometry via Hyprland IPC
- [4] ⬜ IPC trigger — `qs ipc call screenshot <region|fullscreen|window>` so any keybind daemon can drive it

### Output

- [1] ⬜ Save to file — write to `$XDG_PICTURES_DIR/Screenshots/` with a timestamp filename in addition to clipboard copy
- [2] ⬜ Annotation layer — draw arrows, boxes, and text over the capture before copying/saving

---

## Dev Tooling

Improvements to the Claude skills and agentic development workflow.

- [1] ✅ `screenshot` skill passes labels to `kh-view` — once kh-view supports optional pane labels, update the skill to supply a name and short description for each shot (what app/state it shows, what to look for); makes review sessions self-documenting without manual annotation *(implement together with File Viewer → optional pane labels)*
- [2] ⬜ Headless Hyprland for workspace preview screenshots — `kh-bar`'s Workspaces plugin uses
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

### Applications

- **Scratchpad** — persistent floating notepad toggled by keybind; plain text, autosaved to `$XDG_DATA_HOME/kh-scratch`; vim bindings; `y` copies selection
- **Log viewer** — tail `journalctl` or arbitrary log files with unit/level filter; keyboard-driven alternative to `kitty -e journalctl`

### Plugins

#### Bar

- **Ping + bandwidth monitor** — rolling average latency to a configured host plus live upload/download throughput; colour-coded latency indicator; hidden when idle below threshold
- **Multiple time zones** — show additional configured time zones alongside the main clock; click to expand a list of all configured zones

#### Launcher

- **SSH launcher plugin** — fuzzy-searches `~/.ssh/config` hosts; Enter opens kitty with `ssh <host>`
- **Web search prefixes** — configurable prefix → URL mappings (e.g. `g <q>` → Google, `gh <q>` → GitHub, `mdn <q>` → MDN); defined in Nix; Enter opens in default browser
- **Browser history** — fuzzy search Firefox/Chromium history by title and URL; reads from the browser's SQLite history database; Enter opens in browser; read-only, no write access to profile

---

## Probably Not

Considered and deprioritised. Kept here to avoid re-litigating.

### Applications

- **Font browser** — grid/list of installed fonts with live preview text
- **Wallpaper picker** — browse and apply wallpapers via `swww`; no wallpapers in use

### Plugins

#### Bar

- **Pomodoro** — countdown timer; IPC controllable; notification on completion
- **Weather** — current conditions widget fetching from `wttr.in`; 3-day forecast dropdown
- **Night light** — toggle `wlsunset`/`gammastep` on/off with a colour temperature slider
- **NixOS update notifier** — badge when `nix flake metadata` shows the system is behind upstream
- **Keyboard layout switcher** — current layout; click/scroll to cycle via `hyprctl switchxkblayout`
- **GitHub/GitLab notifications** — unread badge via API; click to list PRs/issues/mentions
- **Crypto/stock ticker** — live price widget
- **Git branch indicator** — active branch for the focused window's CWD; unclear what "focused window's repo" means outside a terminal
- **Clock timestamp copy** — click the clock to copy the current time; too niche and a widget action with no visual feedback is confusing

#### Launcher

- **Calculator plugin** — evaluate expressions in the search field; Enter copies result to clipboard
- **Recent files plugin** — fuzzy search `recently-used.xbel`; Enter opens in default app
- **Password generator** — generate and copy a random password
- **IDE project picker** — fuzzy search project directories and open in editor; terminal workflow already covers this
- **Dictionary** — inline word definition via WordNet; search engine covers the need

#### OSD

- **OsdCapsLock** / **OsdNumLock** — lock key state indicators; technically feasible but not worth the screen noise
- **OsdPowerProfile** — profile changes are infrequent and visible in the bar; OSD adds little
- **OsdColourTemperature** — night light transitions are gradual; a transient overlay is more disruptive than the change itself
- **OsdNowPlaying** — the bar's MediaPlayer already covers this; an OSD duplicate adds noise without value

---

## Future Laptop Support

Features deferred until the system runs on a laptop. No implementation timeline.

### Plugins

#### Bar

- **Battery bar module** — percentage + charging indicator via `/sys/class/power_supply`; dropdown with estimated time remaining and power profile selector
- **WiFi bar module** — connection name and signal strength in the bar; dropdown listing nearby networks with connect support (password prompt for new ones)
- **WiFi tile** — `WifiPanel`; toggle WiFi on/off and show connection status; pairs with the WiFi bar module
- **Power profiles** — cycle `power-profiles-daemon` profiles (power-saver / balanced / performance); show active profile as an icon
- **Bluetooth manager** — list paired devices, connect/disconnect, toggle Bluetooth on/off; replaces reaching for `bluetoothctl` or a tray app

#### OSD

- **OsdBrightness** — brightness level on step changes; icon + progress bar; IPC-driven (`qs ipc call osd showBrightness <0–100>`)
- **OsdBattery** — level indicator on plug/unplug and when crossing thresholds (20 %, 10 %, 5 %); via UPower
