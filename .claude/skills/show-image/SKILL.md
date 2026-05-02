---
name: show-image
description: Display one or more image files (PNG/JPEG/etc.) to the user via the `kh-view` image gallery, with labelled panes. Use whenever the user asks to see images already on disk — screenshots, design mockups, plots, downloaded assets, gallery files, etc. Triggers include "show me", "open it", "view that", "open the gallery". Do not invoke just because images exist; only on an explicit display request. Pairs with the `screenshot` skill (capture → show), but works for any image file.
allowed-tools: Bash, Read
---

# Show image skill

`kh-view` is the image gallery used to show images to the user. It
accepts file **or directory** paths (dirs expand to image files). Use
`--label <file> <label> <desc>` to label each pane.

## When to invoke

Only invoke on an explicit display request from the user — "show me",
"open it", "view that", "open the gallery". When the user just wants
file paths (e.g. screenshots captured via the `screenshot` skill), the
default is to print the paths and stop; do not auto-open.

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
  --label "$path1" "Closed state"   "Bar with no popups open"  \
  --label "$path2" "Dropdown open"  "Volume plugin expanded"   \
  --label "$path3" "Search results" "Launcher with query typed" &
```

Update the pinned commit when kh-view reaches a new stable state.

## Sourcing labels for revision comparisons

When showing screenshots produced by the `screenshot` skill's
revision-comparison flow, source each pane's label/desc from
`git log --format='%h %s' -1 <rev>` so the gallery shows the commit
hash and subject for each revision.

## Live view of the headless VM

If the user wants to *watch* the test VM render in real time (rather
than view static screenshots), run `nix run .#kh-headless-view`
instead. It opens an auto-refreshing feh window backed by a 5 fps grim
loop inside the VM that writes to `/tmp/kh-headless/state/live.png`.

Requires the headless daemon to be running (`nix run
.#kh-headless-daemon`). The window stays black until something is
loaded into the VM (`nix run .#kh-headless -- load <config>`); idle
Hyprland with no clients is genuinely empty.

This is for *watching* the VM. To grab one-off shots from it, use the
`screenshot` skill; to display already-captured PNGs, keep using the
labelled `kh-view` flow above.
