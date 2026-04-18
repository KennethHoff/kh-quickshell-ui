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

Try out a component directly:

```bash
nix run github:KennethHoff/kh-quickshell-ui#kh-bar
nix run github:KennethHoff/kh-quickshell-ui#kh-launcher
nix run github:KennethHoff/kh-quickshell-ui#kh-cliphist
nix run github:KennethHoff/kh-quickshell-ui#kh-view
nix run github:KennethHoff/kh-quickshell-ui#kh-osd
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

If [Stylix](https://github.com/nix-community/stylix) is present, colors and fonts are picked up automatically. Otherwise a built-in dark palette and monospace font are used. You can override any theme value explicitly — see `programs.kh-ui.theme`.

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

## Component documentation

| Component | Description | Docs |
|---|---|---|
| `kh-bar` | Status bar — layout, plugins, custom plugins, IPC | **[docs/bar.md](docs/bar.md)** |
| `kh-launcher` | Launcher — mode system, custom modes, IPC | **[docs/launcher-modes.md](docs/launcher-modes.md)** |
| `kh-cliphist` | Clipboard history — IPC | **[docs/clipboard-history.md](docs/clipboard-history.md)** |
| `kh-view` | File/image viewer — IPC | **[docs/view.md](docs/view.md)** |
| `kh-osd` | Volume OSD — configuration, keybinds, IPC | **[docs/osd.md](docs/osd.md)** |

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
