// Sonarr integration panel for bar.
// Displays recently grabbed episodes and upcoming releases.
//
// Polls the Sonarr API at a configurable interval while the panel is visible.
// Supports multiple instances via distinct baseUrl and apiKeyEnv combinations.
// Supports both HTTP and HTTPS.
//
// Configuration:
//   SonarrPanel {
//       baseUrl: "http://sonarr:8989"  // or "https://sonarr.example.com" or "http://192.168.1.100:8989"
//       apiKeyEnv: "SONARR_API_KEY"
//       pollInterval: 120  // optional, defaults to 120 seconds
//       maxHistoryItems: 20  // optional, defaults to 20
//   }

import QtQuick
import Quickshell
import Quickshell.Io

BarPlugin {
    id: root
    ipcName: "sonarr"
    NixBins { id: bin }

    // ── Properties ─────────────────────────────────────────────────────────
    required property string baseUrl
    required property string apiKeyEnv
    property int pollInterval: 120
    property int maxHistoryItems: 20

    // ── Sizing ─────────────────────────────────────────────────────────────
    implicitWidth:  _row.implicitWidth + 16

    // ── State ──────────────────────────────────────────────────────────────
    QtObject {
        id: _state
        property int newCount: 0
        property var recentGrabs: []
        property bool loading: false
        property string error: ""
        // Populated by functionality.validateConfig(); non-empty means the plugin
        // is misconfigured and must not poll. Separate from `error` (which
        // captures runtime/API failures) so a property change that fixes the
        // config doesn't silently clobber a legitimate runtime error.
        property string configError: ""
    }

    readonly property alias newCount: _state.newCount
    readonly property alias recentGrabs: _state.recentGrabs
    readonly property alias loading: _state.loading
    readonly property alias error: _state.error
    readonly property alias configError: _state.configError
    readonly property bool hasError: _state.configError !== "" || _state.error !== ""

    // ── IPC ────────────────────────────────────────────────────────────────
    IpcHandler {
        target: ipcPrefix
        function getNewCount(): int { return _state.newCount }
        function getRecentGrabs(): var { return _state.recentGrabs }
        function getError(): string { return _state.configError || _state.error }
        function getConfigError(): string { return _state.configError }
    }

    // ── Config validation ──────────────────────────────────────────────────
    onBaseUrlChanged:      functionality.validateConfig()
    onPollIntervalChanged: functionality.validateConfig()
    onApiKeyEnvChanged:    functionality.validateConfig()

    // ── Badge visuals ──────────────────────────────────────────────────────
    NixConfig { id: _cfg }

    Row {
        id: _row
        anchors.centerIn: parent
        spacing: 4

        BarIcon {
            id: _icon
            anchors.verticalCenter: parent.verticalCenter
            glyph: "\u{F0839}" // mdi-television
            color: root.hasError
                       ? _cfg.color.base08
                       : _state.newCount > 0 ? _cfg.color.base0B
                                             : _cfg.color.base03
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: _state.newCount > 0 || root.hasError
            text: root.hasError ? "!" : _state.newCount.toString()
            color: root.hasError ? _cfg.color.base08 : _cfg.color.base0B
            font.family:    _cfg.fontFamily
            font.pixelSize: _cfg.fontSize - 2
        }
    }

    BarTooltip {
        active:  root.hasError
        ipcName: "error"
        Column {
            id: _errCol
            spacing: 6
            Repeater {
                model: (_state.configError || _state.error).split("\n").filter(s => s.length > 0)
                delegate: Column {
                    id: _errRow
                    spacing: 6
                    BarHorizontalDivider {
                        visible:      index > 0
                        dividerColor: _cfg.color.base04
                        width:        _errCol.width * 0.9
                        x:            (_errRow.width - width) / 2
                    }
                    BarText { text: modelData; color: errorColor }
                }
            }
        }
    }

    SequentialAnimation on opacity {
        running: _state.loading
        loops:   Animation.Infinite
        NumberAnimation { to: 0.45; duration: 500; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0;  duration: 500; easing.type: Easing.InOutSine }
        onStopped: root.opacity = 1.0
    }

    // ── Logic ──────────────────────────────────────────────────────────────
    QtObject {
        id: functionality

        function normalizeBaseUrl(url: string): string {
            if (!url) return url
            // Add default port if missing
            if (!/:\d+$/.test(url)) {
                if (url.startsWith("https://")) return url + ":443"
                if (url.startsWith("http://")) return url + ":80"
            }
            return url
        }

        function validateConfig(): void {
            const prev = _state.configError
            const errs = []
            if (!baseUrl) errs.push("baseUrl is empty")
            else if (!/^https?:\/\/.+/.test(baseUrl)) errs.push("baseUrl must start with http:// or https://")
            if (pollInterval < 5) errs.push("pollInterval " + pollInterval + "s below minimum 5s")
            if (!apiKeyEnv) errs.push("apiKeyEnv property not set")
            // Only check env var resolution if apiKeyEnv is set — otherwise the
            // "env var is empty" message is a duplicate of the previous line.
            else if (!Quickshell.env(apiKeyEnv)) errs.push(apiKeyEnv + " env var is empty or unset")
            _state.configError = errs.join("\n")
            // Config just became valid — poll immediately instead of waiting
            // out a full pollInterval for the timer's first tick.
            if (prev !== "" && _state.configError === "") poll()
        }

        function getApiKey(): string {
            return Quickshell.env(apiKeyEnv)
        }

        function makeApiCall(endpoint: string): void {
            const url = normalizeBaseUrl(baseUrl) + "/api/v3/" + endpoint
            _proc.command = [
                bin.bash, "-c",
                bin.curl + " -s -H 'X-Api-Key: " + getApiKey() + "' '" + url + "' | " + bin.jq + " ."
            ]
            _state.loading = true
            _state.error = ""
            _proc.running = true
        }

        function onStreamFinished(text: string): void {
            _state.loading = false

            if (!text || text.length === 0) {
                _state.error = "Empty response"
                return
            }

            try {
                const data = JSON.parse(text)

                // Check if it's an error response
                if (data.error !== undefined) {
                    _state.error = data.message || "API error"
                    _state.newCount = 0
                    _state.recentGrabs = []
                    return
                }

                // For queue endpoint: count new items
                if (Array.isArray(data)) {
                    _state.newCount = data.length
                    _state.recentGrabs = data
                        .slice(0, maxHistoryItems)
                        .map(item => ({
                            series: item.series?.title ?? "",
                            season: item.seasonNumber ?? 0,
                            episode: item.episodeNumber ?? 0,
                            title: item.title ?? "",
                            timestamp: item.date ?? ""
                        }))
                    _state.error = ""
                } else {
                    _state.error = "Unexpected response format"
                    _state.newCount = 0
                    _state.recentGrabs = []
                }
            } catch (e) {
                _state.error = "Parse error"
                _state.newCount = 0
                _state.recentGrabs = []
            }
        }

        function poll(): void {
            if (_state.configError !== "") return
            if (!_proc.running) {
                makeApiCall("queue")
            }
        }

        // ui only
        function onProcExited(): void { _state.loading = false }
    }

    Process {
        id: _proc
        stdout: StdioCollector {
            onStreamFinished: functionality.onStreamFinished(text)
        }
        onExited: functionality.onProcExited()
    }

    Timer {
        id: _timer
        interval: pollInterval * 1000
        running: root.contentVisible && _state.configError === ""
        repeat: true
        onTriggered: functionality.poll()
    }

    Component.onCompleted: {
        functionality.validateConfig()
        functionality.poll()
    }
}
