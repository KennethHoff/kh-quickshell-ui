// PipeWire graph data source.
//
// Shells out to `pw-dump` on a timer while `active` and re-parses the output
// into normalised node / link models consumed by PatchbayCanvas. Kept
// presentation-free — the only consumers of these properties are renderers.
//
// Live registry events (Core [4]) will replace polling with a `pw-mon`
// subscription once the renderer is stable; until then a short interval
// is close enough that the graph feels responsive.
import QtQuick
import Quickshell.Io

Item {
    id: root

    NixBins { id: bin }

    property bool active: false
    property int  interval: 2000

    // ── Models ────────────────────────────────────────────────────────────────
    // nodes: [{ id, name, description, mediaClass, kind, ports: [{ id, direction, name }] }]
    // links: [{ id, srcNodeId, srcPortId, dstNodeId, dstPortId, mediaType, state }]
    property var nodes: []
    property var links: []

    function refresh(): void { functionality.poll() }

    // ── Functionality ─────────────────────────────────────────────────────────
    QtObject {
        id: functionality

        // ui only — kick off a new pw-dump if one is not already in flight
        function poll(): void { if (!_proc.running) _proc.running = true }

        // ui only — classify a node via its port counts: anything with
        // only outputs is a source, only inputs is a sink, both is a bridge.
        function classify(nIn: int, nOut: int): string {
            if (nIn  > 0 && nOut === 0) return "sink"
            if (nOut > 0 && nIn  === 0) return "source"
            return "bridge"
        }

        // ui only — derive mediaType tag from a link's format attrs
        function linkMediaType(info): string {
            const f = info && info.format
            if (f && f.mediaType) return f.mediaType
            return "audio"
        }

        // ui only — parse a pw-dump JSON payload into nodes/links models
        function onStreamFinished(text: string): void {
            let parsed
            try       { parsed = JSON.parse(text) }
            catch (_) { root.nodes = []; root.links = []; return }

            const nodeById = {}
            const nodes    = []
            const links    = []

            // First pass — collect nodes keyed by id
            for (const o of parsed) {
                if (o.type !== "PipeWire:Interface:Node") continue
                const info  = o.info  || {}
                const props = info.props || {}
                const mediaClass = props["media.class"] || ""
                // Skip internal clock / driver nodes with no real ports
                if (!mediaClass) continue
                const n = {
                    id:          o.id,
                    name:        props["node.name"] || ("node-" + o.id),
                    description: props["node.description"] || props["node.nick"] || props["node.name"] || "",
                    mediaClass:  mediaClass,
                    nIn:         info["n-input-ports"]  || 0,
                    nOut:        info["n-output-ports"] || 0,
                    kind:        "bridge",
                    ports:       [],
                }
                n.kind = functionality.classify(n.nIn, n.nOut)
                nodeById[o.id] = n
                nodes.push(n)
            }

            // Second pass — attach ports to their owning nodes
            for (const o of parsed) {
                if (o.type !== "PipeWire:Interface:Port") continue
                const info  = o.info  || {}
                const props = info.props || {}
                const nodeId = props["node.id"]
                const n = nodeById[nodeId]
                if (!n) continue
                n.ports.push({
                    id:        o.id,
                    direction: info.direction || props["port.direction"] || "",
                    name:      props["port.name"]  || "",
                    alias:     props["port.alias"] || "",
                    channel:   props["audio.channel"] || "",
                })
            }

            // Third pass — collect links
            for (const o of parsed) {
                if (o.type !== "PipeWire:Interface:Link") continue
                const info = o.info || {}
                links.push({
                    id:        o.id,
                    srcNodeId: info["output-node-id"],
                    srcPortId: info["output-port-id"],
                    dstNodeId: info["input-node-id"],
                    dstPortId: info["input-port-id"],
                    mediaType: functionality.linkMediaType(info),
                    state:     info.state || "",
                })
            }

            // Sort ports inside each node: inputs first, then outputs, by name
            for (const n of nodes) {
                n.ports.sort((a, b) => {
                    if (a.direction !== b.direction)
                        return a.direction === "input" ? -1 : 1
                    return a.name.localeCompare(b.name)
                })
            }

            // Sort nodes by kind then name for stable rendering
            nodes.sort((a, b) => {
                const order = { source: 0, bridge: 1, sink: 2 }
                const da = order[a.kind] ?? 1
                const db = order[b.kind] ?? 1
                if (da !== db) return da - db
                return a.name.localeCompare(b.name)
            })

            root.nodes = nodes
            root.links = links
        }
    }

    // ── Process ───────────────────────────────────────────────────────────────
    Process {
        id: _proc
        command: [bin.pwDump]
        stdout: StdioCollector {
            onStreamFinished: functionality.onStreamFinished(text)
        }
    }

    // ── Poll timer — only while active ────────────────────────────────────────
    Timer {
        interval: root.interval
        running:  root.active
        repeat:   true
        triggeredOnStart: true
        onTriggered: functionality.poll()
    }
}
