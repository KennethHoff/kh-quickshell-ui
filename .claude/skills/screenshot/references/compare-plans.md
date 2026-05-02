# Comparing unimplemented variations (plans A/B/C)

Use this when the user wants to see multiple **uncommitted** approaches
side-by-side — "try these three designs", "show me both options", etc.
The working tree must stay untouched, so each variation lives in its
own git worktree.

The persistent VM stays warm — only quickshell respawns between
variations.

## Worktree layout

One worktree per variation under `/tmp` (keeps the parent dir clean and
matches the existing `/tmp/qs-screenshots/` convention):

```bash
root=/tmp/kh-quickshell-ui-worktrees
mkdir -p "$root"
for name in plan-a plan-b plan-c; do
  git worktree add "$root/$name" HEAD
done
```

## Build and capture

Each variation builds its own `kh-bar-headless` from its worktree.
The flake builds from a worktree's working tree directly via a `path:`
ref — commits not required.

```bash
# Daemon must be running:
#   nix run .#kh-headless-daemon   # in another terminal
khh=$(nix eval --raw .#apps.x86_64-linux.kh-headless.program)

ts=$(date +%Y%m%d-%H%M%S)
out=/tmp/qs-screenshots/$ts
mkdir -p "$out"

for name in plan-a plan-b plan-c; do
  cfg=$(nix build "path:/tmp/kh-quickshell-ui-worktrees/$name#kh-bar-headless" \
        --no-link --print-out-paths)
  "$khh" load "$cfg"

  prev=""; cur=""
  for _ in $(seq 30); do
    cur=$("$khh" call testbar getHeight)
    [[ "$cur" == "$prev" && -n "$cur" ]] && break
    prev=$cur; sleep 0.1
  done

  w=$("$khh" call testbar getWidth)
  h=$("$khh" call testbar getHeight)
  src=$("$khh" grim "0,0 ${w}x${h}" "kh-bar-$name.png")
  mv "$src" "$out/kh-bar-$name.png"
done
```

Label each pane with the plan name and a one-line description of what
that variation does differently.

## Parallelising with Agents

Spawn one Agent per plan to implement variations in parallel. Main
Claude stays in control of worktree layout and the screenshot loop —
agents only touch files.

- **Pre-create all worktrees first** so paths are deterministic and
  known to main Claude.
- **Do not** use the Agent tool's `isolation: "worktree"` flag — it
  puts the worktree in a harness-managed location we don't control,
  breaking the deterministic `$root/<plan>` layout the screenshot loop
  relies on.
- **Spawn all agents in a single message** so they run concurrently.
- Each agent's `prompt` must be self-contained: the plan's
  requirements, the absolute path to its worktree
  (`/tmp/kh-quickshell-ui-worktrees/plan-a`), and an explicit
  instruction to edit files **only** under that path and **not commit**
  (the `path:` flake ref builds from the working tree, dirty is fine).
- Agents inherit main Claude's cwd — they must use absolute paths for
  edits.
- When all agents return, main Claude runs the screenshot loop above.

Skip the agents and implement sequentially when the plans are small —
the spin-up overhead isn't worth it. Parallel agents win when each plan
involves real design work or many files.

## Cleanup

`git worktree remove "$root/plan-a"` etc. Do **not** `rm -rf` the
worktree directories — use `git worktree remove` so git's bookkeeping
stays consistent.
