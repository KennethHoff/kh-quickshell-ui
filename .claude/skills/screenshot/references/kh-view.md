# kh-view: labelled view and display

`kh-view` is the image gallery used to show screenshots to the user. It
accepts file **or directory** paths (dirs expand to image files). Use
`--label <file> <label> <desc>` to label each pane.

## Labelled view

Each `--label` consumes three arguments: `<file>`, `<label>`, `<description>`.
Bare paths (no `--label`) show no header. Directories passed with `--label`
apply the same label/description to every image file found.

```bash
nix run .#kh-view -- \
  --label /path/to/file1 "Label 1" "Description 1" \
  --label /path/to/file2 "Label 2" "Description 2" &
```

## Display (only when the user asks)

By default, after capture, print the file paths back to the user. Do not
open `kh-view` unless the user explicitly asks to see the shots — the paths
alone are enough for the user to inspect them on their own.

When — and only when — the user explicitly asks to view the screenshots
(e.g. "show me", "open it", "view the results"), open them in `kh-view`
using the pinned known-good commit with the `--label` wrapper flag.
**Always label screenshots** — the label and description should describe
what each shot shows, not just the app name.

```bash
nix run "git+file://$PWD?rev=239edbdd4c661f572aee55d8a3bad4f87d264b04#kh-view" -- \
  --label "$path1" "Closed state"   "Bar with no popups open"  \
  --label "$path2" "Dropdown open"  "Volume plugin expanded"   \
  --label "$path3" "Search results" "Launcher with query typed" &
```

Update the pinned commit when kh-view reaches a new stable state.
