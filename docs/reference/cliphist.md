# Clipboard History (`kh-cliphist`)

## IPC

| Target | Functions / Properties |
|---|---|
| `cliphist` | `toggle()`, `open()`, `close()`, `setMode(m)`, `setView(v)`, `nav(dir)`, `key(k)`, `type(text)` |
| | **Props:** `showing` -> bool, `mode` -> string |

```bash
qs ipc -c kh-cliphist call cliphist toggle
qs ipc -c kh-cliphist call cliphist nav down
```
