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

The bar displays plugins in a left slot and a right slot. The default layout is Workspaces on the left and Clock on the right.

```nix
programs.kh-ui.bar = {
  leftPlugins  = [ "Workspaces" ];  # default
  rightPlugins = [ "Clock" ];        # default
};
```

#### Writing a custom plugin

A plugin is a `.qml` file that acts as a self-contained `Item`. It must:
- Declare `required property int barHeight` — the bar passes its height through this.
- Set `implicitWidth` to size the item horizontally; `implicitHeight` is handled for you.

Example `MyWidget.qml`:

```qml
import QtQuick

Item {
    required property int barHeight
    implicitHeight: barHeight
    width: implicitWidth
    height: implicitHeight

    NixConfig { id: cfg }  // theme colors and font

    implicitWidth: label.implicitWidth + 16

    Text {
        anchors.centerIn: parent
        text: "hello"
        color: cfg.color.base05
        font.family: cfg.fontFamily
        font.pixelSize: cfg.fontSize
    }
}
```

Place your plugin files in a directory and pass it via `extraPluginDirs`. Plugins are referenced by filename (without `.qml`):

```nix
programs.kh-ui.bar = {
  leftPlugins    = [ "Workspaces" "MyWidget" ];
  rightPlugins   = [ "Clock" ];
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
