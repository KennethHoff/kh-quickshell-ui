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

The bar has a left slot (left-to-right) and a right slot (right-to-left). Default layout:

```nix
programs.kh-ui.bar = {
  leftPlugins  = [ "Workspaces" "MediaPlayer" ];
  rightPlugins = [ "ControlCenter" "Clock" "Volume" "Tray" ];
};
```

Built-in plugins:

| Plugin | Slot | Description |
|---|---|---|
| `Workspaces` | left | Hyprland workspace switcher; hover for live preview thumbnail |
| `MediaPlayer` | left | MPRIS prev/play-pause/next + track info; hidden when no player active |
| `ControlCenter` | right | `●●●` button → panel with Ethernet and Tailscale tiles + peer list |
| `Clock` | right | `HH:mm:ss` clock |
| `Volume` | right | PipeWire volume; scroll to adjust, click to mute; hidden when no sink |
| `Tray` | right | StatusNotifierItem tray icons; left-click activates, right-click menu |

#### Writing a custom plugin

A plugin is a `BarWidget` subtype. `BarWidget` handles the sizing boilerplate; you only need to set `implicitWidth`.

The bar also exposes these shared library components at the config root, usable in any plugin without an import statement:

| Component | Purpose |
|---|---|
| `NixConfig` | Theme colors (`cfg.color.baseXX`), font family, font size |
| `BarDropdown` | Button that opens a popup panel; add children as panel content |
| `ControlCenterPanel` | Like `BarDropdown` but with a tile `Flow` (`tiles:`) above the content |
| `ControlTile` | Rounded toggle tile with label, sublabel, and active/inactive colors |
| `DropdownHeader` | Muted section heading inside a dropdown panel |
| `DropdownDivider` | 1 px horizontal rule |
| `DropdownItem` | Row with optional dot indicator, primary label, and secondary label |

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

Place your plugin files in a directory and pass it via `extraPluginDirs`. Plugins are referenced by filename (without `.qml`):

```nix
programs.kh-ui.bar = {
  leftPlugins     = [ "Workspaces" "MyWidget" ];
  rightPlugins    = [ "ControlCenter" "Clock" "Volume" "Tray" ];
  extraPluginDirs = [ ./bar-plugins ];  # directory containing MyWidget.qml
};
```

### 5. Autostart and keybinds (Hyprland)

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
