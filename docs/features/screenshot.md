# Screenshot

Region/window/fullscreen capture tool, replacing Flameshot. Captures via
`grim`/`slurp`; result goes to clipboard or is saved to a file. Triggered
via keybind or IPC.

## Core

- [1] ⬜ Region capture — `slurp` crosshair; clipboard via `wl-copy`
- [2] ⬜ Fullscreen capture — focused monitor immediately
- [3] ⬜ Window capture — click to select; geometry via Hyprland IPC
- [4] ⬜ IPC — `qs ipc call screenshot <region|fullscreen|window>`

## Output

- [1] ⬜ Save to file — `$XDG_PICTURES_DIR/Screenshots/` with timestamp
- [2] ⬜ Annotation layer — arrows, boxes, text before copy/save
