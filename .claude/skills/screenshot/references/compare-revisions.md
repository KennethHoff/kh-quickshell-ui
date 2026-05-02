# Comparing revisions side-by-side

Use this when the user asks why something looks different from before —
"it worked earlier", "when did this change", "compare the current UI to
last week's" — or when validating a UI change against the prior state.

The persistent VM stays warm across the loop — only quickshell respawns
between revisions, so each revision swap costs ~1 s instead of a full
boot.

```bash
# Daemon must be running:
#   nix run .#kh-headless-daemon   # in another terminal
khh=$(nix eval --raw .#apps.x86_64-linux.kh-headless.program)

revs=(229eb8f 7627f79 bd4f8f7)
ts=$(date +%Y%m%d-%H%M%S)
out=/tmp/qs-screenshots/$ts
mkdir -p "$out"

for rev in "${revs[@]}"; do
  cfg=$(nix build "git+file://$PWD?rev=$rev#kh-bar-headless" \
        --no-link --print-out-paths)
  "$khh" load "$cfg"

  # Settle (kh-bar dynamic crop pattern — see kh-bar.md).
  prev=""; cur=""
  for _ in $(seq 30); do
    cur=$("$khh" call testbar getHeight)
    [[ "$cur" == "$prev" && -n "$cur" ]] && break
    prev=$cur; sleep 0.1
  done

  w=$("$khh" call testbar getWidth)
  h=$("$khh" call testbar getHeight)
  src=$("$khh" grim "0,0 ${w}x${h}" "kh-bar-$rev.png")
  mv "$src" "$out/kh-bar-$rev.png"
done
```

Notes:

- Build `kh-bar-headless` (the test config), not `kh-bar` — the dev
  config is pinned to `screen = "DP-1"` which doesn't exist in the VM.
  The test config is part of the flake, so it's available at any
  revision that includes `src/test/`.
- For revisions *before* `src/test/` existed, fall back to a manual
  build of the bar config with `screen = "Virtual-1"`. Or skip those
  revisions.
- For each captured revision the commit hash and subject line can be
  obtained via `git log --format='%h %s' -1 <rev>` — useful as label
  metadata when the orchestrator presents the shots downstream.
