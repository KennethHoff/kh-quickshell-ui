---
name: commit
description: Stage and commit changes following this project's commit conventions. ALWAYS use this skill when committing — never commit manually.
allowed-tools: Bash(git:*)
---

Stage and commit the current changes using [Conventional Commits](https://www.conventionalcommits.org/).

## Steps

1. **Format** — If any `.nix` files are changed, run `nix fmt` before doing anything else. Stage the formatting changes alongside the rest of the work.
2. **Verify** — If any `.nix` or `.qml` files are changed, invoke the `validate-changes` skill using the Skill tool. Do not commit if verification fails. If any `.qml` files add or modify event/IPC handlers, also invoke the `event-handler-delegation` skill and confirm handlers are pure single-line delegations to a `functionality.*` object.
3. **Plan** — Run `git diff` and `git diff --cached` to see all unstaged and already-staged changes. Other agents may be working in this repo concurrently — only commit files that belong to your task. **Never run `git add` without first reviewing `git diff --cached`** — already-staged files will be included in your commit even if you only add one file.
4. **Stage** — Stage one logical group at a time. Use `git add -p <file>` to stage only the specific hunks that belong to your task. Do not use `git add -A`.
5. **Commit** — Commit the staged group with a message following the conventions below. Repeat steps 4–5 for each remaining group.

## Commit conventions

- **Logical commits, not file-by-file.** Group changes by concern: QML UI in one commit, Nix packaging in another, etc.
- **Roadmap always travels with the impl.** If `ROADMAP.md` has a corresponding entry for the work being committed, update it (mark ✅, revise the description) and stage it in the same commit. Never commit a feature/fix and leave the roadmap stale.
- **Scope reflects the component.** Use the logical component being changed — e.g. `(cliphist)`, `(launcher)`, `(bar)`, `(hm-module)`, `(skills)` — not the directory or file name. Omit scope for cross-cutting changes with no clear single owner.
- **Don't squash unrelated things.** Separate concerns get separate commits.
- **Subject line**: `type(scope): short description` — keep under 72 chars. Scope must be lowercase.
- **Body**: explain the *what and why*. When refactoring, mention what was replaced and with what.

## Commit types

Use standard [Conventional Commits types](https://www.conventionalcommits.org/en/v1.0.0/#summary).

## Format

Use a heredoc to pass the message:

```bash
git commit -m "$(cat <<'EOF'
type(scope): subject

Body explaining what and why.
EOF
)"
```
