// Bar plugin: notification bell.
// Visible only when there are unread notifications. Hidden when count is zero.
import QtQuick
import Quickshell.Io
import Quickshell.Services.Notifications

BarPlugin {
    ipcName: "notifications"

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: false
        bodyMarkupSupported: false
        bodySupported: true
        imageSupported: false
        persistenceSupported: false

        onNotification: notification => functionality.onNotification(notification)
    }

    QtObject {
        id: state
        readonly property int unreadCount: server.trackedNotifications.values.length
    }

    QtObject {
        id: functionality

        // ui only
        function onNotification(notification): void { notification.tracked = true }
        // ipc only
        function getCount(): int { return state.unreadCount }
        // ipc only
        function list(): var {
            return server.trackedNotifications.values.map(n => ({ id: n.id, app: n.appName, summary: n.summary }))
        }
        // ipc only
        function clear(): void { server.trackedNotifications.values.forEach(n => n.expire()) }
    }

    IpcHandler {
        target: ipcPrefix
        function getCount(): int { return functionality.getCount() }
        function list(): var     { return functionality.list() }
        function clear(): void   { functionality.clear() }
    }

    visible: state.unreadCount > 0
    implicitWidth: visible ? _bell.implicitWidth + 24 : 0

    BarIcon {
        id: _bell
        anchors.centerIn: parent
        glyph: "\uF0F3"
    }
}
