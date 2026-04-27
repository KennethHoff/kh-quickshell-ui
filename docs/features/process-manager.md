# Process Manager

Keyboard-driven process viewer, replacing `htop`. Shows running processes
sortable by CPU, RAM, or name; `k` kills the selected process. Toggle via
keybind or IPC, or open by clicking a System Stats bar widget.

## Core

- [1] ⬜ Process list from `/proc` — PID, name, CPU %, RAM
- [2] ⬜ Sort — `s` cycles column, `S` toggles direction
- [3] ⬜ Filter — `/` searches by process name
- [4] ⬜ IPC trigger — openable from CPU/RAM bar widgets

## Actions

- [1] ⬜ Kill — `k` SIGTERM, `K` SIGKILL; confirmation popup

## Views

- [1] ⬜ Tree view — `t` toggles parent/child layout
