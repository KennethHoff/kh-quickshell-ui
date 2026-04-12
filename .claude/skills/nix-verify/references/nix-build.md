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

## Why build after flake check?

`nix flake check` evaluates Nix expressions but does not invoke builders. Things that only fail at build time:

- Missing files referenced in `cp` commands inside `runCommandLocal`
- QML syntax errors (caught when Quickshell loads the config, not at eval time)
- `fetchurl` / `fetchFromGitHub` with wrong hashes
