# Launcher plugins

The launcher is a unified plugin host — every plugin (apps, window switcher,
emoji picker, etc.) flows through the same item model, search, navigation, and
launch path. The built-in "apps" plugin is registered alongside user-defined
plugins with no special-casing.

> Note: "plugin" here is the launcher's extensibility unit (item source). Do
> not confuse it with the launcher's *input mode* (`insert` / `normal` /
> `actions`), which is a separate concept — navigation state within whichever
> plugin is currently active.

## Concepts

A **plugin** is a named item source. Each plugin has:

| Field | Type | Description |
|---|---|---|
| *key* | string | The attribute name / IPC identifier — stable, machine-facing (e.g. `hyprland-windows`). Used by `activatePlugin`, `removePlugin`, `registerPlugin`, and the plugin's entry in `listPlugins` output |
| `label` | string | Human-facing display name shown on the plugin chip in the launcher. Defaults to the key when empty, so a key like `hyprland-windows` can present itself as `Windows` without changing its IPC identity |
| `script` | path (string) | Executable that outputs items as TSV to stdout |
| `frecency` | bool | Track launch frequency and boost frequently-used items |
| `hasActions` | bool | Enable desktop-action sub-mode (parses `[Desktop Action]` sections from `.desktop` files) |
| `placeholder` | string | Search field placeholder text |
| `default` | bool | Activate this plugin on startup (first match wins) |
| `iconDelegate` | string | Filename of the QML component that renders the icon slot (e.g. `"LauncherIconFile.qml"`). The launcher instantiates it via `Loader` and binds `iconData` (from the item's icon column) and `labelText` (from the item's label) onto it. Omit for a letter-tile fallback |

Items are 4- or 5-field tab-separated lines:

```
label\tdescription\ticon\tcallback[\tid]
```

- **label** — display name
- **description** — secondary text (may be empty)
- **icon** — plugin-defined string passed as `iconData` to the plugin's
  `iconDelegate` component. Shape depends on the chosen delegate — e.g.
  `LauncherIconFile.qml` expects an absolute file path; `LauncherIconGlyph.qml`
  expects a glyph (emoji or single character). Empty falls back to a
  letter-tile built from the label.
- **callback** — shell command executed on launch
- **id** — optional; defaults to label. Used for frecency tracking and
  desktop-action parsing (must be a `.desktop` file path for `hasActions`)

## Adding plugins via Nix

Use `programs.kh-ui.launcher.scriptPlugins` in your home-manager config. Each
entry becomes a plugin alongside the built-in apps plugin.

### Example: system commands

```nix
programs.kh-ui.launcher.scriptPlugins.system = {
  script = pkgs.writeShellScript "system-plugin" ''
    echo -e "Lock\tLock the screen\t\tloginctl lock-session"
    echo -e "Suspend\tSuspend to RAM\t\tsystemctl suspend"
    echo -e "Reboot\tRestart the machine\t\tsystemctl reboot"
    echo -e "Shutdown\tPower off\t\tsystemctl poweroff"
  '';
  label = "System";
  placeholder = "System command...";
};
```

The attribute name (`system`) is the stable IPC identifier; `label` is purely
cosmetic. If `label` is omitted, the chip shows the attribute name.

### Built-in plugins

**`apps`** (default, Apps) — fuzzy searches installed `.desktop` applications,
Enter launches. Frecency-ranked; supports desktop actions (`l` / Tab cycles
into them).

**`emoji`** (Emoji) — fuzzy searches Unicode emoji; Enter copies the glyph
to the Wayland clipboard via `wl-copy` (no trailing newline). Glyph list is
sourced from `pkgs.unicode-emoji` (`fully-qualified` status entries only),
joined with `pkgs.cldr-annotations` (`en.xml`) for authoritative keyword
annotations — same data GNOME/GTK pickers use. Keywords flow through the
description field so `love` finds ❤️, `lol` finds 🤣, etc. The emoji glyph
renders directly in the icon slot.

