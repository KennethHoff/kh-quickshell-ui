# kh-bar screenshots

The dev bar uses ipcPrefix `devbar`. The root target (`devbar`) exposes
two queries that make cropping and settling-detection precise:

| Call | Returns |
|---|---|
| `devbar getHeight` | Visible bar footprint in px — bar height plus the tallest currently-open dropdown popup. |
| `devbar getWidth` | Bar width in px — follows the screen (the bar anchors left+right). |

Plugins sit under `devbar.<plugin>` (e.g. `devbar.volume`). Groups/dropdowns
sit under `devbar.<ipcName>` and expose `toggle`/`open`/`close`/`isOpen`
(e.g. `devbar.controlcenter open`).

## Dynamic crop

Always prefer sizing the crop from the live IPC — no guessing, no wasted
pixels, and the shot resizes automatically when popups open or close.

```bash
h=$("$qs" ipc --pid "$QPID" call devbar getHeight)
w=$("$qs" ipc --pid "$QPID" call devbar getWidth)
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
  cur=$("$qs" ipc --pid "$QPID" call devbar getHeight)
  [[ "$cur" == "$prev" && -n "$cur" ]] && break
  prev=$cur; sleep 0.1
done
```

## Readiness probe

Use `devbar getHeight` as the startup readiness probe too — it's a safe
query with no side effects and it returns as soon as the bar's IPC is up.

```bash
for i in $(seq 80); do
  sleep 0.1
  "$qs" ipc --pid "$QPID" call devbar getHeight >/dev/null 2>&1 && break
done
```
