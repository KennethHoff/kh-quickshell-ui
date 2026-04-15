# quickshell-ui

QML shell components for [Quickshell](https://quickshell.outfoxxed.me/): a status bar (`kh-bar`), application launcher (`kh-launcher`), clipboard history viewer (`kh-cliphist`), and file/image viewer (`kh-view`).

## Components

| Name | Description | IPC target | Toggle call |
|---|---|---|---|
| `kh-bar` | Status bar (all monitors) | — | always visible |
| `kh-launcher` | Application launcher overlay | `launcher` | `qs ipc call launcher toggle` |
| `kh-cliphist` | Clipboard history overlay | `cliphist` | `qs ipc call cliphist toggle` |
| `kh-view` | File / image viewer overlay | `view` | `qs ipc call view toggle` |

## Quick start

Run a component directly without installing:

```bash
nix run .#kh-bar
nix run .#kh-launcher
nix run .#kh-cliphist
nix run .#kh-view
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
};
```

### 4. Configure the bar

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

#### Built-in plugins

| Plugin | Description |
|---|---|
| `Workspaces` | Hyprland workspace switcher; hover for live preview thumbnail |
| `MediaPlayer` | MPRIS prev/play-pause/next + track info; hidden when no player active |
| `Clock` | `HH:mm:ss` clock |
| `Volume` | PipeWire volume; scroll to adjust, click to mute |
| `Tray` | StatusNotifierItem tray icons; left-click activates, right-click menu |

#### Composable panel components

Use `BarGroup` to group plugins behind a single dropdown button. Any plugin or component can be a child:

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

Available composition types (no import statement needed):

| Component | Purpose |
|---|---|
| `BarRow` | Full-width `RowLayout` row; children laid out left-to-right |
| `BarSpacer` | Flexible spacer; expands to fill remaining width |
| `BarGroup` | Bar button that opens a popup panel; children are panel content |
| `TailscalePanel` | Tailscale toggle tile; exposes `connected`, `selfIp`, `peers` |
| `EthernetPanel` | Ethernet toggle tile; exposes `connected`, `iface` |
| `TailscalePeers` | Peer list section; bind via `source: <TailscalePanel id>` |
| `BarDropdown` | Generic dropdown primitive; use `BarGroup` for most cases |
| `ControlTile` | Styled toggle pill for custom panel tiles |
| `DropdownHeader` | Muted section heading |
| `DropdownDivider` | 1 px horizontal rule |
| `DropdownItem` | Row with dot indicator, primary label, secondary label |
| `NixConfig` | Theme colors (`color.baseXX`), font family and size |

#### Writing a custom plugin

A plugin is a `BarPlugin` subtype. `BarPlugin` handles the sizing boilerplate and provides `ipcPrefix`, `barHeight`, and `barWindow` — you only need to set `implicitWidth`.

Example `MyWidget.qml`:

```qml
import QtQuick

BarPlugin {
    NixConfig { id: cfg }

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

### 5. Bar IPC

IPC targets are hierarchical and derived from the bar's `ipcName` (default `"bar"`) plus each component's position in the layout tree. Set `programs.kh-ui.bar.ipcName` to give your bar a unique root prefix — required when running multiple bars.

Targets follow the pattern `<ipcName>.<plugin>`, with group nesting appended automatically:

| Target (default `ipcName = "bar"`) | Functions / Properties |
|---|---|
| `bar.workspaces` | `getFocused()` → string, `list()` → newline-separated names, `switchTo(name)`, `showPreview(name)`, `hidePreview()` |
| `bar.volume` | `getVolume()` → int (0–150), `setVolume(v)`, `adjustVolume(delta)`, `isMuted()` → bool, `setMuted(muted)`, `toggleMute()` |
| `bar.media` | `isActive()` → bool, `isPlaying()` → bool, `getTitle()`, `getArtist()`, `togglePlaying()`, `play()`, `pause()`, `next()`, `prev()` |
| `bar.tray` | `list()` → newline-separated titles, `activate(title)`, `showMenu(title)` |
| `bar.controlcenter` | `toggle()`, `open()`, `close()`, `isOpen()` → bool |
| `bar.controlcenter.tailscale` | `isConnected()` → bool, `getSelfIp()` → string, `toggle()` |
| `bar.controlcenter.ethernet` | `isConnected()` → bool, `getIface()` → string |

```bash
# Examples (with default ipcName = "bar")
qs ipc call bar.workspaces switchTo 2
qs ipc call bar.volume setVolume 50
qs ipc call bar.media togglePlaying
qs ipc call bar.tray activate "KDE Connect"
qs ipc call bar.controlcenter toggle
qs ipc call bar.controlcenter.tailscale toggle
qs ipc prop get bar.volume isMuted
```

Targets reflect structure — a `TailscalePanel` inside a `BarGroup { ipcName: "net" }` in a bar with `ipcName = "top"` is reachable as `top.net.tailscale`.

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

### 6. Launcher IPC

| Target | Functions / Properties |
|---|---|
| `launcher` | `toggle()`, `open()`, `close()`, `launch()`, `launchOnWorkspace(n)`, `enterActionsMode()`, `setMode(m)`, `nav(dir)`, `key(k)`, `type(text)` |
| | **Props:** `showing` → bool, `mode` → string, `selectedAppName` → string, `selectedAppExec` → string |

```bash
qs ipc -c kh-launcher call launcher launch
qs ipc -c kh-launcher call launcher launchOnWorkspace 2
qs ipc -c kh-launcher prop get launcher selectedAppName
```

### 7. Cliphist IPC

| Target | Functions / Properties |
|---|---|
| `cliphist` | `toggle()`, `open()`, `close()`, `setMode(m)`, `setView(v)`, `nav(dir)`, `key(k)`, `type(text)` |
| | **Props:** `showing` → bool, `mode` → string |

```bash
qs ipc -c kh-cliphist call cliphist toggle
qs ipc -c kh-cliphist call cliphist nav down
```

### 8. kh-view

`kh-view` is a file/image viewer overlay. Pass files as arguments via the Nix module or directly:

```bash
nix run .#kh-view -- /path/to/file.png /path/to/other.jpg
```

#### kh-view IPC

| Target | Functions / Properties |
|---|---|
| `view` | `quit()`, `next()`, `prev()`, `seek(n)`, `setFullscreen(on)`, `setWrap(on)`, `key(k)` |
| | **Props:** `currentIndex` → int, `count` → int, `fullscreen` → bool, `wrap` → bool, `hasPrev` → bool, `hasNext` → bool |

```bash
qs ipc -c kh-view call view next
qs ipc -c kh-view call view setFullscreen true
qs ipc -c kh-view prop get view currentIndex
```

### 9. Autostart and keybinds (Hyprland)

When `wayland.windowManager.hyprland.enable` is true the module automatically adds `exec-once` entries for all enabled components. You only need to add keybinds:

```nix
wayland.windowManager.hyprland.settings.bind = [
  "$mainMod, SPACE, exec, ${lib.getExe pkgs.quickshell} ipc -c kh-launcher call launcher toggle"
  "$mainMod, V,     exec, ${lib.getExe pkgs.quickshell} ipc -c kh-cliphist call cliphist toggle"
  "$mainMod, I,     exec, ${lib.getExe pkgs.quickshell} ipc -c kh-view     call view     toggle"
];
```

## Development

Take headless screenshots:

```bash
# Single shot
nix run .#screenshot -- kh-bar default
nix run .#screenshot -- kh-launcher my-shot
nix run .#screenshot -- kh-cliphist my-shot

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
