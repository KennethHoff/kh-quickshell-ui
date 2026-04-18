# quickshell-ui

QML shell components for [Quickshell](https://quickshell.outfoxxed.me/): a status bar (`kh-bar`), application launcher (`kh-launcher`), clipboard history viewer (`kh-cliphist`), file/image viewer (`kh-view`), and volume OSD (`kh-osd`).

Everything controllable via keyboard is also controllable via [Quickshell IPC](https://quickshell.outfoxxed.me/docs/ipc/) — every navigation action, mode switch, plugin toggle, and value query has a corresponding IPC call. This makes all components fully scriptable and suitable for automation or agentic workflows.

## Components

| Name | Description | IPC target | Toggle call |
|---|---|---|---|
| `kh-bar` | Status bar (all monitors) | — | always visible |
| `kh-launcher` | Application launcher overlay | `launcher` | `qs ipc call launcher toggle` |
| `kh-cliphist` | Clipboard history overlay | `cliphist` | `qs ipc call cliphist toggle` |
| `kh-view` | File / image viewer overlay | `view` | `qs ipc call view toggle` |
| `kh-osd` | Volume on-screen display | `osd` | reacts to PipeWire automatically |

## Quick start

Run a component directly without installing:

```bash
nix run .#kh-bar
nix run .#kh-launcher
nix run .#kh-cliphist
nix run .#kh-view
nix run .#kh-osd
```

## Flake integration

### 1. Add the input

```nix
# flake.nix
inputs.kh-quickshell-ui = {
  url = "github:KennethHoff/kh-quickshell-ui";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### 2. Import the home-manager module

The flake exports a home-manager module at `homeModules.default` that handles everything — building configs from Stylix colors, registering them with Quickshell, and defining the `kh-ui` options.

Import it alongside your other home-manager modules (e.g. in `sharedModules` or a home-manager aspect):

```nix
imports = [ inputs.kh-quickshell-ui.homeModules.default ];
```

The module requires [Stylix](https://github.com/nix-community/stylix) — colors and fonts are read from `config.lib.stylix` at build time.

### 3. Enable the components

`programs.kh-ui.enable = true` is a prerequisite — it activates the module but starts nothing on its own. Each component must be explicitly enabled:

```nix
programs.kh-ui = {
  enable = true;        # required — unlocks all kh-ui options
  bar.enable = true;
  launcher.enable = true;
  clipboard-history.enable = true;
  view.enable = true;
  osd.enable = true;
};
```

---

## Bar (`kh-bar`)

### Configuration

The bar requires an explicit layout — there is no default. Set it via `programs.kh-ui.bar.structure`:

```nix
programs.kh-ui.bar.structure = ''
  BarRow {
    Workspaces {}
    MediaPlayer {}
    BarSpacer {}
    Clock {}
    Volume {}
    Tray {}
  }
'';
```

`BarRow` is a full-width `RowLayout` row. `BarSpacer` expands to fill remaining space — place it between plugin groups to push them apart (equivalent to CSS `space-between`). Multiple `BarRow`s, additional spacers, or any other QML types can appear at the top level.

### Layout types

| Component | Purpose |
|---|---|
| `BarRow` | Full-width `RowLayout` row; children laid out left-to-right |
| `BarSpacer` | Flexible spacer; expands to fill remaining width |
| `BarGroup` | Bar button that opens a popup panel; children are panel content |
| `BarDropdown` | Generic dropdown primitive; use `BarGroup` for most cases |

Use `BarGroup` to group plugins behind a single dropdown button:

```nix
programs.kh-ui.bar.structure = ''
  BarRow {
    Workspaces {}
    BarSpacer {}
    BarGroup {
      label: "●●●"
      ipcName: "controlcenter"
      panelWidth: 300
      Row {
        spacing: 8
        EthernetPanel {}
        TailscalePanel { id: ts }
      }
      TailscalePeers { source: ts }
    }
    Clock {}
    Volume {}
    Tray {}
  }
'';
```

### Plugins

#### `Workspaces`

Hyprland workspace switcher. Displays all workspaces and highlights the active one. Click a workspace to switch to it. Hover a workspace for 300 ms to show a live thumbnail preview.

#### `MediaPlayer`

MPRIS playback controls (prev / play-pause / next) with artist and title display. Hidden when no player is active. Shows the first active player when multiple are running.

#### `Clock`

Live `HH:mm:ss` clock. Updates every second.

#### `Volume`

PipeWire volume control. Scroll to adjust volume, click to toggle mute. Hidden when no sink is available.

#### `Tray`

StatusNotifierItem system tray. Left-click activates an item, right-click shows its native context menu. Hidden when no tray items are present.

#### `TailscalePanel`

Tailscale status tile. Shows connection state and the machine's Tailscale IP. Click to toggle `tailscale up` / `tailscale down`. Exposes `connected` (bool), `selfIp` (string), and `peers` (array) for use by `TailscalePeers`.

> **Operator permission required.** `tailscale up`/`down` fail with "Access denied" unless your user is set as the Tailscale operator. Run this once:
> ```bash
> sudo tailscale up --operator=$USER
> ```
> Note: `tailscale set --operator` is [broken upstream](https://github.com/tailscale/tailscale/issues/18294) and `extraUpFlags` in the NixOS module [only applies when `authKeyFile` is set](https://github.com/NixOS/nixpkgs/issues/276912), so there is currently no clean declarative path for users who authenticate manually.

#### `EthernetPanel`

Ethernet status tile. Shows the active interface name and link state. Exposes `connected` (bool) and `iface` (string).

#### `TailscalePeers`

Peer list panel section. Displays the self IP header and all peers with online/offline indicators. Bind it to a `TailscalePanel` via the `source` property — it hides itself when disconnected:

```qml
TailscalePanel { id: ts }
TailscalePeers { source: ts }
```

### Primitive components

Low-level building blocks for custom plugins and panels (no import needed):

| Component | Purpose |
|---|---|
| `ControlTile` | Styled toggle pill for custom panel tiles |
| `DropdownHeader` | Muted section heading |
| `DropdownDivider` | 1 px horizontal rule |
| `DropdownItem` | Row with dot indicator, primary label, secondary label |
| `NixConfig` | Theme colors (`color.baseXX`), font family and size |

### Writing a custom plugin

A plugin is a `BarPlugin` subtype. `BarPlugin` handles the sizing boilerplate and provides `ipcPrefix`, `barHeight`, and `barWindow` — you only need to set `implicitWidth`.

Two singleton helpers are available in every plugin without an import:

| Helper | Purpose |
|---|---|
| `NixConfig` | Theme colors (`color.baseXX`), font family and size |
| `NixBins` | Store-path binaries injected via `extraBins`; use when shelling out to external tools |

Example `MyWidget.qml`:

```qml
import QtQuick
import Quickshell.Io

BarPlugin {
    NixConfig { id: cfg }
    NixBins   { id: bin }  // omit if the plugin doesn't run external processes

    implicitWidth: _label.implicitWidth + 16

    IpcHandler {
        target: ipcPrefix + ".mywidget"
        function getValue(): string { return _label.text }
    }

    Text {
        id: _label
        anchors.centerIn: parent
        text:           "hello"
        color:          cfg.color.base05
        font.family:    cfg.fontFamily
        font.pixelSize: cfg.fontSize
    }
}
```

Place your plugin files in a directory and pass it via `extraPluginDirs`. All `.qml` files in those directories are copied into the bar config root and become available by filename in `structure`:

```nix
programs.kh-ui.bar = {
  structure = ''
    BarRow {
      Workspaces {}
      MyWidget {}
    }
  '';
  extraPluginDirs = [ ./bar-plugins ];  # directory containing MyWidget.qml
};
```

### IPC

Each plugin registers at a suffix derived from its type. The full target path is built from the nesting in your `structure`:

```
bar.<plugin>
bar.<group-ipcName>.<plugin>
bar.<group-ipcName>.<nested-group-ipcName>.<plugin>
```

For example, a `TailscalePanel` inside `BarGroup { ipcName: "net" }` is reachable as `bar.net.tailscale`.

| Plugin | Suffix | Functions / Properties |
|---|---|---|
| `Workspaces` | `.workspaces` | `getFocused()` → string, `list()` → newline-separated names, `switchTo(name)`, `showPreview(name)`, `hidePreview()` |
| `Volume` | `.volume` | `getVolume()` → int (0–150), `setVolume(v)`, `adjustVolume(delta)`, `isMuted()` → bool, `setMuted(muted)`, `toggleMute()` |
| `MediaPlayer` | `.media` | `isActive()` → bool, `isPlaying()` → bool, `getTitle()`, `getArtist()`, `togglePlaying()`, `play()`, `pause()`, `next()`, `prev()` |
| `Tray` | `.tray` | `list()` → newline-separated titles, `activate(title)`, `showMenu(title)` |
| `TailscalePanel` | `.tailscale` | `isConnected()` → bool, `getSelfIp()` → string, `toggle()` |
| `EthernetPanel` | `.ethernet` | `isConnected()` → bool, `getIface()` → string |
| `BarGroup` / `BarDropdown` | `.<ipcName>` | `toggle()`, `open()`, `close()`, `isOpen()` → bool |

#### Dropdown IPC for custom plugins

Any `BarGroup` or `BarDropdown` with `ipcName` set gets `toggle`/`open`/`close`/`isOpen` automatically, under the inherited prefix:

```qml
BarGroup {
    ipcName: "mypanel"
    label: "my panel"
    // children reachable as bar.mypanel.<plugin>
}
```

```bash
qs ipc call bar.mypanel toggle
qs ipc call bar.mypanel isOpen
```

Custom plugins inside a group get their prefix automatically — use `ipcPrefix + ".mywidget"` as the `IpcHandler` target (see the custom plugin example above).

---

## Launcher (`kh-launcher`)

The launcher is a unified mode host. The built-in "apps" mode is just another registered mode — you can add custom modes (emoji picker, window switcher, system commands, etc.) via Nix or at runtime via IPC, and remove the defaults.

See **[docs/launcher-modes.md](docs/launcher-modes.md)** for the full guide on adding, removing, and scripting modes.

### IPC

| Target | Functions / Properties |
|---|---|
| `launcher` | `toggle()`, `open()`, `close()`, `launch()`, `launchOnWorkspace(n)`, `enterActionsMode()`, `setMode(m)`, `nav(dir)`, `key(k)`, `type(text)` |
| | `activateMode(name)`, `returnToDefault()`, `nextMode()`, `prevMode()`, `registerMode(...)`, `removeMode(name)`, `listModes()` |
| | `addItem(mode, ...)`, `addItemWithId(mode, ...)`, `itemsReady(mode)` |
| | **Props:** `showing` → bool, `mode` → string, `activeMode` → string, `selectedLabel` → string, `selectedCallback` → string, `itemCount` → int, `lastSelection` → string |

```bash
qs ipc -c kh-launcher call launcher toggle
qs ipc -c kh-launcher call launcher activateMode emoji
qs ipc -c kh-launcher prop get launcher activeMode
```

---

## Clipboard History (`kh-cliphist`)

### IPC

| Target | Functions / Properties |
|---|---|
| `cliphist` | `toggle()`, `open()`, `close()`, `setMode(m)`, `setView(v)`, `nav(dir)`, `key(k)`, `type(text)` |
| | **Props:** `showing` → bool, `mode` → string |

```bash
qs ipc -c kh-cliphist call cliphist toggle
qs ipc -c kh-cliphist call cliphist nav down
```

---

## File Viewer (`kh-view`)

Pass files as arguments via the Nix module or directly:

```bash
nix run .#kh-view -- /path/to/file.png /path/to/other.jpg
```

### IPC

| Target | Functions / Properties |
|---|---|
| `view` | `quit()`, `next()`, `prev()`, `seek(n)`, `setFullscreen(on)`, `setWrap(on)`, `key(k)` |
| | **Props:** `currentIndex` → int, `count` → int, `fullscreen` → bool, `wrap` → bool, `hasPrev` → bool, `hasNext` → bool |

```bash
qs ipc -c kh-view call view next
qs ipc -c kh-view call view setFullscreen true
qs ipc -c kh-view prop get view currentIndex
```

---

## OSD (`kh-osd`)

A transient bottom-center overlay that appears when the default PipeWire sink volume or mute state changes. No keybind wiring required — run the daemon and it reacts automatically.

### Configuration

```nix
programs.kh-ui = {
  enable = true;
  osd.enable = true;
  volumeMax = 1.5;   # optional — ceiling for volume bar and bar plugin (default 1.5 = 150%)
};
```

`volumeMax` should match the `-l` flag on your `wpctl set-volume` keybinds. The progress bar spans the full `0–volumeMax` range so over-amplified levels display correctly.

### Keybinds

No special wiring needed for the OSD itself — plain `wpctl` calls are enough:

```nix
wayland.windowManager.hyprland.settings.bind = [
  ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"
  ", XF86AudioLowerVolume, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%-"
  ", XF86AudioMute,        exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
];
```

### IPC

The OSD exposes IPC for testing or manual triggering:

| Target | Functions |
|---|---|
| `osd` | `showVolume(value)` — show at given level (0–150); `showMuted()` — show muted state |

```bash
qs ipc -c kh-osd call osd showVolume 75
qs ipc -c kh-osd call osd showMuted
```

---

## Autostart and keybinds

The module registers each enabled component as a `systemd` **user service** bound to `graphical-session.target`. That means:

- Autostart works on any compositor that integrates with the systemd user session.
- Crashed processes are restarted automatically (`Restart=on-failure`).
- On `home-manager switch`, Home Manager's `sd-switch` strategy restarts any service whose `ExecStart` path changed — so a rebuild swaps in the new version without a logout.
- You can inspect / control instances via standard tooling:

  ```bash
  systemctl --user status kh-bar
  systemctl --user restart kh-cliphist
  journalctl --user -u kh-osd -f
  ```

You only need to add keybinds. Example for Hyprland:

```nix
wayland.windowManager.hyprland.settings.bind = [
  "$mainMod, SPACE, exec, ${lib.getExe pkgs.quickshell} ipc -c kh-launcher call launcher toggle"
  "$mainMod, V,     exec, ${lib.getExe pkgs.quickshell} ipc -c kh-cliphist call cliphist toggle"
  "$mainMod, I,     exec, ${lib.getExe pkgs.quickshell} ipc -c kh-view     call view     toggle"
];
```

---

## Development

Take headless screenshots:

```bash
# Single shot
nix run .#screenshot -- kh-bar default
nix run .#screenshot -- kh-launcher my-shot
nix run .#screenshot -- kh-cliphist my-shot
nix run .#screenshot -- kh-osd volume-50 "osd showVolume 50"

# Multiple shots in one run (shared sway instance)
nix run .#screenshot -- kh-launcher shot-a 'type chrm' -- shot-b "type 'chrm"
```

Run the QML test suite:

```bash
nix develop
qmltestrunner -input tests/
```

Or just validate that all derivations evaluate:

```bash
nix flake check
```
