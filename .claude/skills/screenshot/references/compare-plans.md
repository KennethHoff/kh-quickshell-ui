# Comparing unimplemented variations (plans A/B/C)

Use this when the user wants to see multiple **uncommitted** approaches
side-by-side — "try these three designs", "show me both options", etc.
The working tree must stay untouched, so each variation lives in its
own git worktree.

## Worktree layout

One worktree per variation, under `/tmp` to keep the parent directory
clean and match the existing `/tmp/qs-screenshots/` convention:

```bash
root=/tmp/kh-quickshell-ui-worktrees
mkdir -p "$root"
for name in plan-a plan-b plan-c; do
  git worktree add "$root/$name" HEAD
done
```

## Build and capture

Implement each variation in its own worktree (edit files under
`/tmp/kh-quickshell-ui-worktrees/plan-a`, etc. — commits not required,
the flake builds from the worktree's working tree via a `path:` ref).
Then build and capture per worktree:

```bash
for name in plan-a plan-b plan-c; do
  cfg=$(nix build "path:/tmp/kh-quickshell-ui-worktrees/$name#kh-bar" --no-link --print-out-paths)
  # per-variation body mirrors pipeline.md (spawn qs, probe, IPC, settle, grim)
  "$qs" -p "$cfg" >/dev/null 2>&1 &
  QPID=$!
  # ...probe + IPC + settle...
  "$grim" -g "<crop>" "$run/$name.png"
  kill -9 "$QPID" 2>/dev/null || true; wait "$QPID" 2>/dev/null || true
done
```

Label each pane with the plan name and a one-line description of what
that variation does differently.

## Parallelising with Agents

Spawn one Agent per plan to implement the variations in parallel.
Main Claude stays in control of worktree layout and the screenshot
pipeline — agents only touch files.

- **Pre-create all worktrees first** (the `git worktree add` loop
  above) so paths are deterministic and known to main Claude.
- **Do not** use the Agent tool's `isolation: "worktree"` flag here —
  that puts the worktree in a harness-managed location we don't
  control, which breaks the deterministic `$root/<plan>` layout the
  screenshot loop relies on.
- **Spawn all agents in a single message** (multiple Agent tool calls
  in one response) so they run concurrently.
- Each agent's `prompt` must be self-contained: the plan's
  requirements, the absolute path to its worktree
  (`/tmp/kh-quickshell-ui-worktrees/plan-a`), and an explicit
  instruction to edit files **only** under that path and **not
  commit** (the `path:` flake ref builds from the working tree, dirty
  is fine).
- Agents inherit main Claude's cwd — they must use absolute paths for
  edits. No need to `cd` into the worktree.
- When all agents return, main Claude runs the screenshot loop.

Skip the agents and implement sequentially from main Claude when the
plans are small (a handful of edits each) — the spin-up overhead
isn't worth it. Parallel agents win when each plan involves real
design work or many files.

## Cleanup

`git worktree remove "$root/plan-a"` etc. Do **not** `rm -rf` the
worktree directories — use `git worktree remove` so git's bookkeeping
stays consistent.
