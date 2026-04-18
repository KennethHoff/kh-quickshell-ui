// Application list for kh-launcher.
//
// Owns: app loading, search field, filtering, normal/insert/actions mode.
//
// The orchestrator holds keyboard focus on a dedicated handler and calls
// appList.handleKey(event) in the "list active" branch of its dispatch chain.
// For insert mode, the orchestrator calls appList.enterInsertMode(), which
// transfers focus to the internal search field.
//
// Properties out:
//   selectedApp     — { _filePath, name, exec, comment, terminal, icon } or null
//   mode            — "insert" | "normal" | "actions"
//   hintText        — footer hint for the current state
//   filteredCount   — number of visible apps
//
// Signals:
//   launchRequested(string exec, bool terminal, int workspace)
//   closeRequested()
//   searchEscapePressed()   — Esc in insert mode; orchestrator reclaims focus
//
// handleKey(event) → bool
//   Processes normal / actions mode key events. Returns false for '?' so it
//   propagates to the orchestrator's help handler.
//
// handleIpcKey(k) → bool
//   IPC entry point.
import QtQuick
import Quickshell.Io
import "./lib"

Item {
    id: appList

    NixConfig  { id: cfg }
    NixBins    { id: bin }
    FuzzyScore { id: fuzzy }

    // Frecency store: filePath → "<count>:<lastLaunchEpoch>" — decayed launch
    // counter blended into search scores (see impl.frecencyBoost / runFilter).
    MetaStore {
        id: frecencyStore
        bash:     bin.bash
        appName:  "kh-launcher"
        storeKey: "frecency"
    }

    // Half-life for decayed launch counts (seconds). After this much time with
    // no launches, a count halves — so stale apps eventually stop dominating
    // the ranking even if they were heavily used long ago.
    readonly property int _frecencyHalfLifeSec: 14 * 86400

    // ── Private state ─────────────────────────────────────────────────────────
    property var    _allApps:       []
    property var    _filteredApps:  []
    property string _mode:          "insert"  // "insert" | "normal" | "actions"
    property bool   _pendingG:      false
    property var    _actions:       []        // [{ name, exec }]
    property var    _appBuf:        []        // scratch buffer for listProcess

    // ── Properties out ────────────────────────────────────────────────────────
    readonly property var selectedApp: {
        const idx = list.currentIndex
        const apps = _filteredApps
        return (idx >= 0 && idx < apps.length) ? apps[idx] : null
    }
    readonly property string mode: _mode
    readonly property string modeText: _mode === "normal" ? "NOR" : _mode === "actions" ? "ACT" : ""
    readonly property string hintText: {
        if (_mode === "actions")
            return "j/k navigate  \u00b7  Enter launch action  \u00b7  h / Esc back  \u00b7  ? help"
        if (_mode === "normal")
            return "j/k navigate  \u00b7  Enter launch  \u00b7  l / Tab actions  \u00b7  Ctrl+1\u20139 workspace  \u00b7  / search  \u00b7  ? help  \u00b7  Esc close"
        return "Esc  normal mode  \u00b7  ? help"
    }
    readonly property int filteredCount: _filteredApps.length

    // ── Signals ───────────────────────────────────────────────────────────────
    signal launchRequested(string exec, bool terminal, int workspace)
    signal closeRequested()
    signal searchEscapePressed()
    signal flashRequested(int idx)

    // Load the persisted frecency counts once at startup; subsequent writes
    // happen on launch and the in-memory `values` map stays authoritative.
    Component.onCompleted: frecencyStore.load()

    // ── Public API ────────────────────────────────────────────────────────────
    function reset() {
        _mode     = "insert"
        _pendingG = false
        _actions  = []
        _appBuf   = []
        searchField.text = ""
        list.currentIndex = 0
        actionList.currentIndex = 0
        searchDebounce.stop()
        gTimer.stop()
    }

    function load() {
        _allApps      = []
        _filteredApps = []
        listProcess.running = true
    }

    function enterInsertMode() {
        _mode = "insert"
        searchField.forceActiveFocus()
    }

    function enterNormalMode() {
        _mode = "normal"
        _pendingG = false
    }

    // Returns false if no actions; orchestrator does nothing extra.
    function typeText(text) {
        if (_mode !== "insert") enterInsertMode()
        searchField.text += text
        searchDebounce.stop()
        impl.runFilter()
    }

    function enterActionsMode() {
        const app = selectedApp
        if (!app) return false

        const fv = Qt.createQmlObject('import Quickshell.Io; FileView { blockAllReads: true }', appList)
        fv.path = app._filePath
        const actions = []
        let inAction = false, name = "", exec = ""
        for (const line of fv.text().split("\n")) {
            if (line.startsWith("[Desktop Action ")) {
                if (inAction && name && exec) actions.push({ name, exec })
                inAction = true; name = ""; exec = ""
            } else if (line.startsWith("[")) {
                if (inAction && name && exec) actions.push({ name, exec })
                inAction = false
            } else if (inAction) {
                if (line.startsWith("Name="))      name = line.slice(5).trim()
                else if (line.startsWith("Exec=")) exec = line.slice(5).replace(/%[fFuUdDnNick]/g, "").trim()
            }
        }
        if (inAction && name && exec) actions.push({ name, exec })
        fv.destroy()

        _actions = actions
        if (actions.length > 0) {
            _mode = "actions"
            actionList.currentIndex = 0
        }
        return actions.length > 0
    }

    function flash(idx) { flashRequested(idx) }

    // ── Navigation ────────────────────────────────────────────────────────────
    function navUp() {
        if (_mode === "actions") { if (actionList.currentIndex > 0) actionList.currentIndex-- }
        else if (list.currentIndex > 0) list.currentIndex--
    }
    function navDown() {
        if (_mode === "actions") { if (actionList.currentIndex < actionList.count - 1) actionList.currentIndex++ }
        else if (list.currentIndex < list.count - 1) list.currentIndex++
    }
    function navTop() {
        if (_mode === "actions") actionList.currentIndex = 0
        else list.currentIndex = 0
    }
    function navBottom() {
        if (_mode === "actions") actionList.currentIndex = Math.max(0, actionList.count - 1)
        else list.currentIndex = Math.max(0, list.count - 1)
    }
    function navHalfDown() {
        const step = Math.max(1, Math.floor(list.height / 48 / 2))
        if (_mode === "actions") actionList.currentIndex = Math.min(actionList.count - 1, actionList.currentIndex + step)
        else list.currentIndex = Math.min(list.count - 1, list.currentIndex + step)
    }
    function navHalfUp() {
        const step = Math.max(1, Math.floor(list.height / 48 / 2))
        if (_mode === "actions") actionList.currentIndex = Math.max(0, actionList.currentIndex - step)
        else list.currentIndex = Math.max(0, list.currentIndex - step)
    }

    // ── Key handlers ──────────────────────────────────────────────────────────
    function handleKey(event) {
        if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control ||
            event.key === Qt.Key_Alt   || event.key === Qt.Key_Meta) return false
        if (_mode === "actions") return impl.handleActionsKey(event)
        if (_mode === "normal")  return impl.handleNormalKey(event)
        return false
    }

    function handleIpcKey(k) {
        const lk = k.toLowerCase()
        if (lk === "escape" || lk === "esc") {
            if (_mode === "actions") { enterNormalMode(); return true }
            if (_mode !== "normal")  { enterNormalMode(); return true }
            closeRequested(); return true
        }
        if (lk === "enter" || lk === "return") {
            if (_mode === "actions") { impl.launchAction(0); return true }
            impl.launchApp(0); return true
        }
        return false
    }

    // ── Impl ──────────────────────────────────────────────────────────────────
    QtObject {
        id: impl

        // Parse a frecency store value "count:lastLaunchEpoch" → { count, last }.
        // Returns zeros for missing / malformed entries so callers don't branch.
        function parseFrecency(raw: string): var {
            if (!raw) return { count: 0, last: 0 }
            const colon = raw.indexOf(":")
            if (colon < 0) return { count: 0, last: 0 }
            const count = parseFloat(raw.substring(0, colon))
            const last  = parseInt(raw.substring(colon + 1), 10)
            return { count: isFinite(count) ? count : 0, last: isFinite(last) ? last : 0 }
        }

        // Effective count at `nowSec`, applying exponential decay since last launch.
        function effectiveCount(filePath: string, nowSec: int): real {
            const entry = parseFrecency(frecencyStore.values[filePath] || "")
            if (entry.count <= 0) return 0
            const dt = Math.max(0, nowSec - entry.last)
            return entry.count * Math.exp(-dt * Math.LN2 / appList._frecencyHalfLifeSec)
        }

        // Log-scaled boost added to raw fuzzy score. Tuned so a frequently-used
        // app (count ~= 8) adds ~9 points — enough to beat close fuzzy ties but
        // not to swamp strong prefix matches.
        function frecencyBoost(filePath: string, nowSec: int): real {
            const c = effectiveCount(filePath, nowSec)
            return c > 0 ? 3 * (Math.log(1 + c) / Math.LN2) : 0
        }

        function recordLaunch(filePath: string): void {
            if (!filePath) return
            const now = Math.floor(Date.now() / 1000)
            const entry = parseFrecency(frecencyStore.values[filePath] || "")
            const dt = Math.max(0, now - entry.last)
            const decayed = entry.count * Math.exp(-dt * Math.LN2 / appList._frecencyHalfLifeSec)
            frecencyStore.set(filePath, (decayed + 1).toFixed(4) + ":" + now)
        }

        function launchApp(workspace): void {
            const app = selectedApp
            if (!app) return
            const terminal = (app.terminal === "true" || app.terminal === "True")
            recordLaunch(app._filePath)
            flash(list.currentIndex)
            launchRequested(app.exec.trim(), terminal, workspace)
        }

        function launchAction(workspace): void {
            const idx = actionList.currentIndex
            if (idx < 0 || idx >= appList._actions.length) return
            const action = appList._actions[idx]
            const app = selectedApp
            if (app) recordLaunch(app._filePath)
            flash(actionList.currentIndex)
            launchRequested(action.exec.trim(), false, workspace)
        }

        function handleNormalKey(event): bool {
            if (event.text === "?") return false   // propagate → orchestrator opens help
            if (event.key === Qt.Key_Escape || event.text === "q") {
                closeRequested(); return true
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                launchApp(0); return true
            }
            if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
                navDown(); return true
            }
            if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
                navUp(); return true
            }
            if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
                navBottom(); return true
            }
            if (event.key === Qt.Key_G) {
                if (appList._pendingG) { gTimer.stop(); navTop(); appList._pendingG = false }
                else                   { appList._pendingG = true; gTimer.restart() }
                return true
            }
            if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
                navHalfDown(); return true
            }
            if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                navHalfUp(); return true
            }
            if (event.key === Qt.Key_Tab || event.text === "l") {
                enterActionsMode(); return true
            }
            if (event.key === Qt.Key_Slash) {
                enterInsertMode(); return true
            }
            // Ctrl+1–9: launch on workspace N
            if (event.modifiers & Qt.ControlModifier) {
                const n = event.key - Qt.Key_1 + 1
                if (n >= 1 && n <= 9) { launchApp(n); return true }
            }
            return false
        }

        function handleActionsKey(event): bool {
            if (event.text === "?") return false
            if (event.key === Qt.Key_Escape || event.text === "h" || event.text === "q") {
                enterNormalMode(); return true
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                launchAction(0); return true
            }
            if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
                navDown(); return true
            }
            if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
                navUp(); return true
            }
            if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
                navBottom(); return true
            }
            if (event.key === Qt.Key_G) {
                if (appList._pendingG) { gTimer.stop(); navTop(); appList._pendingG = false }
                else                   { appList._pendingG = true; gTimer.restart() }
                return true
            }
            if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
                navHalfDown(); return true
            }
            if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                navHalfUp(); return true
            }
            // Ctrl+1–9: launch action on workspace N
            if (event.modifiers & Qt.ControlModifier) {
                const n = event.key - Qt.Key_1 + 1
                if (n >= 1 && n <= 9) { launchAction(n); return true }
            }
            return false
        }

        // Supports: fuzzy (default), ' exact, ^ prefix, $ suffix, ! negation.
        // Space-separated tokens combine with AND. Fuzzy scores get a
        // frecency boost so frequently-used apps surface higher (and dominate
        // empty-query ordering).
        function runFilter(): void {
            const q = searchField.text.trim().toLowerCase()
            const nowSec = Math.floor(Date.now() / 1000)

            if (!q) {
                const apps = appList._allApps.slice()
                apps.sort((a, b) => {
                    const cb = effectiveCount(b._filePath, nowSec)
                    const ca = effectiveCount(a._filePath, nowSec)
                    if (cb !== ca) return cb - ca
                    return a.name.localeCompare(b.name)
                })
                appList._filteredApps = apps
                list.currentIndex = 0
                return
            }

            const tokens = q.split(/\s+/).filter(t => t.length > 0)
            const scored = []

            for (const app of appList._allApps) {
                const nameLow = app.name.toLowerCase()
                const haystack = nameLow + " " + app.comment.toLowerCase()
                let totalScore = 0
                let matched = true

                for (const token of tokens) {
                    if (token.startsWith("!")) {
                        const neg = token.slice(1)
                        if (!neg) continue
                        const negScore = token.startsWith("!'")
                            ? haystack.includes(neg.slice(1))
                            : fuzzy.fuzzyScore(neg, haystack) >= 0
                        if (negScore) { matched = false; break }
                    } else if (token.startsWith("'")) {
                        const needle = token.slice(1)
                        if (!needle) continue
                        if (!haystack.includes(needle)) { matched = false; break }
                    } else if (token.startsWith("^")) {
                        const needle = token.slice(1)
                        if (!needle) continue
                        if (!nameLow.startsWith(needle)) { matched = false; break }
                    } else if (token.startsWith("$")) {
                        const needle = token.slice(1)
                        if (!needle) continue
                        if (!nameLow.endsWith(needle)) { matched = false; break }
                    } else {
                        const score = fuzzy.fuzzyScore(token, haystack)
                        if (score < 0) { matched = false; break }
                        totalScore += score
                    }
                }

                if (matched) scored.push({ app, score: totalScore + frecencyBoost(app._filePath, nowSec) })
            }

            scored.sort((a, b) => b.score - a.score)
            appList._filteredApps = scored.map(s => s.app)
            list.currentIndex = 0
        }
    }

    // ── Processes ─────────────────────────────────────────────────────────────
    Process {
        id: listProcess
        command: [bin.scanApps]
        stdout: SplitParser {
            onRead: (line) => functionality.onAppRead(line)
        }
        onExited: functionality.onAppsLoaded()
    }

    Timer {
        id: searchDebounce
        interval: 80
        repeat: false
        onTriggered: functionality.runFilter()
    }

    Timer {
        id: gTimer
        interval: 300
        repeat: false
        onTriggered: functionality.clearPendingG()
    }

    // ── Functionality ─────────────────────────────────────────────────────────
    QtObject {
        id: functionality

        // ui only — search field text change
        function onSearchTextChanged(): void { list.currentIndex = 0; searchDebounce.restart() }
        // ui only — Esc/Return in insert mode
        function searchEscape(): void        { appList._mode = "normal"; appList.searchEscapePressed() }
        // ui only — Ctrl+* emacs bindings in search field
        function handleSearchCtrlKey(event): void {
            if (!(event.modifiers & Qt.ControlModifier)) return
            const pos = searchField.cursorPosition; const len = searchField.text.length
            if      (event.key === Qt.Key_A) { searchField.cursorPosition = 0 }
            else if (event.key === Qt.Key_E) { searchField.cursorPosition = len }
            else if (event.key === Qt.Key_F) { searchField.cursorPosition = Math.min(len, pos + 1) }
            else if (event.key === Qt.Key_B) { searchField.cursorPosition = Math.max(0, pos - 1) }
            else if (event.key === Qt.Key_D) { if (pos < len) searchField.remove(pos, pos + 1) }
            else if (event.key === Qt.Key_K) { if (pos < len) searchField.remove(pos, len) }
            else if (event.key === Qt.Key_W) {
                let i = pos
                while (i > 0 && searchField.text[i - 1] === " ") i--
                while (i > 0 && searchField.text[i - 1] !== " ") i--
                if (i !== pos) searchField.remove(i, pos)
            }
            else if (event.key === Qt.Key_U) { if (pos > 0) searchField.remove(0, pos) }
            else return
            event.accepted = true
        }
        // ui only — clamp list currentIndex on model count change
        function clampListIndex(): void    { if (list.count > 0 && list.currentIndex < 0) list.currentIndex = 0 }
        // ui only — clamp actionList currentIndex on model count change
        function clampActionIndex(): void  { if (actionList.count > 0 && actionList.currentIndex < 0) actionList.currentIndex = 0 }
        // ui only — accumulate one line from the app list process
        function onAppRead(line: string): void { if (line !== "") appList._appBuf.push(line) }
        // ui only — parse buffered app lines and populate the app list
        function onAppsLoaded(): void {
            const apps = []
            for (const line of appList._appBuf) {
                const parts = line.split("\t")
                if (parts.length < 2) continue
                apps.push({
                    _filePath: parts[0] || "",
                    name:      parts[1] || "",
                    exec:      parts[2] || "",
                    comment:   parts[3] || "",
                    terminal:  parts[4] || "false",
                    icon:      parts[5] || ""
                })
            }
            appList._allApps = apps
            appList._appBuf  = []
            impl.runFilter()
            if (appList._mode === "insert") searchField.forceActiveFocus()
        }
        // ui only — run the filter (called by debounce timer)
        function runFilter(): void { impl.runFilter() }
        // ui only — clear the pending-G double-tap flag
        function clearPendingG(): void { appList._pendingG = false }
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    Column {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        // Search bar ──────────────────────────────────────────────────────────
        Rectangle {
            id: searchBox
            width: parent.width
            height: 44
            color: cfg.color.base01
            radius: 8

            Rectangle {
                id: modeTag
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                visible: appList._mode !== "insert"
                width: modeLabel.implicitWidth + 12
                height: 22
                radius: 4
                color: appList._mode === "actions" ? cfg.color.base0B + "33" : cfg.color.base02

                Text {
                    id: modeLabel
                    anchors.centerIn: parent
                    text: appList.modeText
                    color: appList._mode === "actions" ? cfg.color.base0B : cfg.color.base0D
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize - 3
                    font.bold: true
                }
            }

            TextInput {
                id: searchField
                anchors.fill: parent
                anchors.leftMargin: appList._mode !== "insert" ? modeTag.width + 18 : 14
                anchors.rightMargin: 14
                color: appList._mode === "actions" ? "transparent" : cfg.color.base05
                font.family: cfg.fontFamily
                font.pixelSize: cfg.fontSize
                clip: true
                verticalAlignment: TextInput.AlignVCenter
                readOnly: appList._mode !== "insert"

                Text {
                    anchors.fill: parent
                    visible: !searchField.text && appList._mode === "insert"
                    text: "Search applications..."
                    color: cfg.color.base03
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize
                    verticalAlignment: Text.AlignVCenter
                }

                // Actions mode: show selected app name in the bar
                Text {
                    anchors.fill: parent
                    anchors.leftMargin: modeTag.width + 8
                    visible: appList._mode === "actions" && appList.selectedApp !== null
                    text: appList.selectedApp ? "Actions \u2014 " + appList.selectedApp.name : ""
                    color: cfg.color.base04
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                onTextChanged:        functionality.onSearchTextChanged()
                Keys.onEscapePressed: functionality.searchEscape()
                Keys.onReturnPressed: functionality.searchEscape()
                Keys.onPressed: (event) => functionality.handleSearchCtrlKey(event)
            }
        }

        // App list ────────────────────────────────────────────────────────────
        ListView {
            id: list
            width: parent.width
            height: parent.height - searchBox.height - parent.spacing
            clip: true
            currentIndex: 0
            model: appList._filteredApps
            visible: appList._mode !== "actions"
            highlightMoveDuration: 0

            onCountChanged: functionality.clampListIndex()

            Text {
                anchors.centerIn: parent
                visible: list.count === 0 && appList._mode !== "actions"
                text: appList._allApps.length === 0 ? "Loading..." : "No results"
                color: cfg.color.base03
                font.family: cfg.fontFamily
                font.pixelSize: cfg.fontSize
            }

            delegate: Item {
                id: appDelegate
                required property var modelData
                required property int index
                width: list.width
                height: modelData.comment !== "" ? 52 : 40

                readonly property bool isCurrent: list.currentIndex === index

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    color: appDelegate.isCurrent ? cfg.color.base02 : "transparent"
                    radius: 6

                    Item {
                        id: appIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32
                        height: 32

                        Image {
                            id: appIconImage
                            anchors.fill: parent
                            source: modelData.icon !== "" ? ("file://" + modelData.icon) : ""
                            fillMode: Image.PreserveAspectFit
                            sourceSize: Qt.size(32, 32)
                            smooth: true
                            visible: status === Image.Ready
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: appIconImage.status !== Image.Ready
                            color: cfg.color.base02
                            radius: 6

                            Text {
                                anchors.centerIn: parent
                                text: modelData.name.charAt(0).toUpperCase()
                                color: cfg.color.base05
                                font.family: cfg.fontFamily
                                font.pixelSize: 16
                                font.bold: true
                            }
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: appIcon.right
                        anchors.right: parent.right
                        anchors.leftMargin: 8
                        anchors.rightMargin: 12
                        spacing: 1

                        Text {
                            text: modelData.name
                            color: cfg.color.base05
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            visible: modelData.comment !== ""
                            text: modelData.comment
                            color: cfg.color.base03
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize - 2
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    Rectangle {
                        id: flashOverlay
                        anchors.fill: parent
                        radius: 6
                        color: cfg.color.base0B
                        opacity: 0
                        SequentialAnimation {
                            id: blinkAnim
                            NumberAnimation {
                                target: flashOverlay; property: "opacity"
                                to: 0.55; duration: 60; easing.type: Easing.OutQuad
                            }
                            NumberAnimation {
                                target: flashOverlay; property: "opacity"
                                to: 0; duration: 140; easing.type: Easing.InQuad
                            }
                        }
                    }

                    QtObject {
                        id: appDelegateFunctionality
                        // ui only
                        function onFlashRequested(idx: int): void {
                            if (appList._mode !== "actions" && idx === appDelegate.index)
                                blinkAnim.restart()
                        }
                    }

                    Connections {
                        target: appList
                        function onFlashRequested(idx) { appDelegateFunctionality.onFlashRequested(idx) }
                    }
                }
            }
        }

        // Actions list ────────────────────────────────────────────────────────
        ListView {
            id: actionList
            width: parent.width
            height: parent.height - searchBox.height - parent.spacing
            clip: true
            currentIndex: 0
            model: appList._actions
            visible: appList._mode === "actions"
            highlightMoveDuration: 0

            onCountChanged: functionality.clampActionIndex()

            delegate: Item {
                id: actionDelegate
                required property var modelData
                required property int index
                width: actionList.width
                height: 40

                readonly property bool isCurrent: actionList.currentIndex === index

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    color: actionDelegate.isCurrent ? cfg.color.base02 : "transparent"
                    radius: 6

                    Item {
                        id: actionIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 28

                        Image {
                            id: actionIconImage
                            anchors.fill: parent
                            source: appList.selectedApp && appList.selectedApp.icon !== ""
                                    ? ("file://" + appList.selectedApp.icon) : ""
                            fillMode: Image.PreserveAspectFit
                            sourceSize: Qt.size(28, 28)
                            smooth: true
                            visible: status === Image.Ready
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: actionIconImage.status !== Image.Ready
                            color: cfg.color.base02
                            radius: 5

                            Text {
                                anchors.centerIn: parent
                                text: appList.selectedApp ? appList.selectedApp.name.charAt(0).toUpperCase() : ""
                                color: cfg.color.base05
                                font.family: cfg.fontFamily
                                font.pixelSize: 14
                                font.bold: true
                            }
                        }
                    }

                    Text {
                        anchors.left: actionIcon.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        color: cfg.color.base05
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        id: actionFlash
                        anchors.fill: parent
                        radius: 6
                        color: cfg.color.base0B
                        opacity: 0
                        SequentialAnimation {
                            id: actionBlinkAnim
                            NumberAnimation {
                                target: actionFlash; property: "opacity"
                                to: 0.55; duration: 60; easing.type: Easing.OutQuad
                            }
                            NumberAnimation {
                                target: actionFlash; property: "opacity"
                                to: 0; duration: 140; easing.type: Easing.InQuad
                            }
                        }
                    }

                    QtObject {
                        id: actionDelegateFunctionality
                        // ui only
                        function onFlashRequested(idx: int): void {
                            if (appList._mode === "actions" && idx === actionDelegate.index)
                                actionBlinkAnim.restart()
                        }
                    }

                    Connections {
                        target: appList
                        function onFlashRequested(idx) { actionDelegateFunctionality.onFlashRequested(idx) }
                    }
                }
            }
        }
    }
}
