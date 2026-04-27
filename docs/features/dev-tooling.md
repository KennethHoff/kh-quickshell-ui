# Dev Tooling

Improvements to the Claude skills and agentic development workflow.

- [1] ✅ `screenshot` skill passes labels to `kh-view` *(implement together with [File Viewer → optional pane labels](view.md))*
- [2] ⬜ Headless Hyprland for workspace preview screenshots — see [Notes](#notes)

## Notes

**Headless Hyprland** *([2])* — `kh-bar`'s Workspaces plugin uses
`Quickshell.Hyprland` types and `ScreencopyView`, which require a live
Hyprland session; Sway headless can't drive them.

**Dead ends already tried** (don't bother):

- `WLR_BACKENDS=headless` — ignored by Aquamarine
- `AQ_BACKENDS=headless` — not a real env var
- `hyprland --headless` — flag does not exist
- Nesting (leaving `WAYLAND_DISPLAY` set) — renders visibly on the real session
- `HYPRLAND_HEADLESS_ONLY=1` — used by Hyprland's own
  [`hyprtester`](https://github.com/hyprwm/Hyprland/tree/main/hyprtester) CI framework,
  but creates no Wayland display socket; Hyprland's IPC socket exists but Quickshell
  can't connect as a Wayland client. Only useful for testing Hyprland internals directly.

**Fix:** `boot.kernelModules = [ "vkms" ]` in NixOS config. VKMS is a
virtual kernel DRM device with no physical output; Hyprland's DRM backend
accepts it and Aquamarine initialises fully, including creating a Wayland
display socket for clients to connect.

**Implementation sketch** (once VKMS is loaded): add `--compositor hyprland`
to `nix run .#screenshot`; launch with `WAYLAND_DISPLAY`, `DISPLAY`, and
`HYPRLAND_INSTANCE_SIGNATURE` unset; detect the Wayland socket at
`$XDG_RUNTIME_DIR/wayland-*` and IPC sig at `$XDG_RUNTIME_DIR/hypr/<sig>/`;
seed fake windows via `exec-once = [workspace N] weston-simple-shm` so
`ScreencopyView` has something to capture.
