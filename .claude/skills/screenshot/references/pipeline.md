# Screenshot pipeline

The core bash pipeline: bring up headless sway, spawn quickshell with the
target app's config, drive state via IPC, capture with grim, tear down.

Output files go to `/tmp/qs-screenshots/<timestamp>/<name>.png`.

## Single shot

```bash
set -e
qs=$(nix build nixpkgs#quickshell --no-link --print-out-paths)/bin/quickshell
sway=$(nix build nixpkgs#sway --no-link --print-out-paths)/bin/sway
grim=$(nix build nixpkgs#grim --no-link --print-out-paths)/bin/grim
cfg=$(nix build .#kh-bar --no-link --print-out-paths)   # ← swap app here

run=/tmp/qs-screenshots/$(date +%Y%m%d-%H%M%S)
mkdir -p "$run"
xdg=$(mktemp -d); export XDG_RUNTIME_DIR=$xdg
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_HEADLESS_OUTPUTS=1
scfg=$(mktemp); echo 'output HEADLESS-1 resolution 3840x2160' > "$scfg"

"$sway" --config "$scfg" >/dev/null 2>&1 &
SPID=$!
# wait for sway socket
for i in $(seq 40); do
  sleep 0.1
  sock=$(ls "$xdg"/wayland-* 2>/dev/null | grep -v lock | head -1)
  [[ -n "$sock" ]] && break
done
export WAYLAND_DISPLAY=$(basename "$sock")

"$qs" -p "$cfg" >/dev/null 2>&1 &
QPID=$!
# wait for IPC — use a safe query (not an action) as the readiness probe
for i in $(seq 60); do
  sleep 0.1
  "$qs" ipc --pid "$QPID" call <target> <safe-query> >/dev/null 2>&1 && break
done

# drive state
"$qs" ipc --pid "$QPID" call <target> <action> [<args>...]

# settle — see timing guidance below
sleep 0.5

# capture — pick a crop per the app table in SKILL.md. For kh-bar, size
# the crop from the live IPC (see kh-bar.md).
out=$run/myshot.png
"$grim" -g "0,0 3840x500" "$out"
echo "$out"

# teardown
kill -9 "$QPID" 2>/dev/null || true; wait "$QPID" 2>/dev/null || true
kill -9 "$SPID" 2>/dev/null || true
rm -rf "$xdg"
```

## Readiness probe

Always probe with a **safe query** (e.g. `isOpen`, `getCount`, a prop read) —
never with the action you're about to perform. Re-firing an action on every
retry mutates state unpredictably (e.g. a `toggle` may cycle off again).

If the target has no query, use `qs ipc --pid $PID prop get <target> <prop>`
as the probe — it returns a value without side effects.

## Timing (post-IPC sleep before grim)

| State change | Sleep |
|---|---|
| Bar chrome only, no popups | 0.25s |
| `PopupWindow` open (e.g. BarDropdown) | 1.0s — compositor needs time to commit the new surface under headless pixman |
| OSD / fade-in animation | 0.5s |
| Launcher / cliphist overlay | 0.5s |

Short sleeps before grim are the most common cause of "the dropdown didn't
appear in my shot." When in doubt, 1.0s.

For kh-bar, prefer polling `dev-bar getHeight` until it stabilises instead
of a fixed sleep — see [kh-bar.md](kh-bar.md).

## Multi-shot

Keep `$SPID` and `$QPID` alive across multiple `grim` calls. Change IPC state
between shots. Only re-spawn `quickshell` when switching app configs.

```bash
# after the first grim call
"$qs" ipc --pid "$QPID" call <target> <other-action>
sleep 0.5
"$grim" -g "<crop>" "$run/second.png"
```

## Fonts

Headless sway uses the host's fontconfig. This is usually fine. If a shot
needs hermetic fonts (e.g. comparing against reference pixels), set
`FONTCONFIG_FILE` to a minimal conf pointing at
`$(nix build nixpkgs#dejavu_fonts --no-link --print-out-paths)/share/fonts` and
`$(nix build nixpkgs#nerd-fonts.symbols-only --no-link --print-out-paths)/share/fonts`.
