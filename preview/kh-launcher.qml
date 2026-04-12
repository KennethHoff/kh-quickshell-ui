// Offscreen preview for kh-launcher.
// Run via: nix run .#screenshots
// Renders the launcher panel with mock data and saves a PNG, then quits.
import QtQuick
import QtQuick.Layouts
import "../lib"

Rectangle {
    id: win
    width: 900
    height: 680
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
    LauncherFilter { id: launcherFilter }

    // ── Mock data ────────────────────────────────────────────────────────────
    property string helpFilter: ""
    property string view: "list"
    property var filteredApps: launcherFilter.filterApps([
        { name: "Firefox",            genericName: "Web Browser",     comment: "Browse the World Wide Web",    icon: "", execString: "firefox",    runInTerminal: false, noDisplay: false, actions: [] },
        { name: "Thunderbird",        genericName: "Mail Client",     comment: "Email and calendar client",   icon: "", execString: "thunderbird", runInTerminal: false, noDisplay: false, actions: [{ name: "Compose", icon: "" }, { name: "Contacts", icon: "" }] },
        { name: "Files",              genericName: "File Manager",    comment: "Access and organize files",   icon: "", execString: "nautilus",    runInTerminal: false, noDisplay: false, actions: [] },
        { name: "Terminal",           genericName: "",                comment: "Terminal emulator",           icon: "", execString: "kitty",       runInTerminal: false, noDisplay: false, actions: [] },
        { name: "Settings",           genericName: "System Settings", comment: "Manage system configuration",icon: "", execString: "gnome-control-center", runInTerminal: false, noDisplay: false, actions: [] },
        { name: "Visual Studio Code", genericName: "Text Editor",     comment: "Code editing",               icon: "", execString: "code",        runInTerminal: false, noDisplay: false, actions: [] },
        { name: "Spotify",            genericName: "Music Player",    comment: "Music streaming",            icon: "", execString: "spotify",     runInTerminal: false, noDisplay: false, actions: [] },
    ], "")

    // ── Panel ─────────────────────────────────────────────────────────────────
    Rectangle {
        id: panel
        width: 560
        height: column.y + column.implicitHeight + 8
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 100
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
                    text: "Search applications..."
                    color: cfg.color.base03
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize
                    verticalAlignment: Text.AlignVCenter
                }
            }

            ListView {
                id: resultList
                width: parent.width
                height: Math.min(contentHeight, 400)
                clip: true
                currentIndex: 0
                model: win.filteredApps
                highlightMoveDuration: 0

                delegate: Item {
                    id: delegateRoot
                    required property var modelData
                    required property int index
                    width: resultList.width
                    height: 50

                    readonly property bool isCurrent: resultList.currentIndex === index
                    readonly property bool hasActions: modelData.actions && modelData.actions.length > 0

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        color: delegateRoot.isCurrent ? cfg.color.base02 : "transparent"
                        radius: 6

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                color: cfg.color.base02
                                radius: 4
                            }

                            Column {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: delegateRoot.modelData.name
                                    color: cfg.color.base05
                                    font.family: cfg.fontFamily
                                    font.pixelSize: cfg.fontSize
                                    elide: Text.ElideRight
                                    width: parent.width
                                }

                                Text {
                                    visible: delegateRoot.modelData.comment !== ""
                                    text: delegateRoot.modelData.comment
                                    color: cfg.color.base03
                                    font.family: cfg.fontFamily
                                    font.pixelSize: cfg.fontSize - 2
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }

                            Text {
                                visible: delegateRoot.isCurrent && delegateRoot.hasActions
                                text: "Tab"
                                color: cfg.color.base03
                                font.family: cfg.fontFamily
                                font.pixelSize: cfg.fontSize - 3
                            }
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: 28
                Text {
                    anchors.centerIn: parent
                    text: "Ctrl+1\u20139  workspace  \u00b7  ?  help"
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
            const path = args.length > 1 ? args[args.length - 1] : "/tmp/kh-launcher-preview.png"
            result.saveToFile(path)
            Qt.quit()
        })
    }
}
