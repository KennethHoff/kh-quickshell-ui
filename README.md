# quickshell-ui

QML shell components for [Quickshell](https://quickshell.outfoxxed.me/): an application launcher (`kh-launcher`) and clipboard history viewer (`kh-cliphist`).

## Components

| Name | IPC target | Toggle call |
|---|---|---|
| `kh-launcher` | `launcher` | `quickshell ipc -c kh-launcher call launcher toggle` |
| `kh-cliphist` | `viewer` | `quickshell ipc -c kh-cliphist call viewer toggle` |

## Quick start

Run a component directly without installing:

```bash
nix run .#kh-launcher
nix run .#kh-cliphist
```

## Flake integration

### 1. Add the input

```nix
# flake.nix
inputs.quickshell-ui = {
  url = "github:kennethhoff/quickshell-ui";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### 2. Build the configs

There are two approaches depending on whether you want to use your own theme colors.

#### Option A — Pre-built packages (Catppuccin Mocha, no customization)

Use the packages directly:

```nix
programs.quickshell = {
  enable = true;
  configs.kh-launcher = inputs.quickshell-ui.packages.${pkgs.system}.kh-launcher;
  configs.kh-cliphist = inputs.quickshell-ui.packages.${pkgs.system}.kh-cliphist;
};
```

#### Option B — Build with custom colors (Stylix or manual)

Import `config.nix` and `ffi.nix` from the flake source with your own colors and font settings. This is the recommended approach for flakes using Stylix:

```nix
{ inputs, config, pkgs, lib, ... }:
let
  src = inputs.quickshell-ui;

  nixConfig = import (src + "/config.nix") {
    inherit pkgs;
    colors   = config.lib.stylix.colors;      # base00–base0F as 6-char hex strings
    fontName = config.stylix.fonts.monospace.name;
    fontSize = config.stylix.fonts.sizes.applications;
  };

  nixBins = import (src + "/ffi.nix") { inherit pkgs lib; };

  mkConfig = { name, qml }: pkgs.runCommandLocal "qs-${name}" { } ''
    mkdir -p $out/lib
    cp ${src}/lib/*.qml $out/lib/
    cp ${src}/qml/${qml} $out/shell.qml
    cp ${nixConfig} $out/NixConfig.qml
    cp ${nixBins}   $out/NixBins.qml
  '';
in
{
  config = lib.mkIf config.wayland.windowManager.hyprland.enable {
    programs.quickshell = {
      enable = true;
      configs.kh-launcher = mkConfig { name = "kh-launcher"; qml = "kh-launcher.qml"; };
      configs.kh-cliphist = mkConfig { name = "kh-cliphist"; qml = "kh-cliphist.qml"; };
    };
  };
}
```

`config.nix` accepts `colors` as an attrset of `base00`–`base0F` keys with 6-character lowercase hex values (no `#` prefix) — the format Stylix uses directly.

If `kh-cliphist` needs an extra binary (e.g. a custom decode script), pass it via `extraBins`:

```nix
nixBins = import (src + "/ffi.nix") {
  inherit pkgs lib;
  extraBins.cliphistDecodeAll = toString myDecodeScript;
};
```

### 3. Autostart and keybinds (Hyprland)

Both daemons must be started at login and toggled via IPC:

```nix
wayland.windowManager.hyprland.settings = {
  exec-once = [
    "${lib.getExe pkgs.quickshell} -c kh-launcher"
    "${lib.getExe pkgs.quickshell} -c kh-cliphist"
  ];

  bind = [
    "$mainMod, SPACE, exec, ${lib.getExe pkgs.quickshell} ipc -c kh-launcher call launcher toggle"
    "$mainMod, V,     exec, ${lib.getExe pkgs.quickshell} ipc -c kh-cliphist call viewer toggle"
  ];
};
```

## Development

Run the test suite:

```bash
nix flake check
```

Or drop into a dev shell and run tests directly:

```bash
nix develop
qmltestrunner -input tests/
```

Take headless screenshots (requires tmux + kitty terminal):

```bash
# Single shot
nix run .#screenshot -- kh-launcher my-shot

# Multiple shots in one run (shared sway instance)
nix run .#screenshot -- kh-launcher shot-a 'type chrm' -- shot-b "type 'chrm"
```
