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
    property bool   showing:        false
    // "pick" (default) | "frozen" — list mode is deferred to a follow-up.
    property string mode:           "pick"
    // The currently picked window's address (empty when none).
    property string pickedAddr:     ""
    // The picked window's full ipc record. Stored as an explicit state
    // property because `HyprlandToplevel.lastIpcObject` is updated lazily
    // and Quickshell does not always notify QML bindings when its contents
    // change — re-evaluating bindings off `pickedAddr` alone misses
    // post-refresh updates.
    property var    pickedIpc:      null
    // Frozen address — separate so unfreezing returns to live picking.
    property string frozenAddr:     ""
    property var    frozenIpc:      null
    // Details panel — secondary surface where copy / dispatch keys live.
    // Auto-freezes on open so the cursor can move without changing the
    // window under inspection.
    property bool   detailsShowing: false
    // Cursor position in global Hyprland coords.
    property int    cursorX:        0
    property int    cursorY:        0

    // ── Hyprland event subscription — keep toplevel data live ────────────────
    Connections {
        target: Hyprland
        function onRawEvent(ev) { functionality.onHyprlandEvent(ev) }
    }

    // ── Cursor polling ───────────────────────────────────────────────────────
    // A long-running shell loop streams cursorpos lines instead of the
    // QML Timer firing a fresh `hyprctl` Process every tick. The Timer
    // approach paid the QML→Process round-trip and the hyprctl spawn cost
    // on every iteration, which capped the effective rate well below the
    // timer interval and made the outline lag the cursor visibly.
    //
    // Hyprland's socket2 event stream doesn't surface cursor moves, and
    // the layer surface uses an empty input region (so it can't receive
    // pointer events itself), so polling is the only option — but the
    // pace is derived from the focused monitor's refresh rate rather
    // than a hardcoded value. One frame's worth of sleep keeps work
    // bounded to "as fast as the user can see" without burning cycles.
    readonly property real _frameSeconds: {
        const m = Hyprland.focusedMonitor && Hyprland.focusedMonitor.lastIpcObject
        const hz = m && m.refreshRate ? m.refreshRate : 60
        return 1.0 / hz
    }
    Process {
        id: cursorProc
        running: root.showing && root.mode === "pick"
        command: [
            bin.bash, "-c",
            "while :; do " + bin.hyprctl + " cursorpos || exit 0; sleep "
                + root._frameSeconds.toFixed(4) + "; done"
        ]
        stdout: SplitParser {
            onRead: (line) => functionality.onCursorRead(line)
        }
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

    // ── Clipboard ────────────────────────────────────────────────────────────
    Process { id: copyProc }

    QtObject {
        id: impl
        function copyText(text: string): void {
            copyProc.command = [bin.bash, "-c", "printf '%s' \"$1\" | " + bin.wlCopy, "--", text]
            copyProc.running = true
        }
    }

    // ── Functionality ────────────────────────────────────────────────────────
    QtObject {
        id: functionality

        // ── Lifecycle ─────────────────────────────────────────────────────────
        // ui+ipc
        function toggle(): void { root.showing ? close() : open() }
        // ipc only
        function open(): void   { root.showing = true }
        // ui+ipc — also resets mode so the next open starts in live pick.
        function close(): void  {
            root.showing        = false
            root.mode           = "pick"
            root.frozenAddr     = ""
            root.frozenIpc      = null
            root.detailsShowing = false
        }
        // ui only — fires once per layer surface when the layer becomes
        // visible. Refresh is cheap and idempotent across calls. The
        // cursor stream starts on its own via `cursorProc.running`.
        // Refresh monitors so `_frameSeconds` resolves to the real refresh
        // rate before the bash loop's sleep is computed.
        function onShow(): void {
            Hyprland.refreshMonitors()
            Hyprland.refreshToplevels()
        }
        // ui only
        function onVisibleChanged(): void { if (root.showing) onShow() }

        // ── Cursor + hit-testing ──────────────────────────────────────────────
        // ui only
        // Output is "X, Y" (comma + space). Parse, dedup against the last
        // known position so an aggressive poll loop doesn't burn cycles
        // recomputing the pick on identical samples, and update state.
        function onCursorRead(line: string): void {
            const parts = line.split(",")
            if (parts.length < 2) return
            const x = parseInt(parts[0].trim())
            const y = parseInt(parts[1].trim())
            if (isNaN(x) || isNaN(y)) return
            if (x === root.cursorX && y === root.cursorY) return
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

        // ── Details panel ─────────────────────────────────────────────────────
        // ui+ipc — opens the secondary surface where copy / dispatch keys
        // live. Auto-freezes the picked window so the cursor can move
        // freely without changing what the panel is acting on.
        function openDetails(): void {
            if (!root.pickedAddr) return
            if (root.mode !== "frozen") freeze()
            root.detailsShowing = true
        }
        // ui+ipc
        function closeDetails(): void { root.detailsShowing = false }
        // ipc only
        function toggleDetails(): void {
            root.detailsShowing ? closeDetails() : openDetails()
        }

        // ── Copy ──────────────────────────────────────────────────────────────
        // ui only
        // Format a windowrulev2 line for the picked window using the requested
        // matcher field. The action is left as `<action>` so the user fills
        // it in — there's no sensible default, and emitting `float` would
        // surprise people who actually wanted `tile` or `move`.
        function ruleLine(ipc, variant: string): string {
            const cls   = ipc.initialClass || ""
            const ttl   = ipc.initialTitle || ""
            const pid   = ipc.pid !== undefined ? String(ipc.pid) : ""
            const addr  = ipc.address || ""
            const ws    = ipc.workspace ? (ipc.workspace.name || String(ipc.workspace.id)) : ""
            const mon   = ipc.monitor !== undefined ? String(ipc.monitor) : ""
            if (variant === "t") return "windowrulev2 = <action>, initialTitle:^" + escapeRegex(ttl) + "$"
            if (variant === "p") return "windowrulev2 = <action>, pid:" + pid
            if (variant === "a") return "windowrulev2 = <action>, address:" + addr
            if (variant === "w") return "windowrulev2 = <action>, workspace:" + ws
            if (variant === "m") return "windowrulev2 = <action>, monitor:" + mon
            // Default ("c") — initialClass.
            return "windowrulev2 = <action>, initialClass:^" + escapeRegex(cls) + "$"
        }
        // ui only
        function escapeRegex(s: string): string {
            return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
        }
        // ui+ipc
        function copyRule(variant: string): void {
            const ipc = root.pickedIpc
            if (!ipc) return
            impl.copyText(ruleLine(ipc, variant))
        }
        // ui+ipc
        function copyJson(): void {
            const ipc = root.pickedIpc
            if (!ipc) return
            impl.copyText(JSON.stringify(ipc, null, 2))
        }

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
        // Top-level keys (pick/frozen mode) are intentionally minimal:
        // f / Esc / q / Enter. The details panel owns its own keymap so
        // copy-as-rule and dispatch don't crowd the global namespace.
        function handleKeyEvent(event): void {
            if (event.key === Qt.Key_Shift   || event.key === Qt.Key_Control ||
                event.key === Qt.Key_Alt     || event.key === Qt.Key_Meta) return

            if (root.detailsShowing) { handleDetailsKeyEvent(event); return }

            if (event.key === Qt.Key_Escape || event.text === "q") {
                close(); event.accepted = true; return
            }
            if (event.text === "f") {
                toggleFreeze(); event.accepted = true; return
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                openDetails(); event.accepted = true; return
            }
        }
        // ui only
        // Esc closes only the panel (back to pick/frozen mode). q closes
        // the inspector entirely so the user always has a one-press exit
        // even when buried in a sub-mode.
        function handleDetailsKeyEvent(event): void {
            if (event.key === Qt.Key_Escape) { closeDetails(); event.accepted = true; return }
            if (event.text === "q")          { close();        event.accepted = true; return }

            const t = event.text
            if      (t === "c") copyRule("c")
            else if (t === "t") copyRule("t")
            else if (t === "p") copyRule("p")
            else if (t === "a") copyRule("a")
            else if (t === "w") copyRule("w")
            else if (t === "m") copyRule("m")
            else if (t === "J") copyJson()
            else return

            event.accepted = true
        }

        // ── Key handling (IPC) ────────────────────────────────────────────────
        // ipc only — mirrors UI cascade: Esc closes the topmost surface
        // (panel if open, inspector otherwise); q always closes inspector.
        function key(k: string): void {
            const lk = k.toLowerCase()
            if (lk === "escape" || lk === "esc") {
                root.detailsShowing ? closeDetails() : close()
                return
            }
            if (lk === "q") { close(); return }
            if (lk === "f") { toggleFreeze(); return }
            if (lk === "enter" || lk === "return") { openDetails(); return }
            if (!root.detailsShowing) return
            if      (lk === "c")              copyRule("c")
            else if (lk === "t")              copyRule("t")
            else if (lk === "p")              copyRule("p")
            else if (lk === "a")              copyRule("a")
            else if (lk === "w")              copyRule("w")
            else if (lk === "m")              copyRule("m")
            else if (k === "J" || lk === "j") copyJson()
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

        readonly property bool   showing:        root.showing
        readonly property string mode:           root.mode
        readonly property string pickedAddress:  root.pickedAddr
        readonly property bool   detailsShowing: root.detailsShowing

        function toggle(): void                       { functionality.toggle() }
        function open(): void                         { functionality.open() }
        function close(): void                        { functionality.close() }
        function setMode(m: string): void             { functionality.setMode(m) }
        function key(k: string): void                 { functionality.key(k) }
        function freeze(): void                       { functionality.freeze() }
        function unfreeze(): void                     { functionality.unfreeze() }
        function openDetails(): void                  { functionality.openDetails() }
        function closeDetails(): void                 { functionality.closeDetails() }
        function copyRule(variant: string): void      { functionality.copyRule(variant) }
        function copyJson(): void                     { functionality.copyJson() }
        function inspectActive(): void                { functionality.inspectActive() }
        function inspectByAddress(addr: string): void { functionality.inspectByAddress(addr) }
        function inspectByPid(pid: int): void         { functionality.inspectByPid(pid) }
    }

    // ── Window ────────────────────────────────────────────────────────────────
    // One WlrLayershell per output, because layer surfaces don't migrate
    // when the cursor moves to another monitor — `screen` is set at create
    // time and is not retroactively reassigned. Each surface decides
    // independently whether to draw the outline (only on the picked
    // window's monitor) and the tag (only on the cursor's monitor), and
    // requests keyboard focus only while the cursor is on it so a single
    // surface owns input at a time.
    Variants {
        model: Quickshell.screens

        delegate: WlrLayershell {
            id: win

            required property var modelData    // QsScreen
            readonly property var monitor: Hyprland.monitorFor(modelData)
            readonly property bool isCursorMonitor:
                monitor && Hyprland.focusedMonitor && monitor.id === Hyprland.focusedMonitor.id

            screen: modelData
            visible: root.showing
            color: "transparent"
            layer: WlrLayer.Overlay
            keyboardFocus: win.isCursorMonitor ? WlrKeyboardFocus.Exclusive
                                               : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            namespace: "kh-window-inspector"
            anchors { top: true; bottom: true; left: true; right: true }

            // Empty input region — pointer events fall through to underlying
            // windows so the user can hover them. Keyboard focus is unaffected.
            mask: Region {}

            onVisibleChanged: functionality.onVisibleChanged()

            // Key dispatcher — only the cursor-monitor surface holds focus.
            Item {
                id: keyHandler
                anchors.fill: parent
                focus: win.isCursorMonitor

                Keys.onPressed: (event) => functionality.handleKeyEvent(event)
            }

            // ── Outline + tag (pick mode visuals) ─────────────────────────────
            WindowOutline {
                anchors.fill: parent

                ipc:          root.pickedIpc
                thisMonitor:  win.monitor
                frozen:       root.mode === "frozen"
                outlineColor: cfg.color.base0D
                frozenColor:  cfg.color.base0A
            }

            InspectorTag {
                anchors.fill: parent
                // Hide the floating tag while the details panel is up;
                // the panel re-renders the same info in a fixed location.
                visible: root.showing && win.isCursorMonitor && !root.detailsShowing
                ipc: root.pickedIpc
                // Convert global cursor coords to this surface's local coords.
                cursorX: root.cursorX - (win.monitor ? win.monitor.x : 0)
                cursorY: root.cursorY - (win.monitor ? win.monitor.y : 0)
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

            DetailsPanel {
                anchors.fill: parent
                // Only render on the cursor's monitor so we don't ghost
                // the panel on every output.
                visible: root.detailsShowing && win.isCursorMonitor
                ipc: root.pickedIpc

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
}
