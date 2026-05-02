# Dev Tooling

Improvements to the Claude skills and agentic development workflow.

- [1] ✅ `screenshot` skill passes labels to `kh-view` *(implement together with [File Viewer → optional pane labels](view.md))*
- [2] ✅ Headless Hyprland for workspace preview screenshots — see [Notes](#notes)

## Notes

**Headless Hyprland** *([2])* — `kh-bar`'s Workspaces plugin uses
`Quickshell.Hyprland` types and `ScreencopyView`, which require a live
Hyprland session; Sway headless can't drive them. Same applies to
`kh-window-inspector`.

Solved by `src/test/`: a NixOS microvm running Hyprland on a vkms
virtual DRM device. The host-side `kh-headless` CLI sends primitive
ops (load / call / prop / show / list / grim / status / kill) over a
virtiofs share. The harness inside the VM dispatches them and writes
PNGs back to the host.

Boot the VM once:

```sh
nix run .#kh-headless-daemon
```

Drive it from any other terminal:

```sh
cfg=$(nix build .#kh-bar-headless --no-link --print-out-paths)
nix run .#kh-headless -- load "$cfg"
nix run .#kh-headless -- call testbar.volume setMuted true
nix run .#kh-headless -- grim "0,0 3840x32" muted-bar.png
```

The screenshot skill (`.claude/skills/screenshot/`) routes through this
flow — see SKILL.md.

**Dead ends already tried** (don't bother):

- `WLR_BACKENDS=headless` — ignored by Aquamarine
- `AQ_BACKENDS=headless` — not a real env var
- `hyprland --headless` — flag does not exist
- Nesting (leaving `WAYLAND_DISPLAY` set) — renders visibly on the real session
- `HYPRLAND_HEADLESS_ONLY=1` — used by Hyprland's own
  [`hyprtester`](https://github.com/hyprwm/Hyprland/tree/main/hyprtester) CI framework,
  but creates no Wayland display socket; Hyprland's IPC socket exists but Quickshell
  can't connect as a Wayland client. Only useful for testing Hyprland internals directly.
- Running `Hyprland` directly without `start-hyprland` — works, but the
  on-screen "started without start-hyprland" CHyprError overlay covers
  the right half of the bar in screenshots.
