# File Viewer

One-shot viewer for arbitrary text or image files. Accepts N file arguments;
shows all files side-by-side with Tab to cycle focus between panes.

## Core

- [1] ✅ `nix run .#kh-view -- <file> [<file2> ...]`
- [2] ✅ Image detection by extension (png/jpg/webp/etc.)
- [3] ✅ N files side-by-side equal-width; Tab cycles focus
- [4] ✅ `q`/`Esc` quits
- [5] ✅ IPC — `target: "view"`; next/prev/seek/quit/setFullscreen/key
- [6] ⬜ Optional pane labels — name + short description per pane *(implement together with [Dev Tooling → screenshot skill labels](dev-tooling.md))*
- [7] ⬜ `--monitor <name|index>` flag; default to active window's monitor
- [8] ⬜ Gallery history — persist sessions; recall via `--recall [N]` so closed windows can be reopened

## Navigation

- [1] ✅ Per-pane motions — `hjkl`/`w`/`b`/`e`, `0`/`$`/`^`, `gg`/`G`/`Ctrl+D`/`U`
- [2] ✅ Per-pane visual select — `v`/`V`/`Ctrl+V`; `y` copies
- [3] ✅ Fullscreen — `f` toggles; `h`/`l` steps through files; dot indicators

## Content

- [1] ⬜ Syntax highlighting — Tree-sitter or `bat` themes
- [2] ⬜ Directory and glob input — `kh-view ./images/` or `./images/*.png`
- [3] ⬜ Image gallery mode — `g` toggles grid view when all panes are images
