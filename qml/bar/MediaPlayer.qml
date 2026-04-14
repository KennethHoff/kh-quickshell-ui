// Bar plugin: MPRIS media controls.
// Shows track title + artist for the first active player, with
// prev/play-pause/next buttons. Hidden entirely when no player is active.
import QtQuick
import Quickshell.Io
import Quickshell.Services.Mpris

BarWidget {
    NixConfig { id: cfg }

    // State in a QtObject so its id is globally accessible from nested children.
    QtObject {
        id: state
        readonly property var  player: Mpris.players.values[0] ?? null
        readonly property bool active: player !== null
    }

    function core_prev(): void          { if (state.active && state.player.canGoPrevious) state.player.previous() }
    function core_togglePlaying(): void { if (state.active && state.player.canControl)   state.player.togglePlaying() }
    function core_next(): void          { if (state.active && state.player.canGoNext)     state.player.next() }
    function core_play(): void          { if (state.active && !state.player.isPlaying)   core_togglePlaying() }
    function core_pause(): void         { if (state.active && state.player.isPlaying)    core_togglePlaying() }

    IpcHandler {
        target: "bar.media"

        function isActive(): bool    { return state.active }
        function isPlaying(): bool   { return state.active && state.player.isPlaying }
        function getTitle(): string  { return state.active ? (state.player.trackTitle  || "") : "" }
        function getArtist(): string { return state.active ? (state.player.trackArtist || "") : "" }
        function togglePlaying(): void { core_togglePlaying() }
        function play(): void          { core_play() }
        function pause(): void         { core_pause() }
        function next(): void          { core_next() }
        function prev(): void          { core_prev() }
    }

    implicitWidth: state.active ? row.implicitWidth + 16 : 0
    visible: state.active

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        // ── Prev ───────────────────────────────────────────────────────────
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "⏮"
            color: state.player && state.player.canGoPrevious ? cfg.color.base05 : cfg.color.base03
            font.pixelSize: cfg.fontSize
            MouseArea {
                anchors.fill: parent
                onClicked: core_prev()
            }
        }

        // ── Play / Pause ───────────────────────────────────────────────────
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: state.player && state.player.isPlaying ? "⏸" : "▶"
            color: state.player && state.player.canControl ? cfg.color.base05 : cfg.color.base03
            font.pixelSize: cfg.fontSize
            MouseArea {
                anchors.fill: parent
                onClicked: core_togglePlaying()
            }
        }

        // ── Next ───────────────────────────────────────────────────────────
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "⏭"
            color: state.player && state.player.canGoNext ? cfg.color.base05 : cfg.color.base03
            font.pixelSize: cfg.fontSize
            MouseArea {
                anchors.fill: parent
                onClicked: core_next()
            }
        }

        // ── Track info ─────────────────────────────────────────────────────
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: cfg.color.base05
            font.family:    cfg.fontFamily
            font.pixelSize: cfg.fontSize - 1
            text: {
                if (!state.player) return ""
                const title  = state.player.trackTitle  || ""
                const artist = state.player.trackArtist || ""
                if (title && artist) return artist + " — " + title
                if (title)           return title
                if (artist)          return artist
                return state.player.identity || ""
            }
            elide: Text.ElideRight
            maximumLineCount: 1
            // Cap width so a long track name doesn't push other plugins off screen.
            width: Math.min(implicitWidth, 280)
        }
    }
}
