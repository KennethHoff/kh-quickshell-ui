# kh-view IPC reference

Target name: `viewer`

All keyboard actions are reachable via IPC. The canonical client is
`quickshell ipc --pid <pid>`.

---

## Properties (read-only)

| Property       | Type   | Description                                      |
|----------------|--------|--------------------------------------------------|
| `currentIndex` | int    | Index of the currently focused pane (0-based)    |
| `count`        | int    | Total number of loaded files                     |
| `fullscreen`   | bool   | Whether fullscreen mode is active                |
| `wrap`         | bool   | Whether navigation wraps around at the ends      |
| `hasPrev`      | bool   | `true` if `currentIndex > 0` or `wrap` is set   |
| `hasNext`      | bool   | `true` if `currentIndex < count - 1` or `wrap`  |

```bash
qs ipc --pid $PID prop get view currentIndex
qs ipc --pid $PID prop get view hasNext
```

---

## Functions

### Navigation

| Function   | Description                                                          |
|------------|----------------------------------------------------------------------|
| `next()`   | Advance to the next file; wraps to start if `wrap` is set            |
| `prev()`   | Go back to the previous file; wraps to end if `wrap` is set          |
| `seek(n)`  | Jump to file at index `n` (clamped to valid range; ignores `wrap`)   |

```bash
qs ipc --pid $PID call view next
qs ipc --pid $PID call view prev
qs ipc --pid $PID call view seek 2
```

### View

| Function              | Description                              |
|-----------------------|------------------------------------------|
| `setFullscreen(bool)` | Enter or exit fullscreen mode            |
| `setWrap(bool)`       | Enable or disable wrap-around navigation |
| `key(k)`              | Send a key by name (see table below)     |

```bash
qs ipc --pid $PID call view setFullscreen true
qs ipc --pid $PID call view setWrap true
qs ipc --pid $PID call view key f        # toggle fullscreen
qs ipc --pid $PID call view key h        # prev in fullscreen
qs ipc --pid $PID call view key l        # next in fullscreen
```

Supported key names for `key()`: `f`, `h`, `l`, `left`, `right`, `tab`,
`q`, `escape`.

### Lifecycle

| Function | Description    |
|----------|----------------|
| `quit()` | Close kh-view  |

```bash
qs ipc --pid $PID call view quit
```

---

## Launching and finding the PID

```bash
nix run .#kh-view -- file1.png file2.png file3.png &
KV_PID=$!

# Poll until ready
for i in $(seq 50); do
    sleep 0.2
    qs ipc --pid $KV_PID prop get view count >/dev/null 2>&1 && break
done
```

---

## Example: scripted slideshow

Step through all files at a fixed interval, then quit.

```bash
qs ipc --pid $KV_PID call view setFullscreen true

while true; do
    sleep 5
    if [[ "$(qs ipc --pid $KV_PID prop get view hasNext)" == "false" ]]; then
        qs ipc --pid $KV_PID call view quit
        break
    fi
    qs ipc --pid $KV_PID call view next
done

wait $KV_PID
```
