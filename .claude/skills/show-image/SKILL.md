---
name: show-image
description: Display one or more image files (PNG/JPEG/etc.) to the user via the `kh-view` image gallery, with labelled panes. Use whenever the user asks to see images already on disk — design mockups, plots, downloaded assets, gallery files, etc. Triggers include "show me", "open it", "view that", "open the gallery". Do not invoke just because images exist; only on an explicit display request.
allowed-tools: Bash, Read
---

# Show image skill

`kh-view` is the image gallery used to show images to the user. It
accepts file **or directory** paths (dirs expand to image files). Use
`--label <file> <label> <desc>` to label each pane.

## When to invoke

Only invoke on an explicit display request from the user — "show me",
"open it", "view that", "open the gallery". When the user just wants
file paths, the default is to print the paths and stop; do not
auto-open.

## Labelled view

Each `--label` consumes three arguments: `<file>`, `<label>`, `<description>`.
Bare paths (no `--label`) show no header. Directories passed with `--label`
apply the same label/description to every image file found.

```bash
nix run .#kh-view -- \
  --label /path/to/file1 "Label 1" "Description 1" \
  --label /path/to/file2 "Label 2" "Description 2" &
```

## Display

Open the images in `kh-view` using the pinned known-good commit with
the `--label` wrapper flag. **Always label images** — the label and
description should describe what each image shows, not just the
filename.

```bash
nix run "git+file://$PWD?rev=239edbdd4c661f572aee55d8a3bad4f87d264b04#kh-view" -- \
  --label "$path1" "Variant A" "First option"  \
  --label "$path2" "Variant B" "Second option" \
  --label "$path3" "Variant C" "Third option"  &
```

Update the pinned commit when kh-view reaches a new stable state.
