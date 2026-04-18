# File Viewer (`kh-view`)

Pass files as arguments via the Nix module or directly:

```bash
nix run .#kh-view -- /path/to/file.png /path/to/other.jpg
```

## IPC

| Target | Functions / Properties |
|---|---|
| `view` | `quit()`, `next()`, `prev()`, `seek(n)`, `setFullscreen(on)`, `setWrap(on)`, `key(k)` |
| | **Props:** `currentIndex` -> int, `count` -> int, `fullscreen` -> bool, `wrap` -> bool, `hasPrev` -> bool, `hasNext` -> bool |

```bash
qs ipc -c kh-view call view next
qs ipc -c kh-view call view setFullscreen true
qs ipc -c kh-view prop get view currentIndex
```
