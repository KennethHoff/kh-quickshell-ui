# kh-bar screenshots

The test bar uses ipcPrefix `testbar`. The root target (`testbar`)
exposes two queries that make cropping and settling-detection precise:

| Call | Returns |
|---|---|
| `testbar getHeight` | Visible bar footprint in px — bar height plus the tallest currently-open dropdown popup. |
| `testbar getWidth` | Bar width in px (3840 on the headless VM's vkms output). |

Plugins sit under `testbar.<plugin>` — e.g. `testbar.volume`,
`testbar.workspaces`, `testbar.media`, `testbar.notifications`.
Groups/dropdowns sit under `testbar.<ipcName>` and expose
`toggle`/`open`/`close`/`isOpen` — the test bar exposes
`testbar.stats` and `testbar.controlcenter`.

Run `kh-headless show` to dump the full surface, or `kh-headless show
testbar.<target>` to filter to one target's methods.

## Standard variants

```bash
cfg=$(nix build .#kh-bar-headless --no-link --print-out-paths)
nix run .#kh-headless -- load "$cfg"

# Chrome only (no dropdowns open).
nix run .#kh-headless -- call testbar.stats         close
nix run .#kh-headless -- call testbar.controlcenter close
# … settle, then capture (see Dynamic crop below).

# Stats dropdown open.
nix run .#kh-headless -- call testbar.controlcenter close
nix run .#kh-headless -- call testbar.stats open

# Controlcenter dropdown open.
nix run .#kh-headless -- call testbar.stats         close
nix run .#kh-headless -- call testbar.controlcenter open
```

## Dynamic crop

Always size the crop from live IPC — no guessing, and the shot
auto-resizes when popups open or close.

```bash
h=$(nix run .#kh-headless -- call testbar getHeight)
w=$(nix run .#kh-headless -- call testbar getWidth)
nix run .#kh-headless -- grim "0,0 ${w}x${h}" bar.png
```

Re-read `getHeight` between shots — it changes with dropdown state.

## Settling via getHeight

`getHeight` reflects the rendered popup's `implicitHeight`, so a
stable value across two consecutive reads means the popup has
committed. Poll it instead of guessing a fixed sleep:

```bash
prev=""; cur=""
for _ in $(seq 30); do
  cur=$(nix run .#kh-headless -- call testbar getHeight)
  [[ "$cur" == "$prev" && -n "$cur" ]] && break
  prev=$cur
  sleep 0.1
done
```

## Performance note

`nix run .#kh-headless` rebuilds the wrapper on every invocation while
the flake is dirty — fine for one-off shots, painful in a loop. For
multi-shot sequences resolve the binary once:

```bash
khh=$(nix eval --raw .#apps.x86_64-linux.kh-headless.program)
"$khh" load "$cfg"
"$khh" call testbar.stats open
# …
```
