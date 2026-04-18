# Bar (`kh-bar`)

## Configuration

The bar requires an explicit layout — there is no default. Set it via `programs.kh-ui.bar.structure`:

```nix
programs.kh-ui.bar.structure = ''
  BarRow {
    Workspaces {}
    MediaPlayer {}
    BarSpacer {}
    Clock {}
    Volume {}
    Tray {}
  }
'';
```

`BarRow` is a full-width `RowLayout` row. `BarSpacer` expands to fill remaining space — place it between plugin groups to push them apart (equivalent to CSS `space-between`). Multiple `BarRow`s, additional spacers, or any other QML types can appear at the top level.

## Layout types

| Component | Purpose |
|---|---|
| `BarRow` | Full-width `RowLayout` row; children laid out left-to-right |
| `BarSpacer` | Flexible spacer; expands to fill remaining width |
| `BarGroup` | Bar button that opens a popup panel; children are panel content |
| `BarDropdown` | Generic dropdown primitive; use `BarGroup` for most cases |

Use `BarGroup` to group plugins behind a single dropdown button:

```nix
programs.kh-ui.bar.structure = ''
  BarRow {
    Workspaces {}
    BarSpacer {}
    BarGroup {
      label: "●●●"
      ipcName: "controlcenter"
      panelWidth: 300
      Row {
        spacing: 8
        EthernetPanel {}
        TailscalePanel { id: ts }
      }
      TailscalePeers { source: ts }
    }
    Clock {}
    Volume {}
    Tray {}
  }
'';
```

## Plugins

### `Workspaces`

Hyprland workspace switcher. Displays all workspaces and highlights the active one. Click a workspace to switch to it. Hover a workspace for 300 ms to show a live thumbnail preview.

### `MediaPlayer`

MPRIS playback controls (prev / play-pause / next) with artist and title display. Hidden when no player is active. Shows the first active player when multiple are running.

### `Clock`

Live `HH:mm:ss` clock. Updates every second.

### `Volume`

PipeWire volume control. Scroll to adjust volume, click to toggle mute. Hidden when no sink is available.

### `Tray`

StatusNotifierItem system tray. Left-click activates an item, right-click shows its native context menu. Hidden when no tray items are present.

### `Cpu`

Aggregate CPU utilisation %. Samples `/proc/stat` on `interval` (default 2 s) and renders a rolling delta. Set `hideBelow` to an int percentage to hide the plugin when idle:

```qml
Cpu { hideBelow: 5 }   // hidden while usage < 5 %
```

### `Ram`

RAM usage from `/proc/meminfo` (`MemTotal - MemAvailable`). Default display is absolute (`ram: 4.2G/16G`); set `format: "percent"` for `ram: 27%`.

### `Gpu`

AMD GPU utilisation and VRAM use from `/sys/class/drm/<card>/device/`. Defaults to `card1`; override via `cardPath`:

```qml
Gpu { cardPath: "/sys/class/drm/card0/device"; hideBelow: 5 }
```

Nvidia is not yet supported — see the ROADMAP's "System Stats → GPU stats" entry.

### `Disk`

Disk used/total for one or more configured mount points. Shells out to `df -B1` on `interval` (default 60 s):

```qml
Disk { mounts: ["/", "/home"]; interval: 120000 }
```

### `Temps`

CPU and GPU temperatures from `/sys/class/hwmon`. Sensors are matched by their `name` file (inspect with `for d in /sys/class/hwmon/hwmon*; do echo "$d $(cat "$d/name")"; done`). Defaults match a Ryzen + AMD GPU system:

```qml
Temps {
    cpuSensor: "zenpower"   // e.g. "coretemp" on Intel, "k10temp" on older Ryzen
    gpuSensor: "amdgpu"
    warmAt: 60              // base09 colour above this
    hotAt:  80              // base08 colour above this
}
```

Hidden entirely when neither sensor is found.

### `TailscalePanel`

Tailscale status tile. Shows connection state and the machine's Tailscale IP. Click to toggle `tailscale up` / `tailscale down`. Exposes `connected` (bool), `selfIp` (string), and `peers` (array) for use by `TailscalePeers`.

