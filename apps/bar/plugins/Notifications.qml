// Bar plugin: notification bell.
// Visible only when there are unread notifications. Hidden when count is zero.
import QtQuick
import Quickshell.Services.Notifications

BarPlugin {
    NixConfig { id: cfg }

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: false
        bodyMarkupSupported: false
        bodySupported: true
        imageSupported: false
        persistenceSupported: false
    }

    readonly property int unreadCount: server.notifications.values.length

    visible: unreadCount > 0
    implicitWidth: visible ? label.implicitWidth + 24 : 0

    Text {
        id: label
        anchors.centerIn: parent
        color: cfg.color.base05
        font.family:    cfg.fontFamily
        font.pixelSize: cfg.fontSize - 1
        text: "󰂚"
    }
}
