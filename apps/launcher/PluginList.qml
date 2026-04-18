// Plugin list for kh-launcher.
//
// Unified plugin host — every plugin (apps, window switcher, emoji, etc.) flows
// through the same item model, search, navigation, and launch path.  The
// built-in "apps" plugin is registered in PluginRegistry.qml by Nix alongside
// any user-defined script plugins; there is no app-specific logic here.
//
// Owns: plugin activation, item loading (registered script or ad-hoc IPC push),
// search field, filtering, normal/insert/actions input modes, navigation.
//
// Properties out:
//   selectedItem      — { label, description, icon, callback, id } or null
//   activePluginName  — current plugin name (e.g. "apps", "hyprland-windows")
//   mode              — "insert" | "normal" | "actions" (navigation state)
//   hintText          — footer hint for the current state
//   filteredCount     — number of visible items
//   lastSelection     — label of the last launched item
//   placeholder       — search field placeholder for the active plugin
//
// Signals:
//   launchRequested(string callback, int workspace)
//   closeRequested()
//   searchEscapePressed()   — Esc in insert mode; orchestrator reclaims focus
//
// handleKey(event) → bool
//   Processes normal / actions mode key events.  Returns false for '?' so it
//   propagates to the orchestrator's help handler.
//
// handleIpcKey(k) → bool
//   IPC entry point.
import QtQuick
import Quickshell.Io
import "./lib"

