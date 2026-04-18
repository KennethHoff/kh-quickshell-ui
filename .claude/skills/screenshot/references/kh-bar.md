# kh-bar screenshots

The dev bar uses ipcPrefix `dev-bar`. The root target (`dev-bar`) exposes
two queries that make cropping and settling-detection precise:

| Call | Returns |
|---|---|
| `dev-bar getHeight` | Visible bar footprint in px — bar height plus the tallest currently-open dropdown popup. |
| `dev-bar getWidth` | Bar width in px — follows the screen (the bar anchors left+right). |

Plugins sit under `dev-bar.<plugin>` (e.g. `dev-bar.volume`). Groups/dropdowns
sit under `dev-bar.<ipcName>` and expose `toggle`/`open`/`close`/`isOpen`
(e.g. `dev-bar.controlcenter open`).

## Dynamic crop

Always prefer sizing the crop from the live IPC — no guessing, no wasted
pixels, and the shot resizes automatically when popups open or close.

```bash
h=$("$qs" ipc --pid "$QPID" call dev-bar getHeight)
w=$("$qs" ipc --pid "$QPID" call dev-bar getWidth)
"$grim" -g "0,0 ${w}x${h}" "$out"
```

Re-read between shots — `getHeight` changes with dropdown state.

## Settling via getHeight (better than a fixed sleep)

`getHeight` reflects the rendered popup's `implicitHeight`, so a stable
value for two consecutive reads means the popup has committed. Poll it
instead of guessing a sleep duration:

```bash
prev=""; cur=""
for _ in $(seq 30); do
  cur=$("$qs" ipc --pid "$QPID" call dev-bar getHeight)
  [[ "$cur" == "$prev" && -n "$cur" ]] && break
  prev=$cur; sleep 0.1
done
```

## Readiness probe

Use `dev-bar getHeight` as the startup readiness probe too — it's a safe
query with no side effects and it returns as soon as the bar's IPC is up.

```bash
for i in $(seq 80); do
  sleep 0.1
  "$qs" ipc --pid "$QPID" call dev-bar getHeight >/dev/null 2>&1 && break
done
```