**`hyprland-windows`** (Windows) — Hyprland-only. Lists every open window
sorted most-recently-focused first, with icons resolved from each window's WM
class; Enter runs `hyprctl dispatch focuswindow` (Hyprland switches to the
window's workspace automatically). Under any other compositor the plugin
stays registered but lists nothing. Activate via
`qs ipc -c kh-launcher call launcher activatePlugin hyprland-windows`.

### Icon primitives

Shared QML components plugins reference via `iconDelegate`. Each primitive
declares `property string iconData` / `property string labelText`; the
launcher binds those from the item's icon and label columns.

| Primitive | When to use |
|---|---|
| `LauncherIconFile.qml` | `iconData` is an absolute file path. Renders as an `Image` with a letter-tile fallback if the path is empty or fails to load. Used by `apps`, `hyprland-windows` |
| `LauncherIconGlyph.qml` | `iconData` is a text glyph (emoji, single character, nerd-font codepoint). Rendered as centred text sized to the slot. Used by `emoji` |

Plugins with exotic rendering needs (colour swatches, animated badges, …)
can skip the primitives and ship a custom QML file via `generatedFiles` in
their Nix helper — set `iconDelegate = "MyCustomIcon.qml"` and ensure the
file declares matching `iconData` / `labelText` properties.

### Removing a built-in plugin

Built-in plugins (`apps`, `emoji`, `hyprland-windows`) are registered by
their plugin sources. To remove one and only use your own plugins, override
`PluginRegistry.qml` via `generatedFiles` in your flake. The simplest
approach is to remove it at runtime via IPC after startup:

```bash
qs ipc -c kh-launcher call launcher removePlugin apps
qs ipc -c kh-launcher call launcher removePlugin emoji
qs ipc -c kh-launcher call launcher removePlugin hyprland-windows
```

Or set up a keybind/script that removes it on each session start if you
never want it.

## Adding plugins via IPC (runtime)

Plugins can be registered and populated entirely at runtime without any Nix
configuration. There are two approaches:

### Script-backed plugin

Register a plugin with a script path. The launcher runs the script and parses
its TSV output, just like Nix-configured plugins:

```bash
qs ipc -c kh-launcher call launcher registerPlugin \
  "bookmarks" "/path/to/bookmarks-script.sh" false false "Search bookmarks..." "Bookmarks"
```

Arguments to `registerPlugin`:
1. `name` (string) — plugin key / IPC identifier
2. `script` (string) — path to executable (empty string for push-based plugins)
3. `frecency` (bool) — enable frecency tracking
4. `hasActions` (bool) — enable desktop-action sub-mode
5. `placeholder` (string) — search field placeholder
6. `label` (string) — display name on the chip; pass `""` to fall back to the key

Then activate it:

```bash
qs ipc -c kh-launcher call launcher activatePlugin bookmarks
```

### Push-based plugin (no script)

Register a plugin with an empty script, then push items via IPC. This is useful
for plugins where the caller controls the item list — e.g. an external fuzzy
finder, a daemon that streams results, or a test harness:

```bash
# Register an empty plugin
qs ipc -c kh-launcher call launcher registerPlugin \
  "picker" "" false false "Pick an item..." "Picker"

# Push items (each call adds one item to the buffer)
qs ipc -c kh-launcher call launcher addItem \
  "picker" "Option A" "First choice" "" "echo picked-a"

qs ipc -c kh-launcher call launcher addItem \
  "picker" "Option B" "Second choice" "" "echo picked-b"

# Signal that all items have been pushed (displays them)
qs ipc -c kh-launcher call launcher itemsReady picker

# Activate the plugin (if not already active)
qs ipc -c kh-launcher call launcher activatePlugin picker
```

Items can be pre-populated before activation — they display instantly when the
plugin is activated, with no flicker. `addItemWithId` accepts a 6th `id` argument
for frecency tracking:

```bash
qs ipc -c kh-launcher call launcher addItemWithId \
  "picker" "Option A" "First choice" "" "echo picked-a" "option-a"
```

### Removing plugins at runtime

```bash
# Remove a specific plugin (returns to default if it was active)
qs ipc -c kh-launcher call launcher removePlugin picker

# List all registered plugins
qs ipc -c kh-launcher call launcher listPlugins
```

## Plugin navigation

### Keyboard (when launcher is open)

| Key | Input mode | Action |
|---|---|---|
| `]` | normal | Next plugin |
| `[` | normal | Previous plugin |
| Click plugin chip | any | Activate that plugin |

### IPC

```bash
qs ipc -c kh-launcher call launcher nextPlugin
qs ipc -c kh-launcher call launcher prevPlugin
qs ipc -c kh-launcher call launcher activatePlugin <name>
qs ipc -c kh-launcher call launcher returnToDefault
```

## Querying state

```bash
# Current active plugin name
qs ipc -c kh-launcher prop get launcher activePlugin

# Number of filtered items
qs ipc -c kh-launcher prop get launcher itemCount

# Label of the currently selected item
qs ipc -c kh-launcher prop get launcher selectedLabel

# Callback of the currently selected item
qs ipc -c kh-launcher prop get launcher selectedCallback

# Label of the last launched item
qs ipc -c kh-launcher prop get launcher lastSelection
```

## Full IPC reference

### Functions

| Function | Arguments | Description |
|---|---|---|
| `activatePlugin` | `name` | Switch to a named plugin |
| `returnToDefault` | — | Switch to the default plugin |
| `nextPlugin` | — | Cycle to the next registered plugin |
| `prevPlugin` | — | Cycle to the previous registered plugin |
| `registerPlugin` | `name, script, frecency, hasActions, placeholder, label` | Register or replace a runtime plugin (`label` empty → chip shows `name`) |
| `removePlugin` | `name` | Remove a plugin (returns to default if active) |
| `listPlugins` | — | Returns space-separated list of plugin keys |
| `addItem` | `plugin, label, description, icon, callback` | Push an item into a plugin's buffer |
| `addItemWithId` | `plugin, label, description, icon, callback, id` | Push an item with explicit id |
| `itemsReady` | `plugin` | Flush the buffer and display items |

### Properties (read-only)

| Property | Type | Description |
|---|---|---|
| `activePlugin` | string | Name of the current plugin |
| `mode` | string | Input mode (`insert` / `normal` / `actions`) |
| `itemCount` | int | Number of visible (filtered) items |
| `selectedLabel` | string | Label of the highlighted item |
| `selectedCallback` | string | Callback of the highlighted item |
| `lastSelection` | string | Label of the last launched item |
