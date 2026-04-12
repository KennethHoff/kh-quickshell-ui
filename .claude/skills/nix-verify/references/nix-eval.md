# nix eval reference

`nix eval` evaluates a Nix expression and prints the result. It performs pure evaluation only — no building occurs, making it fast for inspecting config values.

## Basic usage

```bash
nix eval '<installable>' [options] 2>&1
```

An installable is a flake attribute path like `.#packages.x86_64-linux.kh-launcher`.

## Attribute paths in this flake

**Package derivations:**
```bash
nix eval '.#packages.x86_64-linux.<package>' 2>&1
```

**Home-manager options** (evaluated via the consuming flake at ~/nix):
```bash
nix eval '/home/kennethhoff/nix#nixosConfigurations.<host>.config.home-manager.users.kennethhoff.<option.path>' --json 2>&1
```

## Output formats

| Flag | Behavior |
|------|----------|
| _(none)_ | Human-readable Nix expression |
| `--json` | Structured JSON output |
| `--raw` | Print string value verbatim, no quoting |

## Useful flags

- `--read-only` — skip instantiating derivations, faster for pure config values
- `--apply '<nix-function>'` — transform the result before printing
- `--pretty` / `--no-pretty` — control JSON indentation

## Discovering available attributes

```bash
nix eval '.#packages.x86_64-linux' --apply builtins.attrNames --json 2>&1
```

For home-manager options in ~/nix:
```bash
nix eval '/home/kennethhoff/nix#nixosConfigurations.nixos-desktop.config.home-manager.users.kennethhoff.programs.kh-ui' --apply builtins.attrNames --json 2>&1
```

## Examples

```bash
# Check which packages exist
nix eval '.#packages.x86_64-linux' --apply builtins.attrNames --json 2>&1

# Verify kh-ui options are set correctly (via ~/nix)
nix eval '/home/kennethhoff/nix#nixosConfigurations.nixos-desktop.config.home-manager.users.kennethhoff.programs.kh-ui' --json 2>&1
```

## Limitations

- **Functions can't serialize to JSON** — drill deeper to a serializable sub-attribute.
- **Derivations print as store paths.** `--json` gives the path as a string.
- **Eval ≠ build** — a value can eval cleanly but fail to build. Use `nix build` for build verification.
