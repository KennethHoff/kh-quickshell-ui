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
| `BarPipe` | Thin vertical separator; place between plugin groups for a visual divide |
| `BarGroup` | Bar button that opens a popup panel; children are panel content |
| `BarDropdown` | Generic dropdown primitive; use `BarGroup` for most cases |
| `BarTooltip` | Hover-activated popup attached to any bar element; surfaces secondary detail (errors, long labels, etc.) |

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

## Environment variables

Some plugins require external configuration or secrets. You can pass environment variables to the bar service via the `environment` and `environmentFiles` options:

```nix
programs.kh-ui.bar = {
  structure = ''....'';
  
  environment = {
    // Direct environment variables (plaintext values)
    SONARR_TV = "your-api-key";
    EXAMPLE_VAR = "value";
  };
  
  environmentFiles = [
    // Secret files (typically from sops/agenix)
    config.sops.secrets."sonarr/4k-key".path
  ];
};
```

Plugins read these variables via `Quickshell.env()`. See individual plugin documentation for which variables are required.

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

### `Notifications`

Bell indicator that appears when there are unread notifications. Sourced from the Quickshell `NotificationServer`. Hidden when the count is zero.

### System-stats data sources

`CpuUsage`, `RamUsage`, `GpuUsage`, `DiskUsage`, `CpuTemp`, `GpuTemp` are
**data-only** plugins — they poll their sources and expose readable properties
for you to bind against. They have no visuals of their own. Pair each with a
`BarText` (or any other component) to render the value however you like:

```qml
CpuUsage { id: cpuUsage }
BarText { text: "cpu " + cpuUsage.usage + "%" }
```

| Plugin | Source | Poll | Exposed properties |
|---|---|---|---|
| `CpuUsage` | `/proc/stat` | `interval` (2 s) | `usage: int` (%) |
| `RamUsage` | `/proc/meminfo` | `interval` (2 s) | `totalKb`, `availableKb`, `usedKb`, `percent` |
| `GpuUsage` | `/sys/class/drm/<card>/device/` | `interval` (2 s) | `busy`, `vramUsedB`, `vramTotalB`, `vramUsedMb`, `vramTotalMb` |
| `DiskUsage` | `df -B1 <mounts>` | `interval` (60 s) | `results: [{ mount, usedB, totalB }]` |
| `CpuTemp` | `/sys/class/hwmon/hwmon*/{name,temp1_input}` | `interval` (5 s) | `temp: int` (°C) |
| `GpuTemp` | `/sys/class/hwmon/hwmon*/{name,temp1_input}` | `interval` (5 s) | `temp: int` (°C) |

Key configuration:

- `GpuUsage.cardPath` — default `/sys/class/drm/card1/device`. Nvidia is not yet
  supported — see the ROADMAP's "System Stats → GPU stats" entry.
- `DiskUsage.mounts` — default `["/"]`; list of paths to pass to `df`.
- `CpuTemp.sensor` / `GpuTemp.sensor` — default `"zenpower"` / `"amdgpu"`.
  Inspect your machine with
  `for d in /sys/class/hwmon/hwmon*; do echo "$d $(cat "$d/name")"; done`.
  Common alternatives: `coretemp` (Intel), `k10temp` (older Ryzen), `nvidia`.

Example panel with all six:

```qml
BarGroup {
    label: "stats"
    panelWidth: 320

    CpuUsage { id: cpuUsage }
    BarText  { text: "cpu " + cpuUsage.usage + "%" }

    RamUsage { id: ramUsage }
    BarText  { text: "ram " + ramUsage.percent + "%" }

    GpuUsage { id: gpuUsage }
    BarText  {
        text: "gpu " + gpuUsage.busy + "% ("
            + gpuUsage.vramUsedMb + "M/" + gpuUsage.vramTotalMb + "M)"
    }

    DiskUsage { id: diskUsage; mounts: ["/", "/home"] }
    Repeater {
        model: diskUsage.results
        BarText {
            text: modelData.mount + " "
                + Math.round(modelData.usedB  / 1e9) + "G/"
                + Math.round(modelData.totalB / 1e9) + "G"
        }
    }

    CpuTemp { id: cpuTemp }
    BarText {
        text:  "cpu " + cpuTemp.temp + "°"
        color: cpuTemp.temp >= 80 ? errorColor
             : cpuTemp.temp >= 60 ? warnColor
             :                      normalColor
    }

    GpuTemp { id: gpuTemp }
    BarText {
        text:  "gpu " + gpuTemp.temp + "°"
        color: gpuTemp.temp >= 80 ? errorColor
             : gpuTemp.temp >= 60 ? warnColor
             :                      normalColor
    }
}
```

