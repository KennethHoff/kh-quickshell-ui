# OSD (`kh-osd`)

A transient bottom-center overlay that appears when the default PipeWire sink volume or mute state changes. No keybind wiring required — run the daemon and it reacts automatically.

## Configuration

```nix
programs.kh-ui = {
  enable = true;
  osd.enable = true;
  volumeMax = 1.5;   # optional — ceiling for volume bar and bar plugin (default 1.5 = 150%)
};
```

`volumeMax` should match the `-l` flag on your `wpctl set-volume` keybinds. The progress bar spans the full `0–volumeMax` range so over-amplified levels display correctly.

## Keybinds

No special wiring needed for the OSD itself — plain `wpctl` calls are enough:

```nix
wayland.windowManager.hyprland.settings.bind = [
  ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"
  ", XF86AudioLowerVolume, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%-"
  ", XF86AudioMute,        exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
];
```

## IPC

The OSD exposes IPC for testing or manual triggering:

| Target | Functions |
|---|---|
| `osd` | `showVolume(value)` — show at given level (0-150); `showMuted()` — show muted state |

```bash
qs ipc -c kh-osd call osd showVolume 75
qs ipc -c kh-osd call osd showMuted
```
