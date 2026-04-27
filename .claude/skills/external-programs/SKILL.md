---
name: external-programs
description: How to wire an external binary (nmcli, tailscale, etc.) into a kh-ui QML plugin via the Nix FFI boundary.
allowed-tools: Read, Grep, Glob
---

# Using external programs in kh-ui plugins

All external binaries must be referenced via Nix store paths — never bare command strings that depend on PATH. This ensures the plugin works when launched from systemd or any other environment where PATH is not set.

## The FFI boundary: src/ffi.nix → NixBins.qml → bin.*

`src/ffi.nix` generates `NixBins.qml` at build time. It exposes two sets of properties:

- **Universal bins** — declared directly in `src/ffi.nix` (e.g. `bash`, `hyprctl`, `jq`). Available in every app.
- **App-specific bins** — passed via `extraBins` to `mkAppConfig` / `mkBarConfig` in `flake.nix` and `src/hm-module.nix`.

## Step 1 — Add the binary to extraBins

Open `flake.nix` and find the relevant `mkAppConfig` / `mkBarConfig` call. Add the binary to `extraBins`:

```nix
# For bar plugins (flake.nix and src/hm-module.nix, mkBarConfig):
extraBins = {
  nmcli     = lib.getExe' pkgs.networkmanager "nmcli";
  tailscale = lib.getExe  pkgs.tailscale;
} // extraBins;
```

Rules:
- Use `lib.getExe pkgs.<name>` when the package's `mainProgram` is the binary you want.
- Use `lib.getExe' pkgs.<name> "<binary>"` when the package provides multiple binaries (e.g. `pkgs.networkmanager` → `"nmcli"`, `pkgs.wl-clipboard` → `"wl-copy"`).
- Always add to **both** `flake.nix` and `src/hm-module.nix` — they are kept in sync.

## Step 2 — Declare NixBins in the plugin file

Each QML file that uses `bin.*` must declare its own instance. QML ids are document-scoped — a `bin` declared in a parent file is not visible here.

```qml
import QtQuick
import Quickshell.Io

BarControlTile {       // or BarPlugin, Item, etc.
    NixBins   { id: bin }
    NixConfig { id: cfg }   // if theming is also needed

    // ...
}
```

## Step 3 — Use bin.* in Process commands

```qml
Process {
    command: [bin.nmcli, "-t", "-f", "DEVICE,TYPE,STATE", "dev"]
    // ...
}
```

Never write:
```qml
command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "dev"]  // ❌ PATH-dependent
```

## Universal bins (no extraBins needed)

These are always available via `NixBins { id: bin }` in any app:

| `bin.*`      | Package                    |
|--------------|----------------------------|
| `bin.bash`   | `pkgs.bash`                |
| `bin.hyprctl`| `pkgs.hyprland`            |
| `bin.jq`     | `pkgs.jq`                  |
| `bin.stat`   | `pkgs.coreutils`           |
| `bin.wlCopy` | `pkgs.wl-clipboard` wl-copy|
| `bin.cliphist`| `pkgs.cliphist`           |

Check `src/ffi.nix` for the current authoritative list.

## App-specific bins (bar)

| `bin.*`       | Package / binary                          |
|---------------|-------------------------------------------|
| `bin.nmcli`   | `lib.getExe' pkgs.networkmanager "nmcli"` |
| `bin.tailscale`| `lib.getExe pkgs.tailscale`              |

## Summary checklist

- [ ] Added to `extraBins` in `flake.nix` (`mkBarConfig` or `mkAppConfig`)
- [ ] Added to `extraBins` in `src/hm-module.nix` (same location)
- [ ] `NixBins { id: bin }` declared in the plugin `.qml` file
- [ ] All `Process { command: [...] }` use `bin.*`, not bare strings
- [ ] Run `nix flake check` to verify evaluation
