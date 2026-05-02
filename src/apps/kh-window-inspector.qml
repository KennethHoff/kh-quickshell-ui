// Window inspector — pick-first overlay over open windows.
//
// Daemon: quickshell -p <config-dir>
// Toggle: quickshell ipc -c kh-window-inspector call window-inspector toggle
//
// This file owns: window, IPC, key dispatch, cursor polling, hit-testing.
// Visual layers (outline, tag) live in window-inspector/*.qml.
//
// Pick mode is the default: an empty input region lets the cursor pass
// through to the underlying windows; we poll `hyprctl cursorpos`, find
// the topmost window under the cursor, and render an outline + tag.
// `f` freezes the picked window so it survives focus loss.
//
// Top-level keybinds are intentionally minimal — only `Esc`/`q` (close)
// and `f` (freeze toggle). Window actions (close/focus/float/pin/move-
// to-workspace), copy-as-rule, and copy-as-JSON will live in a future
// "details" panel attached to the picked window, not at the top level.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "./lib"

ShellRoot {
    id: root

    NixConfig { id: cfg }
    NixBins   { id: bin }

    // ── State ─────────────────────────────────────────────────────────────────
    property bool   showing:    false
    // "pick" (default) | "frozen" — list mode is deferred to a follow-up.
    property string mode:       "pick"
    // The currently picked window's address (empty when none).
    property string pickedAddr: ""
    // The picked window's full ipc record. Stored as an explicit state
    // property because `HyprlandToplevel.lastIpcObject` is updated lazily
    // and Quickshell does not always notify QML bindings when its contents
    // change — re-evaluating bindings off `pickedAddr` alone misses
    // post-refresh updates.
    property var    pickedIpc:  null
    // Frozen address — separate so unfreezing returns to live picking.
    property string frozenAddr: ""
    property var    frozenIpc:  null
    // Cursor position in global Hyprland coords.
    property int    cursorX:    0
    property int    cursorY:    0

    // ── Hyprland event subscription — keep toplevel data live ────────────────
    Connections {
        target: Hyprland
        function onRawEvent(ev) { functionality.onHyprlandEvent(ev) }
    }

    // ── Cursor polling ───────────────────────────────────────────────────────
    Process {
        id: cursorProc
        command: [bin.hyprctl, "cursorpos"]
        stdout: SplitParser {
            onRead: (line) => functionality.onCursorRead(line)
        }
    }
    Timer {
        id: cursorTimer
        interval: 50
        repeat: true
        running: root.showing && root.mode === "pick"
        onTriggered: functionality.pollCursor()
    }

    // ── Active-window probe (used by inspectActive) ──────────────────────────
    // Pipe through `tr -d '\n'` so the JSON arrives as a single line — keeps
    // SplitParser straightforward. Quickshell's `Hyprland.activeWindow` is
    // null while a layer surface holds keyboard focus (Hyprland's "active"
    // tracks toplevels, not layer surfaces), so we ask hyprctl directly.
    property string _activeBuf: ""
    Process {
        id: activeProc
        command: [bin.bash, "-c", bin.hyprctl + " activewindow -j | tr -d '\\n'"]
        stdout: SplitParser {
            onRead: (line) => functionality.onActiveRead(line)
        }
        onExited: functionality.onActiveExited()
    }

    // ── Functionality ────────────────────────────────────────────────────────
    QtObject {
        id: functionality

        // ── Lifecycle ─────────────────────────────────────────────────────────
        // ui+ipc
        function toggle(): void { root.showing = !root.showing }
        // ipc only
        function open(): void   { root.showing = true }
        // ui+ipc
        function close(): void  { root.showing = false }
        // ui only
        function onShow(): void {
            root.mode = "pick"
            root.frozenAddr = ""
            root.frozenIpc  = null
            keyHandler.forceActiveFocus()
            Hyprland.refreshToplevels()
            pollCursor()
        }
        // ui only
        function onVisibleChanged(): void { if (root.showing) onShow() }

        // ── Cursor + hit-testing ──────────────────────────────────────────────
        // ui only
        function pollCursor(): void { cursorProc.running = true }
        // ui only
        // Output is "X, Y" (comma + space). Parse and update state, then
        // recompute the picked window.
        function onCursorRead(line: string): void {
            const parts = line.split(",")
            if (parts.length < 2) return
            const x = parseInt(parts[0].trim())
            const y = parseInt(parts[1].trim())
            if (isNaN(x) || isNaN(y)) return
            root.cursorX = x
            root.cursorY = y
            recomputePick()
        }
        // ui only
        function recomputePick(): void {
            if (root.mode === "frozen") {
                root.pickedAddr = root.frozenAddr
                root.pickedIpc  = root.frozenIpc
                return
            }
            const hit = pickWindowAt(root.cursorX, root.cursorY)
            root.pickedAddr = hit ? hit.address : ""
            root.pickedIpc  = hit
        }
        // ui only
        // Topmost-visible-window-at-point. Returns the full ipc record (or
        // null). Filter to windows on the cursor's monitor and active
        // workspace; fullscreen wins; then floating beats tiled; ties
        // broken by focusHistoryID (lower = more recent).
        function pickWindowAt(x: int, y: int): var {
            const mon = monitorAt(x, y)
            if (!mon) return null
            const wins = Hyprland.toplevels.values
            const candidates = []
            for (let i = 0; i < wins.length; i++) {
                const w = wins[i]
                const ipc = w.lastIpcObject
                if (!ipc || !ipc.at || !ipc.size) continue
                if (!ipc.workspace || ipc.workspace.id !== (mon.activeWorkspace ? mon.activeWorkspace.id : -999)) continue
                if (!containsPoint(ipc, x, y)) continue
                candidates.push(ipc)
            }
            if (candidates.length === 0) return null
            // Fullscreen window wins.
            for (let j = 0; j < candidates.length; j++)
                if (candidates[j].fullscreen && candidates[j].fullscreen > 0) return candidates[j]
            candidates.sort(function (a, b) {
                const af = a.floating ? 1 : 0, bf = b.floating ? 1 : 0
                if (af !== bf) return bf - af   // floating first
                return (a.focusHistoryID ?? 999) - (b.focusHistoryID ?? 999)
            })
            return candidates[0]
        }
        // ui only
        function containsPoint(ipc, x: int, y: int): bool {
            const wx = ipc.at[0], wy = ipc.at[1]
            const ww = ipc.size[0], wh = ipc.size[1]
            return x >= wx && x < wx + ww && y >= wy && y < wy + wh
        }
        // ui only
        function monitorAt(x: int, y: int): var {
            const mons = Hyprland.monitors.values
            for (let i = 0; i < mons.length; i++) {
                const m = mons[i]
                if (x >= m.x && x < m.x + m.width &&
                    y >= m.y && y < m.y + m.height) return m
            }
            return null
        }

        // ── Picked window helpers ─────────────────────────────────────────────
        // ui only
        function ipcForAddr(addr: string): var {
            if (!addr) return null
            const wins = Hyprland.toplevels.values
            for (let i = 0; i < wins.length; i++)
                if (wins[i].address === addr) return wins[i].lastIpcObject || null
            return null
        }
        // ui only — re-fetch ipc for the current pickedAddr (frozen flow uses
        // this after refreshToplevels lands so the snapshot stays current).
        function refreshPickedIpc(): void {
            if (root.mode === "frozen" && root.frozenAddr) {
                const next = ipcForAddr(root.frozenAddr)
                if (next) {
                    root.frozenIpc = next
                    root.pickedIpc = next
                    root.pickedAddr = root.frozenAddr
                }
            }
        }

        // ── Inspect by selector (IPC entry points) ────────────────────────────
        // ipc only — `Hyprland.activeWindow` reports null while a layer
        // surface holds keyboard focus, so we always go through hyprctl.
        function inspectActive(): void {
            root._activeBuf = ""
            activeProc.running = true
        }
        // ui only
        function onActiveRead(line: string): void { root._activeBuf = line }
        // ui only
        function onActiveExited(): void {
            const buf = root._activeBuf
            root._activeBuf = ""
            if (!buf) return
            try {
                const obj = JSON.parse(buf)
                if (!obj || !obj.address) return
                root.showing    = true
                root.mode       = "frozen"
                root.frozenAddr = obj.address
                root.frozenIpc  = obj
                root.pickedAddr = obj.address
                root.pickedIpc  = obj
            } catch (e) {}
        }
        // ipc only
        function inspectByAddress(addr: string): void {
            root.showing    = true
            root.mode       = "frozen"
            root.frozenAddr = addr
            root.pickedAddr = addr
            root.frozenIpc  = ipcForAddr(addr)
            root.pickedIpc  = root.frozenIpc
            // Lazy: kick off a refresh in case lastIpcObject hasn't been
            // populated yet — refreshPickedIpc fires after the rawEvent burst.
            Hyprland.refreshToplevels()
        }
        // ipc only
        function inspectByPid(pid: int): void {
            const wins = Hyprland.toplevels.values
            for (let i = 0; i < wins.length; i++) {
                const ipc = wins[i].lastIpcObject
                if (ipc && ipc.pid === pid) {
                    root.showing    = true
                    root.mode       = "frozen"
                    root.frozenAddr = wins[i].address
                    root.frozenIpc  = ipc
                    root.pickedAddr = wins[i].address
                    root.pickedIpc  = ipc
                    return
                }
            }
        }

        // ── Mode toggles ──────────────────────────────────────────────────────
        // ui+ipc
        function freeze(): void {
            if (!root.pickedAddr) return
            root.mode       = "frozen"
            root.frozenAddr = root.pickedAddr
            root.frozenIpc  = root.pickedIpc
        }
        // ui+ipc
        function unfreeze(): void {
            root.mode       = "pick"
            root.frozenAddr = ""
            root.frozenIpc  = null
            recomputePick()
        }
        // ui+ipc
        function toggleFreeze(): void { root.mode === "frozen" ? unfreeze() : freeze() }

        // ── Hyprland events — refresh toplevels on relevant ones ──────────────
        // ui only
        function onHyprlandEvent(ev): void {
            const n = ev.name
            if (n === "openwindow"  || n === "closewindow" ||
                n === "windowtitle" || n === "movewindow"  ||
                n === "activewindow"|| n === "changefloatingmode" ||
                n === "fullscreen"  || n === "windowtitlev2" ||
                n === "movewindowv2") {
                Hyprland.refreshToplevels()
                // After the refresh lands, re-snapshot the frozen window's
                // ipc object — Quickshell does not always notify QML when
                // lastIpcObject mutates, so we explicitly re-pull it.
                refreshPickedIpc()
            }
        }

        // ── Key handling (UI) ─────────────────────────────────────────────────
        // ui only
        // Top-level keys are intentionally minimal. Window actions and
        // copy-as-rule will hang off a future details panel rather than
        // crowding the global namespace.
        function handleKeyEvent(event): void {
            if (event.key === Qt.Key_Shift   || event.key === Qt.Key_Control ||
                event.key === Qt.Key_Alt     || event.key === Qt.Key_Meta) return

            if (event.key === Qt.Key_Escape || event.text === "q") {
                close(); event.accepted = true; return
            }
            if (event.text === "f") {
                toggleFreeze(); event.accepted = true; return
            }
        }

        // ── Key handling (IPC) ────────────────────────────────────────────────
        // ipc only
        function key(k: string): void {
            const lk = k.toLowerCase()
            if      (lk === "escape" || lk === "esc" || lk === "q") close()
            else if (lk === "f")                                    toggleFreeze()
        }
        // ipc only
        function setMode(m: string): void {
            if      (m === "pick"   || m === "live")   unfreeze()
            else if (m === "frozen" || m === "freeze") freeze()
        }
    }

    // ── IPC ───────────────────────────────────────────────────────────────────
    IpcHandler {
        target: "window-inspector"

        readonly property bool   showing:       root.showing
        readonly property string mode:          root.mode
        readonly property string pickedAddress: root.pickedAddr

        function toggle(): void                       { functionality.toggle() }
        function open(): void                         { functionality.open() }
        function close(): void                        { functionality.close() }
        function setMode(m: string): void             { functionality.setMode(m) }
        function key(k: string): void                 { functionality.key(k) }
        function freeze(): void                       { functionality.freeze() }
        function unfreeze(): void                     { functionality.unfreeze() }
        function inspectActive(): void                { functionality.inspectActive() }
        function inspectByAddress(addr: string): void { functionality.inspectByAddress(addr) }
        function inspectByPid(pid: int): void         { functionality.inspectByPid(pid) }
    }

    // ── Window ────────────────────────────────────────────────────────────────
    WlrLayershell {
        id: win
        visible: root.showing
        color: "transparent"
        layer: WlrLayer.Overlay
        keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        namespace: "kh-window-inspector"
        anchors { top: true; bottom: true; left: true; right: true }

        // Empty input region — pointer events fall through to underlying
        // windows so the user can hover them. Keyboard focus is unaffected.
        mask: Region {}

        onVisibleChanged: functionality.onVisibleChanged()

        // Key dispatcher — single Item that holds focus while the layer is up.
        Item {
            id: keyHandler
            anchors.fill: parent
            focus: true

            Keys.onPressed: (event) => functionality.handleKeyEvent(event)
        }

        // ── Outline + tag (pick mode visuals) ─────────────────────────────────
        WindowOutline {
            id: outline
            anchors.fill: parent

            ipc: root.pickedIpc
            monitorOf: outline.ipc && outline.ipc.at
                ? functionality.monitorAt(outline.ipc.at[0], outline.ipc.at[1])
                : null
            frozen: root.mode === "frozen"
            outlineColor: cfg.color.base0D
            frozenColor:  cfg.color.base0A
        }

        InspectorTag {
            id: tag
            anchors.fill: parent
            visible: root.showing
            ipc: root.pickedIpc
            // Layer surface coords are local to its output; convert global
            // cursor coords by subtracting the focused monitor's origin.
            cursorX: root.cursorX - (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.x : 0)
            cursorY: root.cursorY - (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.y : 0)
            screenW: win.width
            screenH: win.height
            frozen: root.mode === "frozen"

            bgColor:     cfg.color.base01
            headerBg:    cfg.color.base02
            textColor:   cfg.color.base05
            mutedColor:  cfg.color.base03
            keyColor:    cfg.color.base0D
            warnColor:   cfg.color.base0A
            stableColor: cfg.color.base0B
            fontFamily:  cfg.fontFamily
            fontSize:    cfg.fontSize
        }
    }
}
