---
name: quickshell-docs
description: Look up Quickshell type documentation. Use when you need to check a type's properties, signals, or methods before writing or editing QML.
allowed-tools: WebFetch
---

Look up Quickshell documentation for a type or module.

## URL structure

```
https://quickshell.org/docs/v0.2.1/types/<Module>/
https://quickshell.org/docs/v0.2.1/types/<Module>/<Type>
```

Examples:
- Module index: `https://quickshell.org/docs/v0.2.1/types/Quickshell.Hyprland/`
- Specific type: `https://quickshell.org/docs/v0.2.1/types/Quickshell.Hyprland/HyprlandWindow`

## Available modules

| Module | What's in it |
|--------|-------------|
| `Quickshell` | Core types: ShellRoot, LazyLoader, PanelWindow, Variants, etc. |
| `Quickshell.Bluetooth` | Bluetooth devices and adapters |
| `Quickshell.DBusMenu` | DBus menu integration |
| `Quickshell.Hyprland` | Hyprland IPC — monitors, windows, workspaces, shortcuts |
| `Quickshell.I3` | i3/Sway IPC |
| `Quickshell.Io` | File I/O, process execution, sockets |
| `Quickshell.Services.Greetd` | Greeter daemon integration |
| `Quickshell.Services.Mpris` | Media player control |
| `Quickshell.Services.Notifications` | Desktop notifications |
| `Quickshell.Services.Pam` | PAM authentication |
| `Quickshell.Services.Pipewire` | Audio via PipeWire |
| `Quickshell.Services.SystemTray` | System tray items |
| `Quickshell.Services.UPower` | Battery / power |
| `Quickshell.Wayland` | Wayland protocols (layer shell, etc.) |
| `Quickshell.Widgets` | Ready-made UI widgets |

## How to look something up

1. **Know the module?** Fetch the module index to see all types and pick the right one.
2. **Know the type?** Fetch the type page directly for its properties, signals, and methods.
3. **Unsure which module?** Start at `https://quickshell.org/docs/v0.2.1/types/` — the sidebar lists every type.

Always fetch the page with a specific prompt such as *"list all properties and their types"* or *"show the signal signatures"* to get a concise answer rather than the full page dump.
