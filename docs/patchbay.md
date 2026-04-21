# Patchbay (`kh-patchbay`)

PipeWire graph editor, replacing `qpwgraph` / `Helvum`. Scaffolding only at this stage: the graph is viewable but not yet editable.

## Configuration

```nix
programs.kh-ui = {
  enable = true;
  patchbay.enable = true;
};
```

Enables a long-running Quickshell daemon. The overlay is hidden by default and toggled via IPC.

## Keybind (Hyprland example)

```nix
wayland.windowManager.hyprland.settings.bind = [
  "SUPER, P, exec, qs ipc -c kh-patchbay call patchbay toggle"
];
```

## IPC

| Target     | Function                  | Notes                                                       |
|------------|---------------------------|-------------------------------------------------------------|
| `patchbay` | `toggle()`                | Show / hide the overlay                                     |
| `patchbay` | `open()` / `close()`      |                                                             |
| `patchbay` | `refresh()`               | Force an immediate `pw-dump` poll                           |
| `patchbay` | `listNodes(): string`     | JSON array — `{id, name, description, mediaClass, ports}`   |
| `patchbay` | `listLinks(): string`     | JSON array — `{id, srcNodeId, srcPortId, dstNodeId, dstPortId, mediaType, state}` |
| `patchbay` | `showing: bool`           | Readable prop                                               |

## Current scope

- Nodes rendered as boxes, grouped into three columns by kind (source → bridge → sink) based on input / output port counts.
- Ports labelled on each node; input ports on the left edge, output ports on the right.
- Bezier edges drawn between connected ports, colour-coded by media type.
- Graph refreshes every 2 s while the overlay is open (via `pw-dump`).
- `Esc` / `q` closes.

Not yet implemented — see the Patchbay section of `ROADMAP.md` for the plan: live registry updates, media-type filtering, keyboard navigation, connect / disconnect editing, automatic layout, persistent manual positions, and saved patches.
