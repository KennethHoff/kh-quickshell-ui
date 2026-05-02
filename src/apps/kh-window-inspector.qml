// Window inspector — pick-first overlay over open windows.
//
// Daemon: quickshell -p <config-dir>
// Toggle: quickshell ipc -c kh-window-inspector call window-inspector toggle
//
// This file owns: window, IPC, key dispatch, cursor polling, hit-testing,
// yank chord state, and dispatcher actions. Visual layers (outline, tag,
// help) live in window-inspector/*.qml.
//
// Pick mode is the default: an empty input region lets the cursor pass
// through to the underlying windows; we poll `hyprctl cursorpos`, find
// the topmost window under the cursor, and render an outline + tag.
// `f` freezes the picked window so it survives focus loss.
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
    // Yank chord state — when true, the next key resolves to a copy variant.
    property bool   yankChord:  false

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
    // SplitParser straightforward. Quickshell's `Hyprland.activeWindow` can
    // be stale or null right after taking keyboard focus, so we ask hyprctl
    // directly.
    property string _activeBuf: ""
    Process {
        id: activeProc
        command: [bin.bash, "-c", bin.hyprctl + " activewindow -j | tr -d '\\n'"]
        stdout: SplitParser {
            onRead: (line) => functionality.onActiveRead(line)
        }
        onExited: functionality.onActiveExited()
    }

    // ── Yank / dispatch processes ────────────────────────────────────────────
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
        function toggle(): void { root.showing = !root.showing }
        // ipc only
        function open(): void   { root.showing = true }
        // ui+ipc
        function close(): void  { root.showing = false }
        // ui only
        function onShow(): void {
            root.mode = "pick"
            root.frozenAddr = ""
            root.yankChord = false
            helpOverlay.close()
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
        // ipc only
        function pickedAddress(): string { return root.pickedAddr }

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

        // ── Help ──────────────────────────────────────────────────────────────
        // ui+ipc
        function openHelp(): void  { helpOverlay.open() }
        // ui+ipc
        function closeHelp(): void { helpOverlay.close() }
        // ipc only
        function toggleHelp(): void { helpOverlay.showing ? closeHelp() : openHelp() }

        // ── Yank ──────────────────────────────────────────────────────────────
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
            const mon   = ipc.monitor || ""
            if (variant === "t") return "windowrulev2 = <action>, initialTitle:^" + escapeRegex(ttl) + "$"
            if (variant === "p") return "windowrulev2 = <action>, pid:" + pid
            if (variant === "a") return "windowrulev2 = <action>, address:" + addr
            if (variant === "w") return "windowrulev2 = <action>, workspace:" + ws
            if (variant === "m") return "windowrulev2 = <action>, monitor:" + mon
            // Default ("c" or bare y) — initialClass.
            return "windowrulev2 = <action>, initialClass:^" + escapeRegex(cls) + "$"
        }
        // ui only
        function escapeRegex(s: string): string {
            return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
        }
        // ui+ipc
        function yank(variant: string): void {
            const ipc = ipcForAddr(root.pickedAddr)
            if (!ipc) return
            impl.copyText(ruleLine(ipc, variant))
            root.yankChord = false
        }
        // ui+ipc
        function yankJson(): void {
            const ipc = ipcForAddr(root.pickedAddr)
            if (!ipc) return
            impl.copyText(JSON.stringify(ipc, null, 2))
            root.yankChord = false
        }
        // ui only
        function startYankChord(): void {
            if (!root.pickedAddr) return
            root.yankChord = true
            yankChordTimer.restart()
        }
        // ui only
        function cancelYankChord(): void {
            root.yankChord = false
            yankChordTimer.stop()
        }
        // ui only
        function yankChordTimedOut(): void {
            if (!root.yankChord) return
            yank("c")
        }

        // ── Dispatch actions ──────────────────────────────────────────────────
        // ui+ipc
        function closeWindow(): void {
            if (!root.pickedAddr) return
            Hyprland.dispatch("closewindow address:" + root.pickedAddr)
        }
        // ui+ipc
        function focusWindow(): void {
            if (!root.pickedAddr) return
            Hyprland.dispatch("focuswindow address:" + root.pickedAddr)
        }
        // ui+ipc
        function toggleFloating(): void {
            if (!root.pickedAddr) return
            Hyprland.dispatch("togglefloating address:" + root.pickedAddr)
        }
        // ui+ipc
        function togglePinned(): void {
            if (!root.pickedAddr) return
            Hyprland.dispatch("pin address:" + root.pickedAddr)
        }
        // ui+ipc
        function moveToWorkspace(n: int): void {
            if (!root.pickedAddr || n < 1) return
            Hyprland.dispatch("movetoworkspace " + n + ",address:" + root.pickedAddr)
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
        function handleKeyEvent(event): void {
            if (event.key === Qt.Key_Shift   || event.key === Qt.Key_Control ||
                event.key === Qt.Key_Alt     || event.key === Qt.Key_Meta) return

            if (helpOverlay.showing) {
                event.accepted = helpOverlay.handleKey(event)
                return
            }

            // Yank chord — next key resolves the variant.
            if (root.yankChord) {
                if (event.key === Qt.Key_Escape) { cancelYankChord(); event.accepted = true; return }
                const t = event.text
                if      (t === "y" || t === "c") yank("c")
                else if (t === "t") yank("t")
                else if (t === "p") yank("p")
                else if (t === "a") yank("a")
                else if (t === "w") yank("w")
                else if (t === "m") yank("m")
                else cancelYankChord()
                event.accepted = true
                return
            }

            // Close.
            if (event.key === Qt.Key_Escape || event.text === "q") {
                close(); event.accepted = true; return
            }

            // Help.
            if (event.text === "?") { openHelp(); event.accepted = true; return }

            // Freeze toggle.
            if (event.text === "f") { toggleFreeze(); event.accepted = true; return }

            // Yank.
            if (event.text === "y") { startYankChord(); event.accepted = true; return }
            if (event.text === "Y") { yankJson(); event.accepted = true; return }

            // Dispatch actions — gated on having a picked window.
            if (event.text === "X") { closeWindow();    event.accepted = true; return }
            if (event.text === "F") { focusWindow();    event.accepted = true; return }
            if (event.text === "t") { toggleFloating(); event.accepted = true; return }
            if (event.text === "T") { togglePinned();   event.accepted = true; return }

            // m1..m9 — move to workspace. `m` enters a one-shot chord.
            if (event.text === "m") { mChord.armed = true; event.accepted = true; return }
            if (mChord.armed) {
                mChord.armed = false
                const d = parseInt(event.text)
                if (!isNaN(d) && d >= 1 && d <= 9) moveToWorkspace(d)
                event.accepted = true
                return
            }
        }

        // ── Key handling (IPC) ────────────────────────────────────────────────
        // ipc only
        function key(k: string): void {
            const lk = k.toLowerCase()
            if      (lk === "?")                       toggleHelp()
            else if (lk === "escape" || lk === "esc" || lk === "q") close()
            else if (lk === "f")                       toggleFreeze()
            else if (lk === "y")                       yank("c")
            else if (lk === "yc")                      yank("c")
            else if (lk === "yt")                      yank("t")
            else if (lk === "yp")                      yank("p")
            else if (lk === "ya")                      yank("a")
            else if (lk === "yw")                      yank("w")
            else if (lk === "ym")                      yank("m")
            else if (lk === "shift+y" || k === "Y")    yankJson()
            else if (lk === "shift+x" || k === "X")    closeWindow()
            else if (lk === "shift+f" || k === "F")    focusWindow()
            else if (lk === "t")                       toggleFloating()
            else if (lk === "shift+t" || k === "T")    togglePinned()
            else if (lk.startsWith("m") && lk.length === 2) {
                const d = parseInt(lk.slice(1))
                if (!isNaN(d) && d >= 1 && d <= 9) moveToWorkspace(d)
            }
        }
        // ipc only
        function setMode(m: string): void {
            if      (m === "pick"   || m === "live")   unfreeze()
            else if (m === "frozen" || m === "freeze") freeze()
        }
    }

    // One-shot chord state for `m<1-9>`.
    QtObject {
        id: mChord
        property bool armed: false
    }

    Timer {
        id: yankChordTimer
        interval: 700
        repeat: false
        onTriggered: functionality.yankChordTimedOut()
    }

    // ── IPC ───────────────────────────────────────────────────────────────────
    IpcHandler {
        target: "window-inspector"

        readonly property bool   showing:        root.showing
        readonly property string mode:           root.mode
        readonly property string pickedAddress:  root.pickedAddr

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
        function focusWindow(): void                  { functionality.focusWindow() }
        function closeWindow(): void                  { functionality.closeWindow() }
        function toggleFloating(): void               { functionality.toggleFloating() }
        function togglePinned(): void                 { functionality.togglePinned() }
        function moveToWorkspace(n: int): void        { functionality.moveToWorkspace(n) }
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
        // The help overlay is keyboard-only, so we never need pointer input.
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
            outlineColor:    cfg.color.base0D
            frozenColor:     cfg.color.base0A
        }

        InspectorTag {
            id: tag
            anchors.fill: parent
            visible: root.showing && !helpOverlay.showing
            ipc: root.pickedIpc
            // Layer surface coords are local to its output; convert global
            // cursor coords by subtracting the focused monitor's origin.
            cursorX: root.cursorX - (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.x : 0)
            cursorY: root.cursorY - (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.y : 0)
            screenW: win.width
            screenH: win.height
            frozen: root.mode === "frozen"
            yankChord: root.yankChord
            mChord: mChord.armed

            bgColor:      cfg.color.base01
            headerBg:     cfg.color.base02
            textColor:    cfg.color.base05
            mutedColor:   cfg.color.base03
            keyColor:     cfg.color.base0D
            warnColor:    cfg.color.base0A
            stableColor:  cfg.color.base0B
            fontFamily:   cfg.fontFamily
            fontSize:     cfg.fontSize
        }

        // ── Help overlay ──────────────────────────────────────────────────────
        HelpOverlay {
            id: helpOverlay
            anchors.fill: parent

            sections: [{
                title: "PICK MODE",
                bindings: [
                    { key: "f",            desc: "freeze / unfreeze picked window" },
                    { key: "Esc / q",      desc: "close inspector" },
                    { key: "?",            desc: "toggle this help" }
                ]
            }, {
                title: "COPY",
                bindings: [
                    { key: "y",            desc: "copy as windowrulev2 (initialClass, default)" },
                    { key: "yc",           desc: "copy as windowrulev2 (initialClass)" },
                    { key: "yt",           desc: "copy as windowrulev2 (initialTitle)" },
                    { key: "yp",           desc: "copy as windowrulev2 (pid)" },
                    { key: "ya",           desc: "copy as windowrulev2 (address)" },
                    { key: "yw",           desc: "copy as windowrulev2 (workspace)" },
                    { key: "ym",           desc: "copy as windowrulev2 (monitor)" },
                    { key: "Y",            desc: "copy full hyprctl clients -j record" }
                ]
            }, {
                title: "DISPATCH",
                bindings: [
                    { key: "X",            desc: "close window" },
                    { key: "F",            desc: "focus window" },
                    { key: "t",            desc: "toggle floating" },
                    { key: "T",            desc: "toggle pinned" },
                    { key: "m1…m9",   desc: "move to workspace 1…9" }
                ]
            }]

            bgColor:    cfg.color.base01
            headerBg:   cfg.color.base02
            textColor:  cfg.color.base05
            keyColor:   cfg.color.base0D
            dimColor:   cfg.color.base03
            fontFamily: cfg.fontFamily
            fontSize:   cfg.fontSize
        }
    }
}
