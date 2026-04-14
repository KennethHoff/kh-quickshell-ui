---
name: event-handler-delegation
description: How event handlers and IPC handlers work in this codebase — all logic lives in a functionality.* object; handlers are pure single-line delegations. Read this before adding any handler or behavioral logic to a QML component.
---

Every component in this codebase follows a strict convention: **all behavioral logic lives inside a `QtObject { id: functionality }`, and every event handler delegates to it exclusively — no inline logic anywhere.**

## Rule

```
event handler → functionality.X()   (no logic in the handler itself)
IPC handler   → functionality.X()   (same function, same path)
```

## Structure

```qml
SomeComponent {
    id: root

    QtObject {
        id: functionality

        // ui+ipc
        function toggle(): void { root.showing = !root.showing }
        // ipc only
        function open(): void   { root.showing = true }
        // ui only
        function handleKeyEvent(event): bool {
            // logic lives here
        }
    }

    IpcHandler {
        target: "my-target"
        function toggle(): void { functionality.toggle() }
        function open(): void   { functionality.open() }
    }

    MouseArea {
        onClicked: functionality.toggle()           // ← no inline logic
    }

    Keys.onPressed: (event) => {
        if (functionality.handleKeyEvent(event)) event.accepted = true
    }
}
```

## Caller annotations

Every function inside `functionality` carries a comment on the line above it:

| Comment | Meaning |
|---|---|
| `// ui+ipc` | Called by both a UI event handler and an IPC handler |
| `// ui only` | Only called from UI handlers (keyboard, mouse, signals) |
| `// ipc only` | Only called from IPC handlers |

These annotations make the call graph immediately visible without tracing cross-file references.

## Keyboard events

For keyboard dispatchers, `handleKeyEvent` is `void` and sets `event.accepted` internally. The call site is a pure single delegation with no inline conditional:

```qml
// ui only
function handleKeyEvent(event): void {
    if (event.key === Qt.Key_Shift || ...) return   // ignore modifiers
    if (event.text === "q") { close(); event.accepted = true; return }
    // ... routing logic
}
```

Handler at the call site:

```qml
Keys.onPressed: (event) => functionality.handleKeyEvent(event)
```

IPC string-key entry points are separate:

```qml
// ipc only
function key(k: string): void {
    const lk = k.toLowerCase()
    if (lk === "q") close()
    // ...
}
```

## Window lifecycle

`onVisibleChanged` delegates to `functionality.onVisibleChanged()`, which contains the conditional:

```qml
// ui only
function onVisibleChanged(): void { if (root.showing) onShow() }
// ui only
function onShow(): void { list.reset(); list.load(); /* ... */ }
```

Call site:

```qml
WlrLayershell {
    onVisibleChanged: functionality.onVisibleChanged()
}
```

## Sub-components (AppList, ClipList)

Sub-components that don't expose IPC still use a `functionality` QtObject for internal handlers — search field text events, Escape/Return, Ctrl+* emacs bindings, and ListView `onCountChanged`:

```qml
QtObject {
    id: functionality

    // ui only
    function onSearchTextChanged(): void { list.currentIndex = 0; searchDebounce.restart() }
    // ui only
    function searchEscape(): void        { clipList._mode = "normal"; clipList.searchEscapePressed() }
    // ui only
    function handleSearchCtrlKey(event): bool { /* Ctrl+A/E/F/B/D/K/W/U */ }
    // ui only
    function clampListIndex(): void      { if (list.count > 0 && list.currentIndex < 0) list.currentIndex = 0 }
}

TextInput {
    id: searchField
    onTextChanged:        functionality.onSearchTextChanged()
    Keys.onEscapePressed: functionality.searchEscape()
    Keys.onPressed: (event) => { if (functionality.handleSearchCtrlKey(event)) event.accepted = true }
}

ListView {
    id: list
    onCountChanged: functionality.clampListIndex()
}
```

## Delegate items (Tray)

Inline Repeater delegates define `functionality` inside the delegate scope. Since each delegate instance is a separate object, there is no ID conflict:

```qml
delegate: Item {
    id: trayItem

    QtObject {
        id: functionality
        // ui only
        function click(mouse, mouseArea): void { /* routing */ }
    }

    MouseArea {
        id: trayMouseArea
        onClicked: mouse => functionality.click(mouse, trayMouseArea)
    }
}
```

## What counts as "inline logic"

These are violations — **do not write them in handlers**:

```qml
// ✗ property assignment
onClicked: root.showing = false

// ✗ conditional
onVisibleChanged: { if (visible) doSomething() }

// ✗ multi-step sequence
onTriggered: { list.reset(); list.load(); normalModeHandler.forceActiveFocus() }
```

These are correct:

```qml
// ✓ single delegation
onClicked: functionality.close()

// ✓ single delegation (conditional is inside functionality)
onVisibleChanged: functionality.onVisibleChanged()

// ✓ single delegation — handleKeyEvent is void and sets event.accepted internally
Keys.onPressed: (event) => functionality.handleKeyEvent(event)
```

## Why

- Future developers see immediately that `functionality` is *the* place to look for what a component does.
- IPC and UI always exercise the same code path — no divergence possible.
- Caller annotations (`// ui+ipc`, `// ui only`, `// ipc only`) make the call graph readable without cross-file tracing.
- Logic is testable/readable in one place rather than scattered across nested handlers.
