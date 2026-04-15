// Bar plugin: MPRIS media controls.
// Shows track title + artist for the first active player, with
// prev/play-pause/next buttons. Hidden entirely when no player is active.
import QtQuick
import Quickshell.Io
import Quickshell.Services.Mpris

BarPlugin {
    NixConfig { id: cfg }

    // State in a QtObject so its id is globally accessible from nested children.
    QtObject {
        id: state
        readonly property var  player: Mpris.players.values[0] ?? null
        readonly property bool active: player !== null
    }

    QtObject {
        id: functionality

        // ui+ipc
        function prev(): void          { if (state.active && state.player.canGoPrevious) state.player.previous() }
        // ui+ipc
        function togglePlaying(): void { if (state.active && state.player.canControl)   state.player.togglePlaying() }
        // ui+ipc
        function next(): void          { if (state.active && state.player.canGoNext)     state.player.next() }
        // ipc only
        function play(): void          { if (state.active && !state.player.isPlaying)   togglePlaying() }
        // ipc only
        function pause(): void         { if (state.active && state.player.isPlaying)    togglePlaying() }
        // ipc only
        function isPlaying(): bool     { return state.active && state.player.isPlaying }
        // ipc only
        function getTitle(): string    { return state.active ? (state.player.trackTitle  || "") : "" }
        // ipc only
        function getArtist(): string   { return state.active ? (state.player.trackArtist || "") : "" }
    }

    IpcHandler {
        target: ipcPrefix + ".media"

        function isActive(): bool      { return state.active }
        function isPlaying(): bool     { return functionality.isPlaying() }
        function getTitle(): string    { return functionality.getTitle() }
        function getArtist(): string   { return functionality.getArtist() }
        function togglePlaying(): void { functionality.togglePlaying() }
        function play(): void          { functionality.play() }
        function pause(): void         { functionality.pause() }
        function next(): void          { functionality.next() }
        function prev(): void          { functionality.prev() }
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
                onClicked: functionality.prev()
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
                onClicked: functionality.togglePlaying()
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
                onClicked: functionality.next()
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
