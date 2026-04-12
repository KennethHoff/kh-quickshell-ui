# ADR 001: Component Architecture for Quickshell UI Modules

**Status:** Accepted  
**Date:** 2026-04-12

---

## Context

`kh-cliphist.qml` grew into a ~1600-line monolith with state, UI, key handling,
IPC, and processes all interleaved. The same pattern would repeat for every new
module (launcher, emoji picker, etc.), producing a pile of independently
unmaintainable files with no shared foundations.

The clipboard viewer also revealed two distinct interaction surfaces — a list
view (search, navigation, visual range selection) and a preview view (text
display, cursor, char/line/block visual selection, fullscreen) — whose concerns
are currently tangled throughout the file.

The goal is an architecture that:
- Separates list and preview concerns into testable, replaceable components
- Provides reusable building blocks that future modules can share
- Keeps the orchestration layer thin and legible

---

## Decision

### File structure

```
qml/
  kh-cliphist.qml          orchestrator: window, IPC, layout, fullscreen, paste/yank
  ClipList.qml             list view, search, list-level visual mode, entry loading
  ClipPreview.qml          detail side panel (thin wrapper around TextViewer)

lib/
  TextViewer.qml           reusable text/image viewer with vim nav and visual selection
  HelpOverlay.qml          reusable searchable keybind popup
  (existing utilities unchanged)
```

### Component responsibilities

#### `TextViewer.qml` (lib — reusable)

Generic text/image viewer with no clipboard or window awareness.

- Flickable text or image display
- Persistent cursor bar
- Char / line / block visual selection with all helpers
  (`_logicalLineAt`, `_lineStartAt`, `_lineEndAt`, `_lineCount`,
  `_scrollEditIntoView`, `_applyLineSelection`, `_enterTextVisual`,
  `_handleTextVisualKey`)
- `hjkl` cursor movement, column preserved across `j`/`k`
- `handleKey(event) → bool`

**Properties in:** `text`, `isImage`, `imageSource`, `imageSize`, `focused`, `loading`  
**Properties out:** `hintText`, `modeText` ("CHR"/"LIN"/"BLK"/"")  
**Signals:** `yankTextRequested(string text)`, `fullscreenRequested()`

#### `HelpOverlay.qml` (lib — reusable)

Generic searchable keybind popup. Callers supply binding data; the component
handles rendering, filtering, and navigation.

- Properties: `showing`, `sections: [{title, bindings: [{key, desc}]}]`
- Built-in `/` filter, `j`/`k`/`g`/`G`/`Ctrl+D`/`U` navigation
- Shrinks to fit filtered matches
- `handleKey(event) → bool`

#### `ClipPreview.qml` (qml — cliphist-specific)

Thin shell around `TextViewer`. Owns decoding and metadata; has no visual
selection logic of its own.

- `detailDecodeProcess`, `detailSizeProcess`, `detailRefreshTimer`
- Header row (TEXT/IMAGE badge + entry preview text)
- Stats bar (char/word/line counts; image dimensions and file size)
- Contains one `TextViewer` instance
- `handleKey(event) → bool`, `handleIpcKey(k) → bool`

**Properties in:** `entry` (raw cliphist line), `focused`  
**Properties out:** `text`, `isImage`, `imageSource`, `hintText`, `modeText`  
**Signals:** `exitFocus()`, `fullscreenRequested()`, `yankEntryRequested(string rawLine)`

#### `ClipList.qml` (qml — cliphist-specific)

Self-contained list view with all search and navigation logic.

- `allEntries`, `filteredEntries`, `_processed`, `_processedIdx`
- `listProcess`, `fullTextDecodeProcess`
- `searchDebounce`, `gTimer`
- `_runFilter()`, `navUp/Down/Top/Bottom/HalfUp/Down()`
- Search field, mode tag, `ListView` with delegates (thumbnails, flash animation)
- Insert / normal / list-visual modes
- `handleKey(event) → bool`, `handleIpcKey(k) → bool`
- `reset()`, `typeText(string)`, `nav(string)`

**Properties out:** `selectedEntry`, `hintText`, `modeText` ("NOR"/"VIS")  
**Signals:** `openDetail()`, `fullscreenRequested()`, `closeRequested()`,
`yankEntryRequested(string rawLine)`

#### `kh-cliphist.qml` (orchestrator)

Owns the window and wires everything together. Contains no list or preview logic.

- `showing`, `detailFocused`, `fullscreenShowing`
- Global paste/yank processes and `closeTimer` (reused by future modules)
- `IpcHandler` → `list.handleIpcKey(k)` and `preview.handleIpcKey(k)`
- Panel layout: `ClipList` (40 %) + `ClipPreview` (60 %)
- Fullscreen overlay: a `TextViewer` anchored to the full panel at z=5,
  fed `preview.text` / `preview.isImage`; `visible: fullscreenShowing`
- `HelpOverlay` with cliphist-specific binding data
- Key dispatch priority: help → fullscreen TextViewer → preview → list
- Footer reading `hintText` from whichever component is currently active

### Key routing

```
Keys.onPressed:
  if helpOverlay.showing      → helpOverlay.handleKey(event)
  else if fullscreenShowing   → fullscreenTextViewer.handleKey(event)
  else if detailFocused       → preview.handleKey(event)
  else                        → list.handleKey(event)
```

### Fullscreen as an orchestrator concern

Fullscreen is not owned by `ClipPreview`; it is a panel-level overlay managed
by the orchestrator. This means:

- Any future module (list, launcher, etc.) can trigger fullscreen via a signal
  without knowing how it is implemented
- The fullscreen `TextViewer` is a separate instance from the detail panel
  `TextViewer`; entering fullscreen resets visual selection state (acceptable —
  the user re-enters visual mode in the fullscreen context)
- Layout: `ClipList` and `ClipPreview` are positioned normally; the fullscreen
  `Rectangle` sits above them at z=5 with `anchors.fill: panel`

### Paste/yank as an orchestrator concern

`yankEntryRequested(rawLine)` and `yankTextRequested(text)` signals bubble up
to the orchestrator, which runs the appropriate process and triggers `closeTimer`.
Future modules (emoji picker, launcher) emit the same signals to the same handler.

### `HelpOverlay` generalisation

The current help popup is cliphist-specific only in its *data* (the binding
list). The rendering, filtering, and navigation are generic. Callers pass
`sections` as a property; the component is otherwise fully self-contained.
Future modules supply their own `sections` array.

---

## Consequences

**Positive**
- `kh-cliphist.qml` shrinks from ~1600 lines to ~150 lines
- `TextViewer` and `HelpOverlay` are available to every future module at zero
  marginal cost
- Visual selection logic lives in exactly one place
- Key routing is a single readable dispatch chain, not a nested if/else tree
- Paste/yank is wired once; future modules get it for free

**Negative / trade-offs**
- Entering fullscreen resets visual selection state (previous behaviour
  preserved it, but the added complexity was not worth it)
- The flake `cliphistConfig` derivation needs two extra `cp` lines for
  `ClipList.qml` and `ClipPreview.qml` (trivial change)
- `lib/` gains two new components (`TextViewer`, `HelpOverlay`) that are not
  yet used by any module other than cliphist; they will earn their keep when
  the next module is built

---

## Implementation order

1. `TextViewer.qml` — extract from current detail+fullscreen code; write tests
2. `HelpOverlay.qml` — extract from current help popup
3. `ClipPreview.qml` — thin wrapper; replaces detailPanel subtree
4. `ClipList.qml` — extract list subtree and all list state
5. `kh-cliphist.qml` — reduce to orchestrator; update flake `cp` lines
