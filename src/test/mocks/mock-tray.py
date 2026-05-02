#!/usr/bin/env python3
"""
Fake StatusNotifierItem publisher. Registers two SNI items (Slack, Spotify)
with org.kde.StatusNotifierWatcher so the bar's Tray plugin renders them.

The watcher is provided by Quickshell's SystemTray service, which only
appears once quickshell is running and has imported Quickshell.Services.
SystemTray. We retry the registration until the watcher is available.
"""

import asyncio
import os

from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, dbus_property, method, signal, PropertyAccess
from dbus_next import Variant, BusType


WATCHER_BUS  = "org.kde.StatusNotifierWatcher"
WATCHER_PATH = "/StatusNotifierWatcher"
WATCHER_IFACE = "org.kde.StatusNotifierWatcher"


class TrayItem(ServiceInterface):
    def __init__(self, item_id: str, title: str, icon_name: str):
        super().__init__("org.kde.StatusNotifierItem")
        self._id = item_id
        self._title = title
        self._icon_name = icon_name

    @dbus_property(access=PropertyAccess.READ)
    def Category(self) -> "s":
        return "ApplicationStatus"

    @dbus_property(access=PropertyAccess.READ)
    def Id(self) -> "s":
        return self._id

    @dbus_property(access=PropertyAccess.READ)
    def Title(self) -> "s":
        return self._title

    @dbus_property(access=PropertyAccess.READ)
    def Status(self) -> "s":
        return "Active"

    @dbus_property(access=PropertyAccess.READ)
    def WindowId(self) -> "i":
        return 0

    @dbus_property(access=PropertyAccess.READ)
    def IconName(self) -> "s":
        return self._icon_name

    @dbus_property(access=PropertyAccess.READ)
    def IconPixmap(self) -> "a(iiay)":
        return []

    @dbus_property(access=PropertyAccess.READ)
    def OverlayIconName(self) -> "s":
        return ""

    @dbus_property(access=PropertyAccess.READ)
    def OverlayIconPixmap(self) -> "a(iiay)":
        return []

    @dbus_property(access=PropertyAccess.READ)
    def AttentionIconName(self) -> "s":
        return ""

    @dbus_property(access=PropertyAccess.READ)
    def AttentionIconPixmap(self) -> "a(iiay)":
        return []

    @dbus_property(access=PropertyAccess.READ)
    def AttentionMovieName(self) -> "s":
        return ""

    @dbus_property(access=PropertyAccess.READ)
    def ToolTip(self) -> "(sa(iiay)ss)":
        return ("", [], self._title, "")

    @dbus_property(access=PropertyAccess.READ)
    def ItemIsMenu(self) -> "b":
        return False

    @dbus_property(access=PropertyAccess.READ)
    def Menu(self) -> "o":
        return "/NO_DBUSMENU"

    @method()
    def Activate(self, x: "i", y: "i"): pass

    @method()
    def SecondaryActivate(self, x: "i", y: "i"): pass

    @method()
    def ContextMenu(self, x: "i", y: "i"): pass

    @method()
    def Scroll(self, delta: "i", orientation: "s"): pass

    @signal()
    def NewTitle(self): pass

    @signal()
    def NewIcon(self): pass

    @signal()
    def NewAttentionIcon(self): pass

    @signal()
    def NewOverlayIcon(self): pass

    @signal()
    def NewToolTip(self): pass

    @signal()
    def NewStatus(self) -> "s":
        return "Active"


async def wait_for_watcher(bus, timeout_s: float = 30.0):
    proxy = await bus.introspect("org.freedesktop.DBus", "/org/freedesktop/DBus")
    obj = bus.get_proxy_object("org.freedesktop.DBus", "/org/freedesktop/DBus", proxy)
    dbus_iface = obj.get_interface("org.freedesktop.DBus")

    deadline = asyncio.get_event_loop().time() + timeout_s
    while asyncio.get_event_loop().time() < deadline:
        names = await dbus_iface.call_list_names()
        if WATCHER_BUS in names:
            return True
        await asyncio.sleep(0.2)
    return False


async def register_item(bus, pid: int, suffix: int, item_id: str, title: str, icon: str):
    bus_name = f"org.kde.StatusNotifierItem-{pid}-{suffix}"
    item = TrayItem(item_id, title, icon)
    bus.export("/StatusNotifierItem", item)
    await bus.request_name(bus_name)

    proxy = await bus.introspect(WATCHER_BUS, WATCHER_PATH)
    watcher_obj = bus.get_proxy_object(WATCHER_BUS, WATCHER_PATH, proxy)
    watcher = watcher_obj.get_interface(WATCHER_IFACE)
    await watcher.call_register_status_notifier_item(bus_name)


async def main():
    bus = await MessageBus(bus_type=BusType.SESSION).connect()

    if not await wait_for_watcher(bus):
        raise SystemExit("StatusNotifierWatcher never appeared on session bus")

    pid = os.getpid()
    # One bus + one /StatusNotifierItem per process: spawn two child connections.
    bus2 = await MessageBus(bus_type=BusType.SESSION).connect()

    await register_item(bus,  pid, 1, "slack",   "Slack",   "applications-internet")
    await register_item(bus2, pid, 2, "spotify", "Spotify", "audio-x-generic")

    await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
