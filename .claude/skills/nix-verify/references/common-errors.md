# Common errors

## Evaluation errors (caught by `nix flake check`)

### Option conflicts

```
error: The option `services.foo.enable' in ... is already declared in ...
```

A custom module declares an option that upstream nixpkgs now also declares. Fix: remove the custom option declaration and use the upstream one.

### Infinite recursion

```
error: infinite recursion encountered
```

Usually caused by:
- A module adding options to a namespace that another module defines as a submodule type
- Circular `imports` between modules
- An option default that references itself through `config`

Debug by bisecting: comment out half the modules and narrow down which one triggers it.

### Undefined options

```
error: The option `programs.foo.bar' does not exist.
```

A host config references an option from a module that was deleted, renamed, or not imported. Check `imports` lists and option paths.

### Type errors

```
error: A definition for option `...' is not of type `...'
```

An option is set to a value of the wrong type (e.g. string where a list is expected). Check the option's type with `nix eval` or the NixOS option search.

## Build errors (caught by `nix build`)

### Plugin build failures

```
error: builder for '/nix/store/...-vimplugin-foo.drv' failed
```

Common with Vim/Neovim plugins that run test suites during build. Fix with `doCheck = false` in the plugin override.

### Wrong fetch hash

```
error: hash mismatch in fixed-output derivation
  specified: sha256-AAAA...
  got:       sha256-BBBB...
```

The hash in `fetchFromGitHub` or similar doesn't match the actual content. Replace with the `got:` hash. This usually means upstream changed (a tag was force-pushed, or the `rev` was updated without updating the hash).

### Missing dependencies

```
error: attribute 'foo' missing
       at /nix/store/...-source/default.nix:5:3
```

A package or module references an attribute that doesn't exist in nixpkgs. Common after a nixpkgs update where a package was renamed or removed. Check the nixpkgs changelog or search for the new name.

### Broken package overrides

```
error: evaluation aborted with the following error message: 'Package foo has been removed...'
```

Upstream removed or renamed a package. Check `nixpkgs/pkgs/by-name` or the nixpkgs commit log for what replaced it.