Item {
    id: pluginList

    NixConfig      { id: cfg }
    NixBins        { id: bin }
    FuzzyScore     { id: fuzzy }
    PluginRegistry   { id: registry }

    // Frecency store: id → "<count>:<lastLaunchEpoch>" — decayed launch
    // counter blended into search scores for modes that opt in.
    MetaStore {
        id: frecencyStore
        bash:     bin.bash
        appName:  "kh-launcher"
        storeKey: "frecency"
    }

    // Half-life for decayed launch counts (seconds).
    readonly property int _frecencyHalfLifeSec: 14 * 86400

    // ── Runtime plugin registry ───────────────────────────────────────────────
    // Seeded from PluginRegistry (Nix) at startup.  Mutable at runtime via
    // registerPlugin / removePlugin.  Each entry:
    //   { script, frecency, hasActions, placeholder, label, default }
    // The key is the stable identifier used by IPC; `label` is what the chip
    // in the plugin bar displays (falls back to the key when empty).
    property var _plugins: ({})

    // Seed the runtime registry from Nix-generated PluginRegistry on startup.
    Component.onCompleted: {
        frecencyStore.load()
        const seed = {}
        const src = registry.plugins
        for (const name in src) {
            seed[name] = src[name]
        }
        _plugins = seed
    }

    // ── Private state ─────────────────────────────────────────────────────────
    property string _activePlugin:     ""       // current plugin name
    property var    _pluginConfig:     ({})     // config object from registry (or {})
    property var    _allItems:       []       // [{ label, description, icon, callback, id }]
    property var    _filteredItems:  []
    property string _mode:           "insert" // "insert" | "normal" | "actions"
    property bool   _pendingG:       false
    property var    _actions:        []       // [{ name, exec }] for desktop-action sub-mode
    property var    _pluginItems:      ({})     // modeName → [parsed items] (persists across switches)
    property var    _itemBuf:        ({})     // modeName → [item objects] (in-progress IPC push)
    property var    _scriptBuf:      []       // raw lines from the active plugin's script process
    property string _lastSelection:  ""       // label of last launched item

    // ── Properties out ────────────────────────────────────────────────────────
    readonly property var selectedItem: {
        const idx = list.currentIndex
        const items = _filteredItems
        return (idx >= 0 && idx < items.length) ? items[idx] : null
    }
    readonly property string activePluginName: _activePlugin
    readonly property string mode: _mode
    readonly property string modeText: _mode === "normal" ? "NOR" : _mode === "actions" ? "ACT" : ""
    readonly property string hintText: {
        if (_mode === "actions")
            return "j/k navigate  \u00b7  Enter launch action  \u00b7  h / Esc back  \u00b7  ? help"
        if (_mode === "normal")
            return "j/k navigate  \u00b7  Enter launch  \u00b7  " +
                   (_pluginConfig.hasActions ? "l / Tab actions  \u00b7  " : "") +
                   (Object.keys(_plugins).length > 1 ? "[ / ] switch plugin  \u00b7  " : "") +
                   "Ctrl+1\u20139 workspace  \u00b7  / search  \u00b7  ? help  \u00b7  Esc close"
        return "Esc  normal mode  \u00b7  ? help"
    }
    readonly property int filteredCount: _filteredItems.length
    readonly property string lastSelection: _lastSelection
    readonly property string placeholder: _pluginConfig.placeholder || "Search..."
    readonly property var pluginNames: Object.keys(_plugins)

    // ── Signals ───────────────────────────────────────────────────────────────
    signal launchRequested(string callback, int workspace)
    signal closeRequested()
    signal searchEscapePressed()
    signal flashRequested(int idx)

    // ── Public API ────────────────────────────────────────────────────────────

    // Activate a plugin by name.  If the plugin already has buffered items (from
    // a prior addItem+itemsReady), displays them immediately.  If the name is
    // in the registry and has a script, runs it to (re)populate items.
    // Otherwise creates an empty ad-hoc plugin (caller pushes items via
    // addItem + itemsReady).
    function activatePlugin(name) {
        _activePlugin    = name
        _pluginConfig    = _plugins[name] || {}
        _actions       = []
        _mode          = "insert"
        _pendingG      = false
        searchField.text = ""
        list.currentIndex = 0
        actionList.currentIndex = 0
        searchDebounce.stop()
        gTimer.stop()

        // If items were pre-populated via addItem+itemsReady, show them.
        const existing = _pluginItems[name]
        if (existing && existing.length > 0) {
            _allItems      = existing
            _filteredItems = []
            impl.runFilter()
            if (_mode === "insert") searchField.forceActiveFocus()
            return
        }

        _allItems      = []
        _filteredItems = []

        if (_pluginConfig.script) {
            pluginProcess.command = [_pluginConfig.script]
            pluginProcess.running = true
        }
    }

    // Activate the default plugin (the one with default: true in the registry).
    // If the registry is empty, clears the UI.
    function activateDefaultPlugin() {
        const plugins = _plugins
        for (const name in plugins) {
            if (plugins[name]["default"]) { activatePlugin(name); return }
        }
        // Fallback: activate first available plugin
        for (const name in plugins) { activatePlugin(name); return }
        // No plugins at all — clear the UI
        _activePlugin    = ""
        _pluginConfig    = {}
        _allItems      = []
        _filteredItems = []
        _actions       = []
        _mode          = "insert"
        _pendingG      = false
        searchField.text = ""
        list.currentIndex = 0
    }

    // Push an item into a named plugin's buffer.  The plugin does not need to
    // be active — items accumulate until itemsReady(plugin) is called.
    function addItem(plugin, label, description, icon, callback, id) {
        const buf = _itemBuf
        if (!buf[plugin]) buf[plugin] = []
        buf[plugin].push({
            label:       label       || "",
            description: description || "",
            icon:        icon        || "",
            callback:    callback    || "",
            id:          id          || label || ""
        })
        _itemBuf = buf
    }

    // Signal that all items for the named plugin have been pushed.  Stores the
    // parsed items and, if that plugin is currently active, refreshes the display.
    function itemsReady(plugin) {
        const buf = _itemBuf
        const items = (buf[plugin] || []).slice()
        delete buf[plugin]
        _itemBuf = buf

        const mi = {}
        for (const k in _pluginItems) mi[k] = _pluginItems[k]
        mi[plugin] = items
        _pluginItems = mi

        if (_activePlugin === plugin) {
            _allItems = items
            impl.runFilter()
            if (_mode === "insert") searchField.forceActiveFocus()
        }
    }

    // Register (or replace) a plugin in the runtime registry.
    // `label` is the display name shown on the plugin chip; empty falls back
    // to the plugin key.
    function registerPlugin(name, script, frecency, hasActions, placeholder, label) {
        const p = {}
        for (const k in _plugins) p[k] = _plugins[k]
        p[name] = {
            script:      script      || "",
            frecency:    !!frecency,
            hasActions:  !!hasActions,
            placeholder: placeholder || "Search...",
            label:       label       || name,
            "default":   false
        }
        _plugins = p
    }

    // Return the display label for a plugin key, falling back to the key.
    function pluginLabel(name) {
        const p = _plugins[name]
        return (p && p.label) ? p.label : name
    }

    // Remove a plugin from the runtime registry.  If the removed plugin is
    // currently active, returns to the default plugin.
    function removePlugin(name) {
        if (!(name in _plugins)) return
        const p = {}
        for (const k in _plugins) { if (k !== name) p[k] = _plugins[k] }
        _plugins = p
        if (_activePlugin === name) activateDefaultPlugin()
    }

    // Return a space-separated list of registered plugin names.
    function listPlugins() {
        return Object.keys(_plugins).join(" ")
    }

    // Cycle to the next registered plugin.
    function nextPlugin() {
        const names = Object.keys(_plugins)
        if (names.length <= 1) return
        const idx = names.indexOf(_activePlugin)
        activatePlugin(names[(idx + 1) % names.length])
    }

    // Cycle to the previous registered plugin.
    function prevPlugin() {
        const names = Object.keys(_plugins)
        if (names.length <= 1) return
        const idx = names.indexOf(_activePlugin)
        activatePlugin(names[(idx - 1 + names.length) % names.length])
    }

    function reset() {
        _activePlugin    = ""
        _pluginConfig    = {}
        _allItems      = []
        _filteredItems = []
        _pluginItems     = {}
        _itemBuf       = {}
        _scriptBuf     = []
        _actions       = []
        _mode          = "insert"
        _pendingG      = false
        _lastSelection = ""
        searchField.text = ""
        list.currentIndex = 0
        actionList.currentIndex = 0
        searchDebounce.stop()
        gTimer.stop()
    }

    function enterInsertMode() {
        _mode = "insert"
        searchField.forceActiveFocus()
    }

    function enterNormalMode() {
        _mode = "normal"
        _pendingG = false
    }

    function typeText(text) {
        if (_mode !== "insert") enterInsertMode()
        searchField.text += text
        searchDebounce.stop()
        impl.runFilter()
    }

    function enterActionsMode() {
        if (!_pluginConfig.hasActions) return false
        const item = selectedItem
        if (!item || !item.id) return false

        const fv = Qt.createQmlObject('import Quickshell.Io; FileView { blockAllReads: true }', pluginList)
        fv.path = item.id
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
            impl.launchItem(0); return true
        }
        return false
    }

    // ── Impl ──────────────────────────────────────────────────────────────────
    QtObject {
        id: impl

        // ── Frecency ─────────────────────────────────────────────────────────
        function parseFrecency(raw: string): var {
            if (!raw) return { count: 0, last: 0 }
            const colon = raw.indexOf(":")
            if (colon < 0) return { count: 0, last: 0 }
            const count = parseFloat(raw.substring(0, colon))
            const last  = parseInt(raw.substring(colon + 1), 10)
            return { count: isFinite(count) ? count : 0, last: isFinite(last) ? last : 0 }
        }

        function effectiveCount(id: string, nowSec: int): real {
            const entry = parseFrecency(frecencyStore.values[id] || "")
            if (entry.count <= 0) return 0
            const dt = Math.max(0, nowSec - entry.last)
            return entry.count * Math.exp(-dt * Math.LN2 / pluginList._frecencyHalfLifeSec)
        }

        function frecencyBoost(id: string, nowSec: int): real {
            const c = effectiveCount(id, nowSec)
            return c > 0 ? 3 * (Math.log(1 + c) / Math.LN2) : 0
        }

        function recordLaunch(id: string): void {
            if (!id) return
            const now = Math.floor(Date.now() / 1000)
            const entry = parseFrecency(frecencyStore.values[id] || "")
            const dt = Math.max(0, now - entry.last)
            const decayed = entry.count * Math.exp(-dt * Math.LN2 / pluginList._frecencyHalfLifeSec)
            frecencyStore.set(id, (decayed + 1).toFixed(4) + ":" + now)
        }

        // ── Launch ───────────────────────────────────────────────────────────
        function launchItem(workspace): void {
            const item = pluginList.selectedItem
            if (!item) return
            if (pluginList._pluginConfig.frecency) recordLaunch(item.id)
            pluginList._lastSelection = item.label
            flash(list.currentIndex)
            launchRequested(item.callback.trim(), workspace)
        }

        function launchAction(workspace): void {
            const idx = actionList.currentIndex
            if (idx < 0 || idx >= pluginList._actions.length) return
            const action = pluginList._actions[idx]
            const item = pluginList.selectedItem
            if (item && pluginList._pluginConfig.frecency) recordLaunch(item.id)
            pluginList._lastSelection = action.name
            flash(actionList.currentIndex)
            launchRequested(action.exec.trim(), workspace)
        }

        // ── Key dispatch ─────────────────────────────────────────────────────
        function handleNormalKey(event): bool {
            if (event.text === "?") return false   // propagate → orchestrator opens help
            if (event.key === Qt.Key_Escape || event.text === "q") {
                closeRequested(); return true
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                launchItem(0); return true
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
                if (pluginList._pendingG) { gTimer.stop(); navTop(); pluginList._pendingG = false }
                else                    { pluginList._pendingG = true; gTimer.restart() }
                return true
            }
            if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
                navHalfDown(); return true
            }
            if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                navHalfUp(); return true
            }
            if ((event.key === Qt.Key_Tab || event.text === "l") && pluginList._pluginConfig.hasActions) {
                enterActionsMode(); return true
            }
            if (event.key === Qt.Key_Slash) {
                enterInsertMode(); return true
            }
            if (event.key === Qt.Key_BracketRight) {
                pluginList.nextPlugin(); return true
            }
            if (event.key === Qt.Key_BracketLeft) {
                pluginList.prevPlugin(); return true
            }
            // Ctrl+1–9: launch on workspace N
            if (event.modifiers & Qt.ControlModifier) {
                const n = event.key - Qt.Key_1 + 1
                if (n >= 1 && n <= 9) { launchItem(n); return true }
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
                if (pluginList._pendingG) { gTimer.stop(); navTop(); pluginList._pendingG = false }
                else                    { pluginList._pendingG = true; gTimer.restart() }
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

        // ── Filter ───────────────────────────────────────────────────────────
        // Supports: fuzzy (default), ' exact, ^ prefix, $ suffix, ! negation.
        // Space-separated tokens combine with AND.  Modes with frecency
        // enabled get a log-scaled boost so frequently-used items rank higher.
        function runFilter(): void {
            const q = searchField.text.trim().toLowerCase()
            const nowSec = Math.floor(Date.now() / 1000)
            const useFrecency = !!pluginList._pluginConfig.frecency

            if (!q) {
                const items = pluginList._allItems.slice()
                if (useFrecency) {
                    items.sort((a, b) => {
                        const cb = effectiveCount(b.id, nowSec)
                        const ca = effectiveCount(a.id, nowSec)
                        if (cb !== ca) return cb - ca
                        return a.label.localeCompare(b.label)
                    })
                }
                pluginList._filteredItems = items
                list.currentIndex = 0
                return
            }

            const tokens = q.split(/\s+/).filter(t => t.length > 0)
            const scored = []

            for (const item of pluginList._allItems) {
                const labelLow = item.label.toLowerCase()
                const haystack = labelLow + " " + item.description.toLowerCase()
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
                        if (!labelLow.startsWith(needle)) { matched = false; break }
                    } else if (token.startsWith("$")) {
                        const needle = token.slice(1)
                        if (!needle) continue
                        if (!labelLow.endsWith(needle)) { matched = false; break }
                    } else {
                        const score = fuzzy.fuzzyScore(token, haystack)
                        if (score < 0) { matched = false; break }
                        totalScore += score
                    }
                }

                if (matched) {
                    const boost = useFrecency ? frecencyBoost(item.id, nowSec) : 0
                    scored.push({ item, score: totalScore + boost })
                }
            }

            scored.sort((a, b) => b.score - a.score)
            pluginList._filteredItems = scored.map(s => s.item)
            list.currentIndex = 0
        }
    }

    // ── Process — runs the plugin's script ───────────────────────────────────
    Process {
        id: pluginProcess
        command: []
        stdout: SplitParser {
            onRead: (line) => functionality.onItemRead(line)
        }
        onExited: functionality.onItemsLoaded()
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
        function searchEscape(): void        { pluginList._mode = "normal"; pluginList.searchEscapePressed() }
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
        // ui only — accumulate one line from the plugin script
        function onItemRead(line: string): void { if (line !== "") pluginList._scriptBuf.push(line) }
        // ui only — plugin chip clicked
        function onPluginChipClicked(name: string): void { pluginList.activatePlugin(name) }
        // ui only — parse buffered lines and populate the item list for the active plugin
        function onItemsLoaded(): void {
            const plugin = pluginList._activePlugin
            const items = []
            for (const line of pluginList._scriptBuf) {
                const parts = line.split("\t")
                if (parts.length < 2) continue
                items.push({
                    label:       parts[0] || "",
                    description: parts[1] || "",
                    icon:        parts[2] || "",
                    callback:    parts[3] || "",
                    id:          parts[4] || parts[0] || ""
                })
            }
            pluginList._scriptBuf = []

            // Store in per-plugin cache
            const mi = {}
            for (const k in pluginList._pluginItems) mi[k] = pluginList._pluginItems[k]
            mi[plugin] = items
            pluginList._pluginItems = mi

            // If still the active plugin, display
            if (pluginList._activePlugin === plugin) {
                pluginList._allItems = items
                impl.runFilter()
                if (pluginList._mode === "insert") searchField.forceActiveFocus()
            }
        }
        // ui only — run the filter (called by debounce timer)
        function runFilter(): void { impl.runFilter() }
        // ui only — clear the pending-G double-tap flag
        function clearPendingG(): void { pluginList._pendingG = false }
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
                visible: pluginList._mode !== "insert"
                width: modeLabel.implicitWidth + 12
                height: 22
                radius: 4
                color: pluginList._mode === "actions" ? "#33" + cfg.color.base0D.slice(1) : cfg.color.base02

                Text {
                    id: modeLabel
                    anchors.centerIn: parent
                    text: pluginList.modeText
                    color: cfg.color.base0D
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize - 3
                    font.bold: true
                }
            }

            TextInput {
                id: searchField
                anchors.fill: parent
                anchors.leftMargin: pluginList._mode !== "insert" ? modeTag.width + 18 : 14
                anchors.rightMargin: 14
                color: pluginList._mode === "actions" ? "transparent" : cfg.color.base05
                font.family: cfg.fontFamily
                font.pixelSize: cfg.fontSize
                clip: true
                verticalAlignment: TextInput.AlignVCenter
                readOnly: pluginList._mode !== "insert"

                Text {
                    anchors.fill: parent
                    visible: !searchField.text && pluginList._mode === "insert"
                    text: pluginList.placeholder
                    color: cfg.color.base03
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize
                    verticalAlignment: Text.AlignVCenter
                }

                // Actions mode: show selected item label in the bar
                Text {
                    anchors.fill: parent
                    anchors.leftMargin: modeTag.width + 8
                    visible: pluginList._mode === "actions" && pluginList.selectedItem !== null
                    text: pluginList.selectedItem ? "Actions \u2014 " + pluginList.selectedItem.label : ""
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

        // Plugin bar ──────────────────────────────────────────────────────────
        Rectangle {
            id: pluginBar
            width: parent.width
            height: 30
            color: "transparent"
            visible: pluginList.pluginNames.length > 0

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Repeater {
                    model: pluginList.pluginNames

                    Rectangle {
                        required property string modelData
                        required property int index
                        width: chipLabel.implicitWidth + 16
                        height: 22
                        radius: 6
                        color: modelData === pluginList._activePlugin ? "#33" + cfg.color.base0D.slice(1) : cfg.color.base02

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: functionality.onPluginChipClicked(modelData)
                        }

                        Text {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: pluginList.pluginLabel(modelData)
                            color: modelData === pluginList._activePlugin ? cfg.color.base0D : cfg.color.base04
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize - 3
                            font.bold: modelData === pluginList._activePlugin
                        }
                    }
                }
            }
        }

        // Item list ───────────────────────────────────────────────────────────
        ListView {
            id: list
            width: parent.width
            height: parent.height - searchBox.height - (pluginBar.visible ? pluginBar.height + parent.spacing : 0) - parent.spacing
            clip: true
            currentIndex: 0
            model: pluginList._filteredItems
            visible: pluginList._mode !== "actions"
            highlightMoveDuration: 0

            onCountChanged: functionality.clampListIndex()

            Text {
                anchors.centerIn: parent
                visible: list.count === 0 && pluginList._mode !== "actions"
                text: pluginList._activePlugin === "" ? "No plugin active"
                    : pluginList._allItems.length === 0 ? "Loading..." : "No results"
                color: cfg.color.base03
                font.family: cfg.fontFamily
                font.pixelSize: cfg.fontSize
            }

            delegate: Item {
                id: itemDelegate
                required property var modelData
                required property int index
                width: list.width
                height: modelData.description !== "" ? 52 : 40

                readonly property bool isCurrent: list.currentIndex === index

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    color: itemDelegate.isCurrent ? cfg.color.base02 : "transparent"
                    radius: 6

                    Item {
                        id: itemIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32
                        height: 32

                        Image {
                            id: itemIconImage
                            anchors.fill: parent
                            source: modelData.icon !== "" ? ("file://" + modelData.icon) : ""
                            fillMode: Image.PreserveAspectFit
                            sourceSize: Qt.size(32, 32)
                            smooth: true
                            visible: status === Image.Ready
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: itemIconImage.status !== Image.Ready
                            color: cfg.color.base02
                            radius: 6

                            Text {
                                anchors.centerIn: parent
                                text: modelData.label.charAt(0).toUpperCase()
                                color: cfg.color.base05
                                font.family: cfg.fontFamily
                                font.pixelSize: 16
                                font.bold: true
                            }
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: itemIcon.right
                        anchors.right: parent.right
                        anchors.leftMargin: 8
                        anchors.rightMargin: 12
                        spacing: 1

                        Text {
                            text: modelData.label
                            color: cfg.color.base05
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            visible: modelData.description !== ""
                            text: modelData.description
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
                        id: itemDelegateFunctionality
                        // ui only
                        function onFlashRequested(idx: int): void {
                            if (pluginList._mode !== "actions" && idx === itemDelegate.index)
                                blinkAnim.restart()
                        }
                    }

                    Connections {
                        target: pluginList
                        function onFlashRequested(idx) { itemDelegateFunctionality.onFlashRequested(idx) }
                    }
                }
            }
        }

        // Actions list ────────────────────────────────────────────────────────
        ListView {
            id: actionList
            width: parent.width
            height: parent.height - searchBox.height - (pluginBar.visible ? pluginBar.height + parent.spacing : 0) - parent.spacing
            clip: true
            currentIndex: 0
            model: pluginList._actions
            visible: pluginList._mode === "actions"
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
                            source: pluginList.selectedItem && pluginList.selectedItem.icon !== ""
                                    ? ("file://" + pluginList.selectedItem.icon) : ""
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
                                text: pluginList.selectedItem ? pluginList.selectedItem.label.charAt(0).toUpperCase() : ""
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
                            if (pluginList._mode === "actions" && idx === actionDelegate.index)
                                actionBlinkAnim.restart()
                        }
                    }

                    Connections {
                        target: pluginList
                        function onFlashRequested(idx) { actionDelegateFunctionality.onFlashRequested(idx) }
                    }
                }
            }
        }
    }
}