> **Operator permission required.** `tailscale up`/`down` fail with "Access denied" unless your user is set as the Tailscale operator. Run this once:
> ```bash
> sudo tailscale up --operator=$USER
> ```
> Note: `tailscale set --operator` is [broken upstream](https://github.com/tailscale/tailscale/issues/18294) and `extraUpFlags` in the NixOS module [only applies when `authKeyFile` is set](https://github.com/NixOS/nixpkgs/issues/276912), so there is currently no clean declarative path for users who authenticate manually.

### `EthernetPanel`

Ethernet status tile. Shows the active interface name and link state. Exposes `connected` (bool) and `iface` (string).

### `TailscalePeers`

Peer list panel section. Displays the self IP header and all peers with online/offline indicators. Bind it to a `TailscalePanel` via the `source` property — it hides itself when disconnected:

```qml
TailscalePanel { id: ts }
TailscalePeers { source: ts }
```

## Primitive components

Low-level building blocks for custom plugins and panels (no import needed):

| Component | Purpose |
|---|---|
| `ControlTile` | Styled toggle pill for custom panel tiles |
| `DropdownHeader` | Muted section heading |
| `DropdownDivider` | 1 px horizontal rule |
| `DropdownItem` | Row with dot indicator, primary label, secondary label |
| `NixConfig` | Theme colors (`color.baseXX`), font family and size |

## Writing a custom plugin

A plugin is a `BarPlugin` subtype. `BarPlugin` handles the sizing boilerplate and provides `ipcPrefix`, `barHeight`, and `barWindow` — you only need to set `implicitWidth`.

Two singleton helpers are available in every plugin without an import:

| Helper | Purpose |
|---|---|
| `NixConfig` | Theme colors (`color.baseXX`), font family and size |
| `NixBins` | Store-path binaries injected via `extraBins`; use when shelling out to external tools |

Example `MyWidget.qml`:

```qml
import QtQuick
import Quickshell.Io

BarPlugin {
    NixConfig { id: cfg }
    NixBins   { id: bin }  // omit if the plugin doesn't run external processes

    implicitWidth: _label.implicitWidth + 16

    IpcHandler {
        target: ipcPrefix + ".mywidget"
        function getValue(): string { return _label.text }
    }

    Text {
        id: _label
        anchors.centerIn: parent
        text:           "hello"
        color:          cfg.color.base05
        font.family:    cfg.fontFamily
        font.pixelSize: cfg.fontSize
    }
}
```

Place your plugin files in a directory and pass it via `extraPluginDirs`. All `.qml` files in those directories are copied into the bar config root and become available by filename in `structure`:

```nix
programs.kh-ui.bar = {
  structure = ''
    BarRow {
      Workspaces {}
      MyWidget {}
    }
  '';
  extraPluginDirs = [ ./bar-plugins ];  # directory containing MyWidget.qml
};
```

## IPC

Each plugin registers at a suffix derived from its type. The full target path is built from the nesting in your `structure`:

```
bar.<plugin>
bar.<group-ipcName>.<plugin>
bar.<group-ipcName>.<nested-group-ipcName>.<plugin>
```

For example, a `TailscalePanel` inside `BarGroup { ipcName: "net" }` is reachable as `bar.net.tailscale`.

| Plugin | Suffix | Functions / Properties |
|---|---|---|
| `Workspaces` | `.workspaces` | `getFocused()` -> string, `list()` -> newline-separated names, `switchTo(name)`, `showPreview(name)`, `hidePreview()` |
| `Volume` | `.volume` | `getVolume()` -> int (0-150), `setVolume(v)`, `adjustVolume(delta)`, `isMuted()` -> bool, `setMuted(muted)`, `toggleMute()` |
| `MediaPlayer` | `.media` | `isActive()` -> bool, `isPlaying()` -> bool, `getTitle()`, `getArtist()`, `togglePlaying()`, `play()`, `pause()`, `next()`, `prev()` |
| `Tray` | `.tray` | `list()` -> newline-separated titles, `activate(title)`, `showMenu(title)` |
| `TailscalePanel` | `.tailscale` | `isConnected()` -> bool, `getSelfIp()` -> string, `toggle()` |
| `EthernetPanel` | `.ethernet` | `isConnected()` -> bool, `getIface()` -> string |
| `Cpu` | `.cpu` | `getUsage()` -> int |
| `Ram` | `.ram` | `getUsedMb()` -> int, `getTotalMb()` -> int, `getPercent()` -> int |
| `Gpu` | `.gpu` | `getBusy()` -> int, `getVramUsedMb()` -> int, `getVramTotalMb()` -> int |
| `Disk` | `.disk` | `list()` -> `[{ mount, usedB, totalB }]` |
| `Temps` | `.temps` | `getCpu()` -> int, `getGpu()` -> int |
| `BarGroup` / `BarDropdown` | `.<ipcName>` | `toggle()`, `open()`, `close()`, `isOpen()` -> bool |

### Dropdown IPC for custom plugins

Any `BarGroup` or `BarDropdown` with `ipcName` set gets `toggle`/`open`/`close`/`isOpen` automatically, under the inherited prefix:

```qml
BarGroup {
    ipcName: "mypanel"
    label: "my panel"
    // children reachable as bar.mypanel.<plugin>
}
```

```bash
qs ipc call bar.mypanel toggle
qs ipc call bar.mypanel isOpen
```

Custom plugins inside a group get their prefix automatically — use `ipcPrefix + ".mywidget"` as the `IpcHandler` target (see the custom plugin example above).
