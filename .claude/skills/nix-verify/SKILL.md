---
name: nix-verify
description: Verify that the nix configurations evaluate and build correctly. ALWAYS run this after editing any .nix file — no change is too small to skip verification. Do not present changes as complete without running this first.
allowed-tools: Bash(nix:*)
---

## Step 1 — Evaluate

Run `nix flake check` to verify all configurations evaluate correctly:

```bash
nix flake check 2>&1
```

A passing run ends with `all checks passed!`. Investigate any errors before proceeding.

## Step 2 — Spot-check specific option values (optional)

When a change targets a specific package or home-manager option, use `nix eval` to verify the evaluated value matches expectations:

```bash
# Package output paths
nix eval '.#packages.x86_64-linux.<package>' 2>&1

# home-manager options (evaluated via the consuming flake at ~/nix)
nix eval '/home/kennethhoff/nix#nixosConfigurations.nixos-desktop.config.home-manager.users.kennethhoff.<option.path>' --json 2>&1
```

## Step 3 — Build (final verification only)

Build all packages to verify they actually compile. This is expensive — only run it when confident the changes are complete or near-complete. Step 1 is cheap and should be used freely during iteration.

```bash
nix build \
  .#kh-launcher \
  .#kh-cliphist \
  .#cliphistDecodeAll \
  --out-link .nix-artifacts/result \
  2>&1
```

A passing run produces no output. `.nix-artifacts/` is gitignored.
