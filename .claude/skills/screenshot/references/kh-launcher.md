# kh-launcher screenshots

The launcher uses IPC target `launcher`. Three plugins are registered at
build time and all three populate in the headless VM thanks to fixtures:

| Plugin name (lowercase!) | Items in headless VM | Fixture |
|---|---|---|
| `apps` | 8 (Browser, Calculator, Files, Mail, Music, Photos, Settings, Terminal) | `src/test/launcher-fixture.nix` — pinned via `XDG_DATA_DIRS` in `vm.nix`. |
| `emoji` | ~3900 fully-qualified Unicode 17 emoji + CLDR keywords. | `pkgs.unicode-emoji` + `pkgs.cldr-annotations`, joined at Nix eval time into a static TSV. No fixture needed. |
| `hyprland-windows` | 3 (Files, Browser, Terminal) | `src/test/mocks/fake-clients.sh` — Hyprland `exec-once` spawns three named `foot` terminals before the harness comes up. |

Plugin keys are **lowercase** when calling `activatePlugin` — passing
`Apps`/`Emoji`/`Windows` (the *labels* shown on the chips) silently
falls through to an empty `_pluginConfig`, leaves the script unspawned,
and you get `itemCount=0`.

## Standard variants

```bash
cfg=$(nix build .#kh-launcher-headless --no-link --print-out-paths)
nix run .#kh-headless -- load "$cfg"
nix run .#kh-headless -- call launcher toggle    # opens; default plugin is 'apps'

# Switch plugin (lowercase name)
nix run .#kh-headless -- call launcher activatePlugin emoji
nix run .#kh-headless -- call launcher activatePlugin hyprland-windows
nix run .#kh-headless -- call launcher activatePlugin apps

# Type into the search field
nix run .#kh-headless -- call launcher type smile
nix run .#kh-headless -- call launcher key BackSpace   # five times to clear
```

## Settling

The plugin script runs in a `Process`. Wait for items via:

```bash
for _ in $(seq 30); do
  n=$(nix run .#kh-headless -- prop launcher itemCount)
  [[ "$n" -gt 0 ]] && break
  sleep 0.1
done
```

A flat 1-2 s sleep also works — the apps fixture has 8 items, emoji has
3944, and hyprland-windows has 3, all of which load in well under a
second on llvmpipe.

## Crop

The launcher panel is centred and sized at `panel.width = round(parent.width * 0.42)` and
`panel.height = round(parent.height * 0.65)`, with `topMargin = round(parent.height * 0.08)`.
On the VM's 3840×2160 Virtual-1 output that's:

| Geometry | Value |
|---|---|
| width | `round(3840 * 0.42) = 1613` |
| height | `round(2160 * 0.65) = 1404` |
| topMargin | `round(2160 * 0.08) = 173` |
| left | `(3840 - 1613) / 2 = 1113` |

Crop suggestion (rounded for readability):

```bash
nix run .#kh-headless -- grim "1110,170 1620x1410" launcher.png
```

If you only need the chrome (search box + plugin chips), drop the
height to ~120 px:

```bash
nix run .#kh-headless -- grim "1110,170 1620x120" launcher-chrome.png
```

## Caveats

- `Loading...` text appears whenever `_allItems.length === 0` — it does
  not distinguish "still loading" from "loaded, empty". If you see it
  after settling, the plugin script returned zero lines (typically:
  fixture missing, wrong env var, plugin name typo'd in `activatePlugin`).
- `weston-simple-shm` was previously used for fake clients but is no
  longer shipped by `pkgs.weston`; the harness now spawns `foot` with
  per-instance `-a/-T` so each window has a unique class+title.
