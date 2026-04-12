---
name: quickshell-ipc
description: Add or call Quickshell IPC handlers using IpcHandler from Quickshell.Io and the `qs ipc` CLI.
allowed-tools: WebFetch
---

Quickshell IPC lets you expose QML functions to the outside world via the `qs ipc` command-line interface.

## QML side — IpcHandler

```qml
import Quickshell.Io

IpcHandler {
    target: "myTarget"   // unique name; used in CLI calls
    enabled: true        // default; can disable at runtime

    function doSomething(name: string): void { /* ... */ }
    function getValue(): bool { return someProperty }
}
```

Docs: `https://quickshell.org/docs/v0.2.1/types/Quickshell.Io/IpcHandler`

### Rules for handler functions

- All argument and return types **must be explicit**
- Max **10 arguments**
- Allowed argument types: `string`, `int`, `bool`, `real`, `color`
- Allowed return types: `void`, `string`, `int`, `bool`, `real`, `color`
- `color` accepts named colors or hex strings (with or without `#`)
- `bool` accepts `"true"`, `"false"`, or integers (`0` = false)

## CLI side — `qs ipc`

```bash
# List all registered targets
qs ipc show targets

# List functions on a target
qs ipc show target <target>

# Call a function (no args)
qs ipc call <target> <function>

# Call a function with args
qs ipc call <target> <function> <arg1> <arg2> ...

# Read an IPC-compatible property
qs ipc prop get <target> <property>
```

## Example

```qml
IpcHandler {
    target: "media"
    function togglePlaying(): void { Mpris.players[0].togglePlaying() }
    function isPlaying(): bool { return Mpris.players[0].isPlaying }
}
```

```bash
qs ipc call media togglePlaying
qs ipc call media isPlaying
# → true
```

## Tips

- `target` must be unique across the entire shell — use a descriptive name like `"launcher"` or `"bar"`.
- `enabled` can be toggled at runtime to temporarily disable a handler without removing it.
- To look up additional `Quickshell.Io` types (Socket, Process, etc.), use the `quickshell-docs` skill.
