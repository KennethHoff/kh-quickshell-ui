# quickshell-ui

QML shell components for [Quickshell](https://quickshell.outfoxxed.me/): a status bar (`kh-bar`), application launcher (`kh-launcher`), and clipboard history viewer (`kh-cliphist`).

## Components

| Name | Description | IPC target | Toggle call |
|---|---|---|---|
| `kh-bar` | Status bar (all monitors) | — | always visible |
| `kh-launcher` | Application launcher | `launcher` | `quickshell ipc -c kh-launcher call launcher toggle` |
| `kh-cliphist` | Clipboard history viewer | `viewer` | `quickshell ipc -c kh-cliphist call viewer toggle` |

## Quick start

Run a component directly without installing:

```bash
nix run .#kh-bar
nix run .#kh-launcher
nix run .#kh-cliphist
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

Enable everything with a single option:

```nix
programs.kh-ui.enable = true;
```

Individual components can be disabled while keeping the rest active:

```nix
programs.kh-ui = {
  enable = true;
  bar.enable = false;                # disable kh-bar
  launcher.enable = false;           # disable kh-launcher
  clipboard-history.enable = false;  # disable kh-cliphist
};
```

### 4. Configure the bar

The bar layout is a QML snippet set via `programs.kh-ui.bar.structure`. The default:

```nix
programs.kh-ui.bar.structure = ''
  BarRow {
    Workspaces {}
    MediaPlayer {}
    BarSpacer {}
    ControlCenter {}
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
| `ControlCenter` | `●●●` button → panel with Ethernet + Tailscale tiles and peer list |
| `Clock` | `HH:mm:ss` clock |
| `Volume` | PipeWire volume; scroll to adjust, click to mute; hidden when no sink |
| `Tray` | StatusNotifierItem tray icons; left-click activates, right-click menu |

#### Composable panel components

`ControlCenter` is just one possible composition. You can build your own panel directly in the structure string:

```nix
programs.kh-ui.bar.structure = ''
  BarRow {
    Workspaces {}
    BarSpacer {}
    ControlPanel {
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
| `ControlPanel` | `●●●` dropdown frame; children go in the popup panel |
| `ControlTile` | Rounded toggle tile with label, sublabel, active/inactive colors |
| `TailscalePanel` | Tailscale ControlTile; exposes `connected`, `selfIp`, `peers` |
| `EthernetPanel` | Ethernet ControlTile; exposes `connected`, `iface` |
| `TailscalePeers` | Peer list section; bind via `source: <TailscalePanel id>` |
| `BarDropdown` | Generic bar button that opens a popup panel |
| `DropdownHeader` | Muted section heading |
| `DropdownDivider` | 1 px horizontal rule |
| `DropdownItem` | Row with dot indicator, primary label, secondary label |
| `NixConfig` | Theme colors (`color.baseXX`), font family and size |

#### Writing a custom plugin

A plugin is a `BarWidget` subtype. `BarWidget` handles the sizing boilerplate; you only need to set `implicitWidth`.

Example `MyWidget.qml`:

```qml
import QtQuick

BarWidget {
    NixConfig { id: cfg }

    implicitWidth: _label.implicitWidth + 16

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
    BarLeft {
      Workspaces {}
      MyWidget {}
    }
    BarRight {
      ControlCenter {}
      Clock {}
    }
  '';
  extraPluginDirs = [ ./bar-plugins ];  # directory containing MyWidget.qml
};
```

### 5. Bar IPC

Each bar plugin exposes its own IPC target — no single bottleneck. Targets follow the pattern `bar.<plugin>`:

| Target | Functions |
|---|---|
| `bar.workspaces` | `getFocused()` → string, `list()` → newline-separated names, `switchTo(name)` |
| `bar.volume` | `getVolume()` → int (0–150), `setVolume(v)`, `adjustVolume(delta)`, `isMuted()` → bool, `setMuted(muted)`, `toggleMute()` |
| `bar.media` | `isActive()` → bool, `isPlaying()` → bool, `getTitle()`, `getArtist()`, `togglePlaying()`, `play()`, `pause()`, `next()`, `prev()` |
| `bar.controlcenter` | `toggle()`, `open()`, `close()`, `isOpen()` → bool |

```bash
# Examples
qs ipc call bar.workspaces switchTo 2
qs ipc call bar.volume setVolume 50
qs ipc call bar.media togglePlaying
qs ipc call bar.controlcenter toggle
qs ipc prop get bar.volume isMuted
```

#### Dropdown IPC for custom plugins

Any `BarDropdown` (or `ControlPanel`) with `ipcName` set gets `toggle`/`open`/`close`/`isOpen` automatically:

```qml
BarDropdown {
    ipcName: "mypanel"
    label: "my panel"
    // ...
}
```

```bash
qs ipc call bar.mypanel toggle
qs ipc call bar.mypanel isOpen
```

### 6. Autostart and keybinds (Hyprland)

When `wayland.windowManager.hyprland.enable` is true the module automatically adds `exec-once` entries for all enabled components. You only need to add keybinds:

```nix
wayland.windowManager.hyprland.settings.bind = [
  "$mainMod, SPACE, exec, ${lib.getExe pkgs.quickshell} ipc -c kh-launcher call launcher toggle"
  "$mainMod, V,     exec, ${lib.getExe pkgs.quickshell} ipc -c kh-cliphist call viewer toggle"
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
