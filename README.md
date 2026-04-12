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
inputs.kh-quickshell-ui = {
  url = "github:KennethHoff/kh-quickshell-ui";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### 2. Import the home-manager module

The flake exports a home-manager module at `homeManagerModules.default` that handles everything — building configs from Stylix colors, registering them, and defining the `kh-ui` option.

Import it alongside your other home-manager modules (e.g. in `sharedModules` or a home-manager aspect):

```nix
imports = [ inputs.kh-quickshell-ui.homeModules.default ];
```

The module requires [Stylix](https://github.com/nix-community/stylix) — colors and fonts are read from `config.lib.stylix` at build time.

### 3. Enable the components

With the module imported, enabling both components is a single option:

```nix
programs.kh-ui.enable = true;
```

Individual components can be disabled while keeping the rest active:

```nix
programs.kh-ui = {
  enable = true;
  launcher.enable = false;          # disable kh-launcher
  clipboard-history.enable = false; # disable kh-cliphist
};
```

### 4. Autostart and keybinds (Hyprland)

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

Take headless screenshots (with optional tmux + kitty display integration):

```bash
# Single shot
nix run .#screenshot -- kh-launcher my-shot

# Multiple shots in one run (shared sway instance)
nix run .#screenshot -- kh-launcher shot-a 'type chrm' -- shot-b "type 'chrm"
```
