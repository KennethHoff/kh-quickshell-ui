# OSD

Transient overlay that appears briefly on system events such as volume
changes. Currently a single hardcoded volume display; the end goal is a
plugin architecture matching the bar — user-composable slots, each slot an
independent QML component with its own bindings and IPC.

## Core

- [1] ✅ Volume OSD — appears on volume up/down/mute
- [2] ✅ Auto-dismiss — fades after ~2 s; timer resets on change
- [3] ✅ IPC — `osd showVolume <0–100>` / `osd showMuted`
- [4] ⬜ Plugin system — composable OSD plugins matching the bar pattern
- [5] ⬜ Volume plugin — extract current display into `OsdVolume`
- [6] ⬜ Per-plugin dismiss timer — independent visibility per plugin

## Audio plugins

Each plugin is **reactive** — subscribes to its own signal source,
self-triggers on a state transition, then dismisses.

- **OsdVolume** *(extracted from current impl)* — volume on up/down/mute
- **OsdMicMute** — mic mute toggle indicator; via PipeWire input sink

## Connectivity plugins

- **OsdBluetooth** — device + connected/disconnected on pairing events
- **OsdVpn** — VPN interface up/down; IPC-driven (no standard signal)
