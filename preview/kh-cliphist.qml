// Offscreen preview for kh-cliphist.
// Run via: nix run .#screenshots
// Renders the cliphist panel with mock data and saves a PNG, then quits.
import QtQuick
import QtQuick.Layouts
import "../lib"

Rectangle {
    id: win
    width: 1100
    height: 720
    color: "#99000000"

    // ── Stub config ──────────────────────────────────────────────────────────
    QtObject {
        id: cfg
        property string fontFamily: "sans-serif"
        property int    fontSize:   14
        property QtObject color: QtObject {
            property string base00: "#1e1e2e"
            property string base01: "#181825"
            property string base02: "#313244"
            property string base03: "#45475a"
            property string base04: "#585b70"
            property string base05: "#cdd6f4"
            property string base06: "#f5c2e7"
            property string base07: "#b4befe"
            property string base08: "#f38ba8"
            property string base09: "#fab387"
            property string base0A: "#f9e2af"
            property string base0B: "#a6e3a1"
            property string base0C: "#94e2d5"
            property string base0D: "#89b4fa"
            property string base0E: "#cba6f7"
            property string base0F: "#f2cdcd"
        }
    }

    // ── Lib ──────────────────────────────────────────────────────────────────
    CliphistEntry { id: clipEntry }
    FormatBytes   { id: fmtBytes }
    TextStats     { id: textStats }

    // ── Mock data ────────────────────────────────────────────────────────────
    property string view: "list"
    property var allEntries: [
        "1\tHello, world! This is a clipboard entry.",
        "2\tfunction fuzzyScore(needle, haystack) {\n    let ni = 0, score = 0\n    for (let hi = 0; hi < haystack.length; hi++) {",
        "3\t[[binary data 0x1234 image/png]]",
        "4\thttps://github.com/anthropics/claude-code/issues/1234",
        "5\tNix is a purely functional package manager. This means that it treats packages like values in purely functional programming languages such as Haskell.",
        "6\tsudo systemctl restart nginx",
        "7\t[[binary data 0x5678 image/jpeg]]",
        "8\tconst result = await fetch('/api/data').then(r => r.json())",
    ]

    property int selectedIndex: 1
    readonly property string selectedEntry: allEntries[selectedIndex] || ""
    readonly property string selectedPreview: clipEntry.entryPreview(selectedEntry)
    readonly property bool   selectedIsImage: selectedPreview.startsWith("[[")
    readonly property string detailText: selectedPreview

    // ── Panel ─────────────────────────────────────────────────────────────────
    Rectangle {
        id: panel
        width: parent.width * 0.7
        height: parent.height * 0.7
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.06
        color: cfg.color.base00
        radius: 12
        clip: true

        Column {
            id: column
            x: 8; y: 8
            width: parent.width - 16
            spacing: 4

            Rectangle {
                width: parent.width
                height: 44
                color: cfg.color.base01
                radius: 8
                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    text: "Search clipboard... (img: text:)"
                    color: cfg.color.base03
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize
                    verticalAlignment: Text.AlignVCenter
                }
            }

            RowLayout {
                width: parent.width
                height: panel.height - 44 - footerHint.height - column.spacing * 2 - 16
                spacing: 4

                // Entry list
                Item {
                    Layout.preferredWidth: parent.width * 0.45
                    Layout.fillHeight: true

                    ListView {
                        id: resultList
                        anchors.fill: parent
                        clip: true
                        currentIndex: win.selectedIndex
                        model: win.allEntries
                        highlightMoveDuration: 0

                        delegate: Item {
                            id: delegateRoot
                            required property var modelData
                            required property int index
                            width: resultList.width
                            height: clipEntry.entryPreview(modelData).startsWith("[[") ? 64 : 40

                            readonly property bool isCurrent: resultList.currentIndex === index
                            readonly property string preview: clipEntry.entryPreview(modelData)
                            readonly property bool   isImage: preview.startsWith("[[")

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 2
                                color: delegateRoot.isCurrent ? cfg.color.base02 : "transparent"
                                radius: 6

                                Rectangle {
                                    visible: delegateRoot.isImage
                                    width: 90
                                    anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: 4 }
                                    color: cfg.color.base02
                                    radius: 4
                                    Text {
                                        anchors.centerIn: parent
                                        text: "IMG"
                                        color: cfg.color.base04
                                        font.pixelSize: cfg.fontSize - 3
                                    }
                                }

                                Text {
                                    visible: !delegateRoot.isImage
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    text: delegateRoot.preview
                                    color: cfg.color.base05
                                    font.family: cfg.fontFamily
                                    font.pixelSize: cfg.fontSize
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    color: cfg.color.base02
                }

                // Detail panel
                Column {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8
                    topPadding: 10
                    leftPadding: 10
                    rightPadding: 10

                    Text {
                        width: parent.width - 20
                        height: parent.height - detailStats.height - 28
                        text: win.detailText
                        color: cfg.color.base05
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize - 1
                        wrapMode: Text.Wrap
                        clip: true
                    }

                    Text {
                        id: detailStats
                        width: parent.width - 20
                        text: textStats.buildTextStats(win.detailText, true)
                        color: cfg.color.base03
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize - 3
                    }
                }
            }

            Item {
                id: footerHint
                width: parent.width
                height: 28
                Text {
                    anchors.centerIn: parent
                    text: "Tab  preview  \u00b7  ?  help"
                    color: cfg.color.base03
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize - 3
                }
            }
        }
    }

    // ── Screenshot ───────────────────────────────────────────────────────────
    Timer {
        interval: 100
        running: true
        repeat: false
        onTriggered: win.grabToImage(result => {
            const args = Qt.application.arguments
            const path = args.length > 1 ? args[args.length - 1] : "/tmp/kh-cliphist-preview.png"
            result.saveToFile(path)
            Qt.quit()
        })
    }
}
