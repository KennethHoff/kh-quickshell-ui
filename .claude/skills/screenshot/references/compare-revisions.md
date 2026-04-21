# Comparing revisions side-by-side

Use this when the user asks why something looks different from before —
"it worked earlier", "when did this change", "compare the current UI to
last week's" — or when validating a UI change against the prior state.

Build each revision's config via the `git+file://` flake URL (same
approach as the [`test-older-revision`](../../test-older-revision/SKILL.md)
skill — no `git checkout`, working tree stays untouched), then capture
one shot per revision.

```bash
revs=(229eb8f 7627f79 bd4f8f7)
declare -A cfgs
for rev in "${revs[@]}"; do
  cfgs[$rev]=$(nix build "git+file://$PWD?rev=$rev#kh-view" --no-link --print-out-paths)
done

# per-revision body mirrors pipeline.md (probe + IPC + settle per Timing table)
for rev in "${revs[@]}"; do
  "$qs" -p "${cfgs[$rev]}" >/dev/null 2>&1 &
  QPID=$!
  sleep 0.5
  "$grim" "$run/$rev.png"
  kill -9 "$QPID" 2>/dev/null || true; wait "$QPID" 2>/dev/null || true
done
```

Open the gallery per [kh-view.md § Display](kh-view.md#display-only-when-the-user-asks),
sourcing each pane's label/desc from `git log --format='%h %s' -1 <rev>`.
