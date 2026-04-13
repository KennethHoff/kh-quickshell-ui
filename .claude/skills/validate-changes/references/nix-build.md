# nix build reference

`nix build` builds one or more derivations. In this flake, it's used to verify packages actually compile — not just evaluate.

## Building packages

```bash
nix build \
  .#kh-launcher \
  .#kh-cliphist \
  .#cliphistDecodeAll \
  --out-link .nix-artifacts/result \
  2>&1
```

Build a single package (faster, useful when debugging):
```bash
nix build .#kh-launcher 2>&1
```

## Interpreting build failures

A failing build produces a cascade of errors. The important one is the **root cause** — usually the first derivation listed as failing.

```
error: builder for '/nix/store/...-kh-launcher-config.drv' failed with exit code 1
...
error: 1 dependencies of derivation '/nix/store/...-result.drv' failed to build
```

The first `error: builder for` line is the root cause. The subsequent "dependencies failed" lines are just the cascade — ignore them.

## Useful flags

- `--no-link` — don't create a result symlink
- `--print-build-logs` / `-L` — show full build logs (helpful for debugging shell script errors in config derivations)
- `--rebuild` — force rebuild even if the output already exists in the store

## Inspecting generated QML files

Some QML files are generated at build time by Nix (e.g. `BarLayout.qml` from `bar-layout.nix`).
To inspect the actual generated output after a build:

```bash
# Print the store path, then cat a generated file
nix build .#kh-bar --no-link --print-out-paths 2>/dev/null \
  | xargs -I{} cat {}/BarLayout.qml

# Or list all files in the package
nix build .#kh-bar --no-link --print-out-paths 2>/dev/null | xargs ls -R
```

This is essential when debugging bar plugin rendering issues — the inlined plugin
bodies in `BarLayout.qml` are the actual code Quickshell runs, not the source `.qml` files.

## Why build after flake check?

`nix flake check` evaluates Nix expressions but does not invoke builders. Things that only fail at build time:

- Missing files referenced in `cp` commands inside `runCommandLocal`
- QML syntax errors (caught when Quickshell loads the config, not at eval time)
- `fetchurl` / `fetchFromGitHub` with wrong hashes
