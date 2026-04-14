---
name: test-older-revision
description: Test an older git revision of this repo using nix run without disturbing the working tree.
allowed-tools: Bash(nix run git+file://*), Bash(git log*)
---

When running or testing an older git revision of this repo, use the `nix run`
flake URL syntax to point directly at the revision — **do not use `git checkout`**.

```bash
nix run "git+file://$PWD?rev=<commit-hash>#<app>" -- [args...]
```

## Why

`git checkout` moves the working tree, which disrupts in-progress work, unstaged
changes, and any other agent operating in the repo. The flake URL syntax builds
and runs the pinned revision in isolation without touching the working tree at all.

## Examples

```bash
# Run kh-view at a known-good commit
nix run "git+file://$PWD?rev=3724687a0e01b0d60db759ae528e087694353a56#kh-view" -- /tmp/file.png

# Run kh-bar at a specific revision
nix run "git+file://$PWD?rev=abc1234#kh-bar"

# Run kh-cliphist at a specific revision
nix run "git+file://$PWD?rev=abc1234#kh-cliphist"
```

## Finding the commit hash

```bash
git log --oneline          # recent commits
git log --oneline <file>   # commits touching a specific file
```

## Pinned revisions

The `screenshot` skill keeps a pinned known-good `kh-view` commit for its
display step. Update that pin whenever `kh-view` reaches a new stable state.
