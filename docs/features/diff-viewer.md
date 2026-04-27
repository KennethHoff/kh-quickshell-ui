# Diff Viewer

Side-by-side two-pane file diff. `kh-diff file1 file2` or pipe from `git
diff` / `diff`. Keyboard-driven; vim motion navigation. Natural sibling
to [File Viewer](view.md).

## Core

- [1] ⬜ Two-pane diff with added/removed/changed line highlighting
- [2] ⬜ Pipe input — `git diff | kh-diff` reads unified diff from stdin
- [3] ⬜ IPC — same pattern as File Viewer

## Navigation

- [1] ⬜ `]c`/`[c` jump to next/previous change hunk
- [2] ⬜ `Tab` cycles panes; `hjkl` scroll; `gg`/`G`/`Ctrl+D`/`U`
- [3] ⬜ `y` copies selected hunk or visual selection
