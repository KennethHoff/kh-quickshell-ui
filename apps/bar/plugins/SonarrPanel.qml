// Sonarr integration panel for bar.
// Displays recently grabbed episodes and upcoming releases.
//
// Polls the Sonarr API at a configurable interval while the panel is visible.
// Supports multiple instances via distinct host/port and apiKeyEnv combinations.
//
// Configuration:
//   SonarrPanel {
//       host: "192.168.1.100"
//       port: 8989
//       pollInterval: 120
//       apiKeyEnv: "SONARR_API_KEY"
//       maxHistoryItems: 20
//   }

import QtQuick
import Quickshell
import Quickshell.Io

BarPlugin {
    id: root
    ipcName: "sonarr"
    NixBins { id: bin }

    // ── Properties ─────────────────────────────────────────────────────────
    property string host: "localhost"
    property int port: 8989
    property int pollInterval: 120
    property string apiKeyEnv: "SONARR_API_KEY"
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
    onHostChanged:         functionality.validateConfig()
    onPortChanged:         functionality.validateConfig()
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

        function validateConfig(): void {
            const prev = _state.configError
            let err = ""
            if (!host) {
                err = "host is empty"
            } else if (port < 1 || port > 65535) {
                err = "port " + port + " out of range (1..65535)"
            } else if (pollInterval < 5) {
                err = "pollInterval " + pollInterval + "s below minimum 5s"
            } else if (!apiKeyEnv) {
                err = "apiKeyEnv property not set"
            } else if (!Quickshell.env(apiKeyEnv)) {
                err = apiKeyEnv + " env var is empty or unset"
            }
            _state.configError = err
            // Config just became valid — poll immediately instead of waiting
            // out a full pollInterval for the timer's first tick.
            if (prev !== "" && err === "") poll()
        }

        function getApiKey(): string {
            return Quickshell.env(apiKeyEnv)
        }

        function makeApiCall(endpoint: string): void {
            const url = "http://" + host + ":" + port + "/api/v3/" + endpoint
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
