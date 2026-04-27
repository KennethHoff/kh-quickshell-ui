# Audio Mixer

Per-app volume mixing UI, replacing `pavucontrol`. Shows all active audio
streams grouped by app, with per-app volume sliders, mute toggles, and live
visualizations indicating which apps are currently producing audio. Toggle
via IPC/keybind.

## Core

- [1] ⬜ Stream list — active PipeWire streams grouped by app
- [2] ⬜ Per-app volume slider — drag or scroll
- [3] ⬜ Per-app mute toggle
- [4] ⬜ Output device selector — default sink from PipeWire sinks

## Visualization

- [1] ⬜ Live activity indicator — VU meter or pulse per stream
