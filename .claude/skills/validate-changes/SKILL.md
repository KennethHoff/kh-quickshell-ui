---
name: validate-changes
description: Validate that changes did what was expected — covers both Nix configuration and QML UI. ALWAYS run this after editing any .nix or .qml file. Do not present changes as complete without running this first.
allowed-tools: Bash(nix:*), Bash(tmux:*), Bash(kitty:*)
---

## Step 1 — Evaluate (Nix changes)

Run `nix flake check` to verify all configurations evaluate correctly:

```bash
nix flake check 2>&1
```

A passing run ends with `all checks passed!`. Investigate any errors before proceeding.

For details on what flake check does and doesn't catch, see [references/nix-flake-check.md](references/nix-flake-check.md).

## Step 2 — Spot-check specific option values (optional)

When a change targets a specific package or home-manager option, use `nix eval` to verify the evaluated value matches expectations:

```bash
# Package output paths
nix eval '.#packages.x86_64-linux.<package>' 2>&1

# home-manager options (evaluated via the consuming flake at ~/nix)
nix eval '/home/kennethhoff/nix#nixosConfigurations.nixos-desktop.config.home-manager.users.kennethhoff.<option.path>' --json 2>&1
```

For full usage details, see [references/nix-eval.md](references/nix-eval.md).

## Step 3 — Build and inspect generated QML (final verification only)

Build all packages to verify they actually compile. This is expensive — only run it when confident the changes are complete or near-complete. Steps 1 and 2 are cheap and should be used freely during iteration.

```bash
nix build \
  .#kh-launcher \
  .#kh-cliphist \
  .#cliphistDecodeAll \
  --out-link .nix-artifacts/result \
  2>&1
```

A passing run produces no output. On failure, see [references/nix-build.md](references/nix-build.md) for how to interpret errors.

### Inspecting generated QML

Some files are generated at build time (e.g. `BarLayout.qml` from `bar-layout.nix`). After building `kh-bar`, inspect the actual output to verify the generated code looks right — especially after changes to `bar-layout.nix` or adding new plugins:

```bash
nix build .#kh-bar --no-link --print-out-paths 2>/dev/null \
  | xargs -I{} cat {}/BarLayout.qml
```

This is the code Quickshell actually runs. If plugins aren't rendering or there are runtime errors, this is the first place to look.

## Step 4 — Screenshot (QML changes)

For any change that affects the UI (`.qml` files, or Nix changes that affect runtime behavior), take a screenshot to visually confirm the result matches expectations. Use the `screenshot` skill.

- Target the specific app and view affected by the change
- Compare against a before screenshot if one was taken prior to editing

For QML error patterns to watch for, see [references/qml-common-errors.md](references/qml-common-errors.md).

## Troubleshooting

For common Nix error patterns and how to fix them, see [references/nix-common-errors.md](references/nix-common-errors.md).

For how this flake is structured and where to find attribute paths, see [references/nix-flake-structure.md](references/nix-flake-structure.md).

For how the QML files are organized and where views/styling live, see [references/qml-structure.md](references/qml-structure.md).
