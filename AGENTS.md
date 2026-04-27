# Agent notes

Project-specific gotchas for AI agents working on this repo.

## Backwards compatibility is not a concern

This repo has no external consumers and no stability guarantees. Make API-breaking changes freely when they improve the code — don't add shims, deprecation paths, or compatibility wrappers to preserve old call sites. Update all callers in the same change.

## Nix: new files must be `git add`-ed before building

`${self}` in a Nix flake refers to the git-tracked source tree. **Untracked files are invisible to Nix** — they are silently omitted from the build even though they exist on disk.

Whenever you create a new `.qml`, `.nix`, or any other file that the build needs, run:

```bash
git add <file>
```

before `nix build` or `nix run`. Without this, the build will succeed but the file will be missing at runtime, causing errors like `Foo is not a type` or missing imports that are impossible to reproduce from the diff alone.

This applies even to files in `src/lib/` that are picked up by a glob (`cp ${self}/src/lib/*.qml ...`) — the glob only sees tracked files.
