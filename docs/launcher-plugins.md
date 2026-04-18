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
| `script` | path (string) | Executable that outputs items as TSV to stdout |
| `frecency` | bool | Track launch frequency and boost frequently-used items |
| `hasActions` | bool | Enable desktop-action sub-mode (parses `[Desktop Action]` sections from `.desktop` files) |
| `placeholder` | string | Search field placeholder text |
| `default` | bool | Activate this plugin on startup (first match wins) |

Items are 4- or 5-field tab-separated lines:

```
label\tdescription\ticon\tcallback[\tid]
```

- **label** — display name
- **description** — secondary text (may be empty)
- **icon** — absolute path to icon file (may be empty)
- **callback** — shell command executed on launch
- **id** — optional; defaults to label. Used for frecency tracking and
  desktop-action parsing (must be a `.desktop` file path for `hasActions`)

## Adding plugins via Nix

Use `programs.kh-ui.launcher.scriptPlugins` in your home-manager config. Each
entry becomes a plugin alongside the built-in apps plugin.

### Example: emoji picker

```nix
programs.kh-ui.launcher.scriptPlugins.emoji = {
  script = pkgs.writeShellScript "emoji-plugin" ''
    # Output: label (emoji + name), description, icon (empty), callback
    echo -e "😀 Grinning Face\t\t\techo 😀 | wl-copy"
    echo -e "🎉 Party Popper\t\t\techo 🎉 | wl-copy"
    # In practice, read from a data file:
    # while IFS=$'\t' read -r emoji name; do
    #   printf '%s %s\t\t\techo %s | wl-copy\n' "$emoji" "$name" "$emoji"
    # done < /path/to/emoji.tsv
  '';
  placeholder = "Search emoji...";
};
```

### Example: system commands

```nix
programs.kh-ui.launcher.scriptPlugins.system = {
  script = pkgs.writeShellScript "system-plugin" ''
    echo -e "Lock\tLock the screen\t\tloginctl lock-session"
    echo -e "Suspend\tSuspend to RAM\t\tsystemctl suspend"
    echo -e "Reboot\tRestart the machine\t\tsystemctl reboot"
    echo -e "Shutdown\tPower off\t\tsystemctl poweroff"
  '';
  placeholder = "System command...";
};
```

### Example: window switcher (Hyprland)

```nix
programs.kh-ui.launcher.scriptPlugins.windows = {
  script = pkgs.writeShellScript "window-plugin" ''
    ${lib.getExe pkgs.jq} -r '
      .[] | "\(.title)\t\(.class)\t\thyprctl dispatch focuswindow address:\(.address)"
    ' <<< "$(hyprctl clients -j)"
  '';
  placeholder = "Switch window...";
};
```

### Removing the default apps plugin

The built-in apps plugin is registered by the apps plugin source. To remove it
and only use your own plugins, override the apps plugin output in your flake
by providing a custom `PluginRegistry.qml` via `generatedFiles`. However, the
simplest approach is to remove it at runtime via IPC after startup:

```bash
qs ipc -c kh-launcher call launcher removePlugin apps
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
  "bookmarks" "/path/to/bookmarks-script.sh" false false "Search bookmarks..."
```

Arguments to `registerPlugin`:
1. `name` (string) — plugin name
2. `script` (string) — path to executable (empty string for push-based plugins)
3. `frecency` (bool) — enable frecency tracking
4. `hasActions` (bool) — enable desktop-action sub-mode
5. `placeholder` (string) — search field placeholder

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
  "picker" "" false false "Pick an item..."

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
| `registerPlugin` | `name, script, frecency, hasActions, placeholder` | Register or replace a runtime plugin |
| `removePlugin` | `name` | Remove a plugin (returns to default if active) |
| `listPlugins` | — | Returns space-separated list of plugin names |
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