### `TailscalePanel`

Tailscale status tile. Shows connection state and the machine's Tailscale IP. Click to toggle `tailscale up` / `tailscale down`. Exposes `connected` (bool), `selfIp` (string), and `peers` (array) for use by `TailscalePeers`.

> **Operator permission required.** `tailscale up`/`down` fail with "Access denied" unless your user is set as the Tailscale operator. Run this once:
> ```bash
> sudo tailscale up --operator=$USER
> ```
> Note: `tailscale set --operator` is [broken upstream](https://github.com/tailscale/tailscale/issues/18294) and `extraUpFlags` in the NixOS module [only applies when `authKeyFile` is set](https://github.com/NixOS/nixpkgs/issues/276912), so there is currently no clean declarative path for users who authenticate manually.

### `EthernetPanel`

Ethernet status tile. Shows the active interface name and link state. Exposes `connected` (bool) and `iface` (string).

### `SonarrPanel`

Sonarr integration tile. Displays the count of recently grabbed episodes from a Sonarr media server. Click to poll the API manually.

Configuration:

```qml
SonarrPanel {
    baseUrl: "http://sonarr"         // Required: protocol://host[:port] (port defaults to 80 for http, 443 for https)
    apiKeyEnv: "SONARR_API_KEY"      // Environment variable name for API key (required)
    pollInterval: 120                // Poll interval in seconds (optional, default: 120)
    maxHistoryItems: 20              // Max items to display (optional, default: 20)
}
```

**API Key Setup:**

The API key must be passed via an environment variable. Set it in your home-manager config using the standard `environment` + `environmentFiles` pattern:

```nix
programs.kh-ui.bar = {
  structure = ''
    BarRow {
      Workspaces {}
      BarSpacer {}
      SonarrPanel {
        baseUrl: "http://192.168.1.100:8989"
        apiKeyEnv: "SONARR_TV"
      }
      Clock {}
      Volume {}
    }
  '';
  
  environment = {
    SONARR_TV = "your-api-key";  // Plaintext (not recommended for secrets)
  };
};
```

For secrets, use `sops` or `agenix`:

```nix
programs.kh-ui.bar.environmentFiles = [
  config.sops.secrets."sonarr/api-key".path
];
```

**Multiple Instances:**

To monitor multiple Sonarr servers, declare multiple `SonarrPanel` instances with different `host` and `apiKeyEnv` values:

```qml
BarRow {
  SonarrPanel {
    baseUrl: "http://sonarr:8989"
    apiKeyEnv: "SONARR_TV"
  }
  SonarrPanel {
    baseUrl: "https://sonarr.100.x.x.x"
    apiKeyEnv: "SONARR_4K"
  }
}
```

Each instance polls independently and reads from its own environment variable.

**Exposes:**

- `newCount: int` — Number of recently grabbed episodes
- `recentGrabs: array` — Array of recent grab items (`{series, season, episode, title, timestamp}`)
- `loading: bool` — Whether an API call is in progress
- `error: string` — Runtime/API error from the last poll (empty on success)
- `configError: string` — Newline-separated list of failed config checks (empty when the config is valid); set by `validateConfig()` on `Component.onCompleted` and whenever `baseUrl`/`pollInterval`/`apiKeyEnv` changes. Polling is skipped while non-empty
- `hasError: bool` — `configError !== "" || error !== ""`; drives the badge colour and the error `BarTooltip` visibility

**Error surface:**

Hovering the badge opens a `BarTooltip` listing every current error (config + runtime), each line separated by a `BarHorizontalDivider`. The tooltip is also IPC-pinnable — `qs ipc call bar.sonarr.error pin` keeps it visible without a mouse hover, useful for scripts or keyboard-first workflows.

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
| `BarText` | Pre-styled `Text` (theme font + default foreground); exposes `normalColor` / `warnColor` / `errorColor` / `mutedColor` for overrides without a separate `NixConfig` reference |
| `BarIcon` | Pre-styled `Text` bound to the bundled nerd-font via `cfg.iconFontFile`; set `glyph:` to the PUA codepoint; same `normalColor` / `warnColor` / `errorColor` / `mutedColor` overrides as `BarText` |
| `BarTooltip` | Hover popup attached to any bar element; default content slot accepts any QML children; optional `ipcName` exposes `pin` / `unpin` / `togglePin` / `isPinned` / `isVisible` |
| `BarHorizontalDivider` | 1 px horizontal rule spanning the parent's width; `dividerColor` and `dividerHeight` override per use |
| `BarControlTile` | Styled toggle pill for custom panel tiles |
| `BarDropdownHeader` | Muted section heading inside a `BarDropdown` panel |
| `BarDropdownItem` | Row with dot indicator, primary label, secondary label |
| `NixConfig` | Theme colors (`color.baseXX`), font family and size |

## Writing a custom plugin

A plugin is a `BarPlugin` subtype. `BarPlugin` handles the sizing boilerplate and provides `ipcPrefix`, `barHeight`, and `barWindow` — you only need to set `implicitWidth`. Set `ipcName: "<segment>"` on the plugin to give it a stable IPC namespace; the plugin's own `IpcHandler` then writes `target: ipcPrefix` and resolves to `<parentPrefix>.<segment>` automatically. Any child that walks the parent chain (another `BarPlugin`, a `BarTooltip`, a `BarDropdown`) nests underneath.

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
    ipcName: "mywidget"
    NixConfig { id: cfg }
    NixBins   { id: bin }  // omit if the plugin doesn't run external processes

    implicitWidth: _label.implicitWidth + 16

    IpcHandler {
        target: ipcPrefix
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

Each plugin registers at a suffix derived from its `ipcName` property. The full target path is built from the nesting in your `structure` — every `BarPlugin` / `BarGroup` / `BarDropdown` / `BarTooltip` that declares an `ipcName` appends its own segment to the parent's prefix:

```
bar                                              (root)
bar.<plugin>
bar.<group-ipcName>.<plugin>
bar.<group-ipcName>.<nested-group-ipcName>.<plugin>
```

For example, a `TailscalePanel` inside `BarGroup { ipcName: "net" }` is reachable as `bar.net.tailscale`.

The root target (`bar`) exposes bar-wide queries:

| Target | Functions |
|---|---|
| `bar` | `getHeight()` -> int (visible bar footprint in px — bar height plus the tallest currently-open dropdown popup), `getWidth()` -> int (bar width in px) |

| Plugin | Suffix | Functions / Properties |
|---|---|---|
| `Workspaces` | `.workspaces` | `getFocused()` -> string, `list()` -> newline-separated names, `switchTo(name)`, `showPreview(name)`, `hidePreview()` |
| `Workspaces` preview tooltip | `.workspaces.ws<name>` | `pin()`, `unpin()`, `togglePin()`, `isPinned()` -> bool, `isVisible()` -> bool — one tooltip per workspace; pin lets multiple previews coexist |
| `Volume` | `.volume` | `getVolume()` -> int (0-150), `setVolume(v)`, `adjustVolume(delta)`, `isMuted()` -> bool, `setMuted(muted)`, `toggleMute()` |
| `MediaPlayer` | `.media` | `isActive()` -> bool, `isPlaying()` -> bool, `getTitle()`, `getArtist()`, `togglePlaying()`, `play()`, `pause()`, `next()`, `prev()` |
| `Tray` | `.tray` | `list()` -> newline-separated titles, `activate(title)`, `showMenu(title)` |
| `Notifications` | `.notifications` | `getCount()` -> int, `list()` -> array of `{id, app, summary}`, `clear()` |
| `TailscalePanel` | `.tailscale` | `isConnected()` -> bool, `getSelfIp()` -> string, `toggle()` |
| `EthernetPanel` | `.ethernet` | `isConnected()` -> bool, `getIface()` -> string |
| `SonarrPanel` | `.sonarr` | `getNewCount()` -> int, `getRecentGrabs()` -> array, `getError()` -> string, `getConfigError()` -> string |
| `SonarrPanel` error tooltip | `.sonarr.error` | `pin()`, `unpin()`, `togglePin()`, `isPinned()` -> bool, `isVisible()` -> bool |
| `CpuUsage` | `.cpu` | `getUsage()` -> int |
| `RamUsage` | `.ram` | `getUsedMb()` -> int, `getTotalMb()` -> int, `getPercent()` -> int |
| `GpuUsage` | `.gpu` | `getBusy()` -> int, `getVramUsedMb()` -> int, `getVramTotalMb()` -> int |
| `DiskUsage` | `.disk` | `list()` -> tab-separated `mount\tusedB\ttotalB` per line; `count()` -> int |
| `CpuTemp` | `.cpuTemp` | `getTemp()` -> int (°C) |
| `GpuTemp` | `.gpuTemp` | `getTemp()` -> int (°C) |
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
