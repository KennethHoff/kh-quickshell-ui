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

        // ui only — classify a node by media.class + factory into a column
        // bucket. Flow reads physical source → virtual source → bridge →
        // virtual sink → physical sink, matching how audio typically routes
        // through `null-audio-sink`-backed loopbacks.
        //
        // factory.name is the only reliable virtual-sink discriminator —
        // a virtual sink reports media.class "Audio/Sink" same as a
        // physical one, so a media.class-only heuristic would put them
        // in the wrong column.
        function classify(mediaClass: string, factoryName: string): string {
            const virtual = factoryName === "support.null-audio-sink"
                         || mediaClass.indexOf("Virtual") !== -1
            if (virtual) {
                if (mediaClass.indexOf("Source") !== -1) return "virt-source"
                if (mediaClass.indexOf("Sink")   !== -1) return "virt-sink"
            }
            if (mediaClass.indexOf("Stream/Output") === 0) return "source"
            if (mediaClass.indexOf("Stream/Input")  === 0) return "sink"
            if (mediaClass.indexOf("Audio/Source")  === 0) return "source"
            if (mediaClass.indexOf("Video/Source")  === 0) return "source"
            if (mediaClass.indexOf("Audio/Sink")    === 0) return "sink"
            if (mediaClass.indexOf("Video/Sink")    === 0) return "sink"
            return "bridge"
        }

        // ui only — derive mediaType tag from a link's format attrs
        function linkMediaType(info): string {
            const f = info && info.format
            if (f && f.mediaType) return f.mediaType
            return "audio"
        }

        // ui only — subtype splits within a column. Drives the accent
        // colour so a physical microphone (device) reads distinctly from
        // a Firefox stream (stream) even though they share the SOURCES
        // column; the same split applies on the sink side.
        function subtype(mediaClass: string): string {
            if (mediaClass.indexOf("Stream/") === 0) return "stream"
            if (mediaClass.indexOf("Midi")    === 0) return "midi"
            if (mediaClass.indexOf("Video")   === 0) return "video"
            return "device"
        }

        // ui only — parse a pw-dump JSON payload into nodes/links models
        function onStreamFinished(text: string): void {
            let parsed
            try       { parsed = JSON.parse(text) }
            catch (_) { root.nodes = []; root.links = []; return }

            const nodeById = {}
            const nodes    = []
            const links    = []

            // ── Default-node discovery ──
            // PipeWire publishes the configured default sink / source via a
            // Metadata object named "default". The value is JSON whose
            // `.name` matches a node's node.name — `virt-sink-main` for a
            // loopback, `alsa_output.…` for a raw ALSA sink, etc.
            let defaultSinkName   = ""
            let defaultSourceName = ""
            for (const o of parsed) {
                if (o.type !== "PipeWire:Interface:Metadata") continue
                if ((o.props || {})["metadata.name"] !== "default") continue
                for (const entry of (o.metadata || [])) {
                    const v = entry.value || {}
                    if (entry.key === "default.audio.sink")   defaultSinkName   = v.name || ""
                    if (entry.key === "default.audio.source") defaultSourceName = v.name || ""
                }
            }

            // First pass — collect nodes keyed by id
            for (const o of parsed) {
                if (o.type !== "PipeWire:Interface:Node") continue
                const info  = o.info  || {}
                const props = info.props || {}
                const mediaClass = props["media.class"] || ""
                // Skip internal clock / driver nodes with no real ports
                if (!mediaClass) continue
                const nodeName = props["node.name"] || ("node-" + o.id)
                const n = {
                    id:          o.id,
                    name:        nodeName,
                    description: props["node.description"] || props["node.nick"] || nodeName,
                    mediaClass:  mediaClass,
                    nIn:         info["n-input-ports"]  || 0,
                    nOut:        info["n-output-ports"] || 0,
                    kind:        functionality.classify(mediaClass, props["factory.name"] || ""),
                    subtype:     functionality.subtype(mediaClass),
                    isDefault:   (nodeName === defaultSinkName) || (nodeName === defaultSourceName),
                    ports:       [],
                }
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
                const order = { source: 0, "virt-source": 1, bridge: 2, "virt-sink": 3, sink: 4 }
                const da = order[a.kind] ?? 2
                const db = order[b.kind] ?? 2
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
