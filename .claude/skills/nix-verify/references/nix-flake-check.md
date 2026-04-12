# nix flake check reference

`nix flake check` evaluates all outputs of a flake and runs basic validation. It is the first line of defense but has important gaps.

## What it checks

- All `checks` derivations build successfully (the QML test suite)
- All `packages` derivations evaluate
- All `apps` are valid
- Flake output schema is valid (correct attribute types)

## What it does NOT check

- **Does not build packages** — it evaluates them but does not invoke the builder. A package can pass `flake check` and still fail to build (e.g. a broken store path, a QML compile error).
- **Does not validate the home-manager module** — `homeManagerModules.default` is listed as an unknown output and not evaluated. Use `nix eval` against the consuming flake (~/nix) to verify it.
- **Does not validate runtime behavior** — Quickshell IPC, window rendering, etc. are only checked by running the app.

## Common output

```
# Success
all checks passed!

# Evaluation error
error: attribute 'foo' missing
       at /nix/store/.../flake.nix:42:5

# Unknown output (expected — nix doesn't know homeManagerModules)
warning: unknown flake output 'homeManagerModules'
```
