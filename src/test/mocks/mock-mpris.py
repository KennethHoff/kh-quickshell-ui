#!/usr/bin/env python3
"""
Fake MPRIS player. Registers org.mpris.MediaPlayer2.mock on the session bus
with a fixed track + Playing status so the bar's MediaPlayer plugin renders.

Quickshell's Mpris service watches for any name matching
org.mpris.MediaPlayer2.* and reads PlaybackStatus + Metadata.
"""

import asyncio

from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, dbus_property, method, PropertyAccess
from dbus_next import Variant


TRACK_TITLE  = "Music for Airports"
TRACK_ARTIST = "Brian Eno"
TRACK_ALBUM  = "Ambient 1: Music for Airports"
TRACK_LENGTH_US = 17 * 60 * 1_000_000  # 17 minutes


class Root(ServiceInterface):
    def __init__(self):
        super().__init__("org.mpris.MediaPlayer2")

    @dbus_property(access=PropertyAccess.READ)
    def Identity(self) -> "s":
        return "kh-test mock player"

    @dbus_property(access=PropertyAccess.READ)
    def DesktopEntry(self) -> "s":
        return "mock"

    @dbus_property(access=PropertyAccess.READ)
    def CanQuit(self) -> "b":
        return False

    @dbus_property(access=PropertyAccess.READ)
    def CanRaise(self) -> "b":
        return False

    @dbus_property(access=PropertyAccess.READ)
    def HasTrackList(self) -> "b":
        return False

    @dbus_property(access=PropertyAccess.READ)
    def SupportedUriSchemes(self) -> "as":
        return []

    @dbus_property(access=PropertyAccess.READ)
    def SupportedMimeTypes(self) -> "as":
        return []

    @method()
    def Quit(self):
        pass

    @method()
    def Raise(self):
        pass


class Player(ServiceInterface):
    def __init__(self):
        super().__init__("org.mpris.MediaPlayer2.Player")

    @dbus_property(access=PropertyAccess.READ)
    def PlaybackStatus(self) -> "s":
        return "Playing"

    @dbus_property(access=PropertyAccess.READ)
    def LoopStatus(self) -> "s":
        return "None"

    @dbus_property(access=PropertyAccess.READ)
    def Rate(self) -> "d":
        return 1.0

    @dbus_property(access=PropertyAccess.READ)
    def Shuffle(self) -> "b":
        return False

    @dbus_property(access=PropertyAccess.READ)
    def Metadata(self) -> "a{sv}":
        return {
            "mpris:trackid":  Variant("o", "/org/mpris/MediaPlayer2/mock/track/1"),
            "mpris:length":   Variant("x", TRACK_LENGTH_US),
            "xesam:title":    Variant("s", TRACK_TITLE),
            "xesam:artist":   Variant("as", [TRACK_ARTIST]),
            "xesam:album":    Variant("s", TRACK_ALBUM),
            "xesam:albumArtist": Variant("as", [TRACK_ARTIST]),
        }

    @dbus_property(access=PropertyAccess.READ)
    def Volume(self) -> "d":
        return 1.0

    @dbus_property(access=PropertyAccess.READ)
    def Position(self) -> "x":
        return 5 * 60 * 1_000_000  # 5 min in

    @dbus_property(access=PropertyAccess.READ)
    def MinimumRate(self) -> "d":
        return 1.0

    @dbus_property(access=PropertyAccess.READ)
    def MaximumRate(self) -> "d":
        return 1.0

    @dbus_property(access=PropertyAccess.READ)
    def CanGoNext(self) -> "b":
        return True

    @dbus_property(access=PropertyAccess.READ)
    def CanGoPrevious(self) -> "b":
        return True

    @dbus_property(access=PropertyAccess.READ)
    def CanPlay(self) -> "b":
        return True

    @dbus_property(access=PropertyAccess.READ)
    def CanPause(self) -> "b":
        return True

    @dbus_property(access=PropertyAccess.READ)
    def CanSeek(self) -> "b":
        return False

    @dbus_property(access=PropertyAccess.READ)
    def CanControl(self) -> "b":
        return True

    @method()
    def Next(self): pass

    @method()
    def Previous(self): pass

    @method()
    def Pause(self): pass

    @method()
    def PlayPause(self): pass

    @method()
    def Stop(self): pass

    @method()
    def Play(self): pass

    @method()
    def Seek(self, Offset: "x"): pass

    @method()
    def SetPosition(self, TrackId: "o", Position: "x"): pass

    @method()
    def OpenUri(self, Uri: "s"): pass


async def main():
    bus = await MessageBus().connect()
    bus.export("/org/mpris/MediaPlayer2", Root())
    bus.export("/org/mpris/MediaPlayer2", Player())
    await bus.request_name("org.mpris.MediaPlayer2.mock")
    await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
