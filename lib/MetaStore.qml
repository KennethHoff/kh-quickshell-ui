// Generic id→value metadata store.
//
// Manages one file under $XDG_DATA_HOME/<appName>/meta/<storeKey>.
// File format: id<TAB>value<LF> per line.
//
// Usage:
//   MetaStore {
//       id:       myStore
//       bash:     bin.bash
//       appName:  "kh-cliphist"
//       storeKey: "attribution"
//       onLoaded: doSomethingWithMyStore.values
//   }
//   Component.onCompleted: myStore.load()
//
// API:
//   load()                        — resolve path + read file; emits loaded() when done
//   set(id, val)                  — add/update one entry, persist
//   remove(id)                    — remove one entry, persist
//   removeMany(idsSet)            — remove a Set of IDs, persist if changed
//   prune(knownIdsObj)            — drop stale IDs (not in knownIdsObj), persist if changed
//   pruneAndFill(knownIds, dflt)  — prune stale + add missing IDs with dflt value
import QtQuick
import Quickshell.Io

Item {
    id: store

    property string bash:     ""   // path to bash binary; set before calling load()
    property string appName:  ""   // subdir under $XDG_DATA_HOME; set before calling load()
    property string storeKey: ""   // filename under meta/; set before calling load()
    property var    values:   ({}) // live id → value map (reassign to notify bindings)

    signal loaded()   // emitted once after the initial file read completes

    // ── Public API ─────────────────────────────────────────────────────────────
    function load() {
        if (!bash || !appName || !storeKey) return
        pathProcess.running = true
    }

    function set(id, val) {
        values = Object.assign({}, values, { [id]: val })
        impl.write()
    }

    function remove(id) {
        if (!(id in values)) return
        const v = Object.assign({}, values)
        delete v[id]
        values = v
        impl.write()
    }

    function removeMany(idsSet) {
        let changed = false
        const v = Object.assign({}, values)
        for (const id of idsSet) {
            if (id in v) { delete v[id]; changed = true }
        }
        if (changed) { values = v; impl.write() }
    }

    function prune(knownIdsObj) {
        let changed = false
        const v = {}
        for (const [id, val] of Object.entries(values)) {
            if (id in knownIdsObj) v[id] = val
            else changed = true
        }
        if (changed) { values = v; impl.write() }
    }

    // Prune stale IDs, and add knownIdsObj entries that have no value yet.
    function pruneAndFill(knownIdsObj, defaultVal) {
        let changed = false
        const v = {}
        for (const [id, val] of Object.entries(values)) {
            if (id in knownIdsObj) v[id] = val
            else changed = true
        }
        for (const id of Object.keys(knownIdsObj)) {
            if (!(id in v)) { v[id] = defaultVal; changed = true }
        }
        if (changed) { values = v; impl.write() }
    }

    // ── Private ────────────────────────────────────────────────────────────────
    property string _path: ""
    property var    _buf:  []

    QtObject {
        id: functionality

        // ui only
        function onPathRead(line: string): void { if (line) store._path = line }
        // ui only
        function onPathExited(): void { if (store._path) readProcess.running = true }
        // ui only
        function onDataRead(line: string): void { if (line) store._buf.push(line) }
        // ui only
        function onDataExited(): void {
            const v = {}
            for (const line of store._buf) {
                const tab = line.indexOf("\t")
                if (tab > 0)
                    v[line.substring(0, tab)] = line.substring(tab + 1)
            }
            store.values = v
            store._buf   = []
            store.loaded()
        }
    }

    QtObject {
        id: impl
        function write(): void {
            if (!store._path || !store.bash) return
            const pairs = []
            for (const [id, val] of Object.entries(store.values)) pairs.push(id, val)
            writeProcess.command = [store.bash, "-c",
                'f="$1"; shift; { while [[ $# -ge 2 ]]; do printf "%s\\t%s\\n" "$1" "$2"; shift 2; done; } > "$f"',
                "--", store._path].concat(pairs)
            writeProcess.running = true
        }
    }

    Process {
        id: pathProcess
        command: [store.bash, "-c",
            'f="${XDG_DATA_HOME:-$HOME/.local/share}/' + store.appName + '/meta/' + store.storeKey + '"' +
            '; mkdir -p "$(dirname "$f")"' +
            '; printf "%s\\n" "$f"']
        stdout: SplitParser {
            onRead: (line) => functionality.onPathRead(line)
        }
        onExited: functionality.onPathExited()
    }

    Process {
        id: readProcess
        command: [store.bash, "-c", '[ -f "$1" ] && cat "$1" || true', "--", store._path]
        stdout: SplitParser {
            onRead: (line) => functionality.onDataRead(line)
        }
        onExited: functionality.onDataExited()
    }

    Process { id: writeProcess }
}
