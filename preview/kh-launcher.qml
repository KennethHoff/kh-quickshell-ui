// Offscreen preview for kh-launcher.
// Run via: nix run .#screenshots
// Usage: qml ... preview/kh-launcher.qml -- <outpath> [list|help|actions]
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
            property string base0D: "#89b4fa"
        }
    }

    // ── Lib ──────────────────────────────────────────────────────────────────
    LauncherFilter { id: launcherFilter }

    // ── State from CLI args ──────────────────────────────────────────────────
    property string view: {
        const args = Qt.application.arguments
        const i = args.indexOf("--")
        return (i >= 0 && args.length > i + 2) ? args[i + 2] : "list"
    }
    property string helpFilter: ""
    property int    actionIndex: 0
    property var    actionEntry: mockApps[1]  // Thunderbird (has actions)

    // ── Mock data ────────────────────────────────────────────────────────────
    property var mockApps: [
        { name: "Firefox",            genericName: "Web Browser",     comment: "Browse the World Wide Web",    icon: "", execString: "firefox",    runInTerminal: false, noDisplay: false, actions: [] },
        { name: "Thunderbird",        genericName: "Mail Client",     comment: "Email and calendar client",   icon: "", execString: "thunderbird", runInTerminal: false, noDisplay: false, actions: [{ name: "Compose New Message", icon: "" }, { name: "Open Address Book", icon: "" }] },
        { name: "Files",              genericName: "File Manager",    comment: "Access and organize files",   icon: "", execString: "nautilus",    runInTerminal: false, noDisplay: false, actions: [] },
        { name: "Terminal",           genericName: "",                comment: "Terminal emulator",           icon: "", execString: "kitty",       runInTerminal: false, noDisplay: false, actions: [] },
        { name: "Settings",           genericName: "System Settings", comment: "Manage system configuration",icon: "", execString: "gnome-control-center", runInTerminal: false, noDisplay: false, actions: [] },
        { name: "Visual Studio Code", genericName: "Text Editor",     comment: "Code editing",               icon: "", execString: "code",        runInTerminal: false, noDisplay: false, actions: [] },
        { name: "Spotify",            genericName: "Music Player",    comment: "Music streaming",            icon: "", execString: "spotify",     runInTerminal: false, noDisplay: false, actions: [] },
    ]
    property var filteredApps: launcherFilter.filterApps(mockApps, "")

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

            // Search box ──────────────────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: 44
                color: cfg.color.base01
                radius: 8

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    visible: win.view !== "actions"
                    text: win.view === "help"
                        ? (win.helpFilter ? win.helpFilter : "Filter shortcuts...")
                        : "Search applications..."
                    color: cfg.color.base03
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize
                    verticalAlignment: Text.AlignVCenter
                }

                // Action breadcrumb
                RowLayout {
                    visible: win.view === "actions"
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 22; Layout.preferredHeight: 22
                        color: cfg.color.base02; radius: 4
                    }
                    Text {
                        Layout.fillWidth: true
                        text: win.actionEntry ? win.actionEntry.name : ""
                        color: cfg.color.base05
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize
                    }
                    Text {
                        text: "Tab / Esc \u2190 back"
                        color: cfg.color.base03
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize - 3
                    }
                }
            }

            // App list ────────────────────────────────────────────────────────
            ListView {
                id: resultList
                width: parent.width
                height: Math.min(contentHeight, 400)
                visible: win.view === "list"
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
                        anchors.fill: parent; anchors.margins: 2
                        color: delegateRoot.isCurrent ? cfg.color.base02 : "transparent"
                        radius: 6

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8; anchors.rightMargin: 8
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 28; Layout.preferredHeight: 28
                                color: cfg.color.base02; radius: 4
                            }
                            Column {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    text: delegateRoot.modelData.name
                                    color: cfg.color.base05
                                    font.family: cfg.fontFamily; font.pixelSize: cfg.fontSize
                                    elide: Text.ElideRight; width: parent.width
                                }
                                Text {
                                    visible: delegateRoot.modelData.comment !== ""
                                    text: delegateRoot.modelData.comment
                                    color: cfg.color.base03
                                    font.family: cfg.fontFamily; font.pixelSize: cfg.fontSize - 2
                                    elide: Text.ElideRight; width: parent.width
                                }
                            }
                            Text {
                                visible: delegateRoot.isCurrent && delegateRoot.hasActions
                                text: "Tab"
                                color: cfg.color.base03
                                font.family: cfg.fontFamily; font.pixelSize: cfg.fontSize - 3
                            }
                        }
                    }
                }
            }

            // Help overlay ────────────────────────────────────────────────────
            Column {
                id: helpContent
                visible: win.view === "help"
                width: parent.width
                spacing: 0; topPadding: 4; bottomPadding: 4

                component ShortcutRow: Row {
                    property string shortcut: ""
                    property string description: ""
                    width: helpContent.width; height: 26
                    visible: {
                        const f = win.helpFilter.toLowerCase()
                        if (!f) return true
                        return shortcut.toLowerCase().includes(f) || description.toLowerCase().includes(f)
                    }
                    Text {
                        width: 130; text: shortcut
                        color: cfg.color.base03; font.family: cfg.fontFamily; font.pixelSize: cfg.fontSize - 1
                        horizontalAlignment: Text.AlignRight
                    }
                    Item { width: 14; height: 1 }
                    Text {
                        text: description
                        color: cfg.color.base05; font.family: cfg.fontFamily; font.pixelSize: cfg.fontSize - 1
                    }
                }

                component SectionLabel: Text {
                    width: helpContent.width; visible: !win.helpFilter
                    color: cfg.color.base03; font.family: cfg.fontFamily; font.pixelSize: cfg.fontSize - 3
                    topPadding: 8; bottomPadding: 4
                }

                SectionLabel { text: "App mode" }
                ShortcutRow { shortcut: "\u2191 / \u2193"; description: "Navigate" }
                ShortcutRow { shortcut: "Enter";           description: "Launch" }
                ShortcutRow { shortcut: "Esc";             description: "Close" }
                ShortcutRow { shortcut: "Tab";             description: "Open actions" }
                ShortcutRow { shortcut: "Ctrl+1\u20139";   description: "Launch to workspace" }
                ShortcutRow { shortcut: "?";               description: "Toggle this help" }

                SectionLabel { text: "Action mode  (Tab to enter)" }
                ShortcutRow { shortcut: "\u2191 / \u2193"; description: "Navigate actions" }
                ShortcutRow { shortcut: "Enter";           description: "Launch action" }
                ShortcutRow { shortcut: "Tab / Esc";       description: "Back to app list" }

                Item { width: 1; height: 4 }
            }

            // Footer ──────────────────────────────────────────────────────────
            Item {
                width: parent.width; height: 28
                visible: win.view === "list"
                Text {
                    anchors.centerIn: parent
                    text: "Ctrl+1\u20139  workspace  \u00b7  ?  help"
                    color: cfg.color.base03; font.family: cfg.fontFamily; font.pixelSize: cfg.fontSize - 3
                }
            }

            // Action list ─────────────────────────────────────────────────────
            ListView {
                id: actionList
                width: parent.width
                height: Math.min(contentHeight, 300)
                visible: win.view === "actions"
                clip: true
                currentIndex: win.actionIndex
                model: win.view === "actions" && win.actionEntry ? win.actionEntry.actions : []
                highlightMoveDuration: 0

                delegate: Item {
                    id: actionDelegate
                    required property var modelData
                    required property int index
                    width: actionList.width; height: 44

                    readonly property bool isCurrent: win.actionIndex === index

                    Rectangle {
                        anchors.fill: parent; anchors.margins: 2
                        color: actionDelegate.isCurrent ? cfg.color.base02 : "transparent"
                        radius: 6

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8; anchors.rightMargin: 8
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 28; Layout.preferredHeight: 28
                                color: cfg.color.base02; radius: 4
                            }
                            Text {
                                Layout.fillWidth: true
                                text: actionDelegate.modelData.name
                                color: cfg.color.base05
                                font.family: cfg.fontFamily; font.pixelSize: cfg.fontSize
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Screenshot ───────────────────────────────────────────────────────────
    Timer {
        interval: 100; running: true; repeat: false
        onTriggered: win.grabToImage(result => {
            const args = Qt.application.arguments
            const i = args.indexOf("--")
            const path = i >= 0 ? args[i + 1] : "/tmp/kh-launcher-preview.png"
            result.saveToFile(path)
            Qt.quit()
        })
    }
}
