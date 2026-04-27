# Patchbay

PipeWire graph editor, replacing `qpwgraph`/`Helvum`. Visualises all PipeWire
nodes (audio, MIDI, video) as boxes with input/output ports, and the links
between them. Keyboard-first — every connect/disconnect that can be done
with a mouse drag must also be doable with vim-style motion + action
bindings and via IPC. Toggle via IPC/keybind.

## Core

- [1] ⬜ Node graph — boxes with name, media class, port list; `pw-dump` source
- [2] ⬜ Port rows — input ports left, output right, labelled
- [3] ⬜ Links — bezier edges, colour-coded by media type
- [4] ⬜ Live updates from PipeWire registry events
- [5] ⬜ Media type filter — toggle audio/MIDI/video independently
- [6] ⬜ IPC — `target: "patchbay"`; toggle/connect/disconnect/list

## Navigation

- [1] ⬜ Modal normal/insert — `hjkl` spatial, `/` filter by name
- [2] ⬜ Port selection — `Tab`/`Shift+Tab` cycles ports on focused node
- [3] ⬜ Follow link — `gd` jumps to peer port across a link
- [4] ⬜ Zoom and pan — `+`/`-` zoom, `Ctrl+hjkl` pan, `gg`/`z.` centre

## Editing

- [1] ⬜ Connect — `c`/Enter on output, navigate to input, confirm
- [2] ⬜ Disconnect — `d` on selected link
- [3] ⬜ Visual link select — `v` then `d` disconnects all
- [4] ⬜ Auto-layout — `=` re-runs topological sources→sinks layout

## Layout

- [1] ⬜ Automatic layout — topological sort, collision-free routing
- [2] ⬜ Manual node positions — drag or `m`+`hjkl`; persisted by node name
- [3] ⬜ Group nodes — collapse same-app streams into expandable group

## Patches

- [1] ⬜ `:w <name>` saves current link set to JSON
- [2] ⬜ `:e <name>` loads and re-creates saved links
- [3] ⬜ Auto-apply on device reconnect — match endpoints by name
