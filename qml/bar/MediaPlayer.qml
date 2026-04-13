// Bar plugin: MPRIS media controls.
// Shows track title + artist for the first active player, with
// prev/play-pause/next buttons. Hidden entirely when no player is active.
import QtQuick
import Quickshell.Services.Mpris

BarWidget {
    NixConfig { id: cfg }

    readonly property MprisPlayer player: Mpris.players.length > 0
        ? Mpris.players.get(0) : null
    readonly property bool active: player !== null

    implicitWidth: active ? row.implicitWidth + 16 : 0
    visible: active

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        // ── Prev ───────────────────────────────────────────────────────────
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "⏮"
            color: player && player.canGoPrevious ? cfg.color.base05 : cfg.color.base03
            font.pixelSize: cfg.fontSize
            MouseArea {
                anchors.fill: parent
                onClicked: if (player && player.canGoPrevious) player.previous()
            }
        }

        // ── Play / Pause ───────────────────────────────────────────────────
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: player && player.isPlaying ? "⏸" : "▶"
            color: player && player.canControl ? cfg.color.base05 : cfg.color.base03
            font.pixelSize: cfg.fontSize
            MouseArea {
                anchors.fill: parent
                onClicked: if (player && player.canControl) player.togglePlaying()
            }
        }

        // ── Next ───────────────────────────────────────────────────────────
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "⏭"
            color: player && player.canGoNext ? cfg.color.base05 : cfg.color.base03
            font.pixelSize: cfg.fontSize
            MouseArea {
                anchors.fill: parent
                onClicked: if (player && player.canGoNext) player.next()
            }
        }

        // ── Track info ─────────────────────────────────────────────────────
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: cfg.color.base05
            font.family:    cfg.fontFamily
            font.pixelSize: cfg.fontSize - 1
            text: {
                if (!player) return ""
                const title  = player.trackTitle  || ""
                const artist = player.trackArtist || ""
                if (title && artist) return artist + " — " + title
                if (title)           return title
                if (artist)          return artist
                return player.identity || ""
            }
            elide: Text.ElideRight
            maximumLineCount: 1
            // Cap width so a long track name doesn't push other plugins off screen.
            width: Math.min(implicitWidth, 280)
        }
    }
}
