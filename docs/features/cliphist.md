# Clipboard History

Standalone Quickshell daemon (`quickshell -c kh-cliphist`) with a searchable
list of clipboard entries from `cliphist`. SUPER+V toggles it via IPC.

## Core

- [1] ✅ Searchable list — text pre-decoded for full-content match
- [2] ✅ Text entries inline; image entries as thumbnails
- [3] ✅ Enter copies via `cliphist decode | wl-copy`; row flashes
- [4] ✅ Search filters — `img:`/`text:` type, `'` exact substring
- [5] ✅ Entry counter in footer
- [6] ✅ Fast search — pre-processed haystacks, 80 ms debounce
- [7] ✅ IPC — `toggle`, `setMode`, `nav`, `key`, `type`

## Navigation

- [1] ✅ Modal insert/normal — opens normal; `j`/`k`, `/` → insert
- [2] ✅ `gg`/`G`, `Ctrl+D`/`Ctrl+U` half-page scroll
- [3] ✅ Emacs bindings in insert mode (`Ctrl+A/E/F/B/D/K/W/U`)

## Detail Panel

- [1] ✅ Always-visible 40/60 side pane; 120 ms debounce
- [2] ✅ Char/word/line count for text entries
- [3] ✅ Dimensions and file size for image entries
- [4] ✅ `Tab`/`l` enters; `Tab`/`Esc` returns
- [5] ✅ Cursor motions — `hjkl`/`w`/`b`/`e`/`W`/`B`/`E`, `0`/`$`/`^`
- [6] ✅ Visual select — `v`/`V`/`Ctrl+V`; `o`/`O` swap; `y` copies
- [7] ⬜ Insert mode — edit text inline; vim operators (`ciw`, `dw`)

## Fullscreen View

- [1] ✅ `Enter` from detail opens; `Escape` returns
- [2] ✅ Cursor + line motions; `gg`/`G`/`Ctrl+D`/`U`
- [3] ✅ Visual select — same as detail panel
- [4] ⬜ Insert mode — same as detail panel insert mode

## Help

- [1] ✅ `?` opens popup with all bindings; `/` filters inline
- [2] ⬜ Context-aware help — highlight section for current mode

## Entry Management

- [1] ✅ Delete single — `d` in normal; confirmation popup
- [2] ✅ Delete range in visual mode — `d` with confirmation
- [3] ✅ Fade-out animation on delete
- [4] ✅ Pin toggle — `p` on selected entry
- [5] ✅ Pinned entries sort to top (filtered or not)
- [6] ✅ Pin persistence — `$XDG_DATA_HOME/kh-cliphist/pins`
- [7] ✅ Pin visual indicator — coloured bar on left edge
- [8] ⬜ Batch pin in visual mode — `p` on selected range

## Metadata

- [1] ✅ First-seen timestamp shown right-aligned ("just now"…); persisted
- [2] ⬜ Source app attribution — see [Notes](#notes) below

## Integration

- [1] ⬜ Auto-paste — close window, simulate Ctrl+V via `wtype`

## Notes

**Source app attribution** *(Metadata [2])* — record the active Hyprland
window at copy time and show it on each row. Attempted via `wl-paste --watch`
+ `hyprctl activewindow`, but accuracy is poor: copying from within the
overlay always reports the last regular window, and every copy-from-overlay
creates a mis-attributed entry. Needs a Hyprland plugin/event hook or a
Wayland protocol exposing the source client of clipboard changes.
