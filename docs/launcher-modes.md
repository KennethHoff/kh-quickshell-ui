# Launcher modes

The launcher is a unified mode host — every mode (apps, window switcher, emoji
picker, etc.) flows through the same item model, search, navigation, and launch
path. The built-in "apps" mode is registered alongside user-defined modes with
no special-casing.

## Concepts

A **mode** is a named item source. Each mode has:

| Field | Type | Description |
|---|---|---|
| `script` | path (string) | Executable that outputs items as TSV to stdout |
| `frecency` | bool | Track launch frequency and boost frequently-used items |
| `hasActions` | bool | Enable desktop-action sub-mode (parses `[Desktop Action]` sections from `.desktop` files) |
| `placeholder` | string | Search field placeholder text |
| `default` | bool | Activate this mode on startup (first match wins) |

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

## Adding modes via Nix

Use `programs.kh-ui.launcher.scriptModes` in your home-manager config. Each
entry becomes a mode alongside the built-in apps mode.

### Example: emoji picker

```nix
programs.kh-ui.launcher.scriptModes.emoji = {
  script = pkgs.writeShellScript "emoji-mode" ''
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
programs.kh-ui.launcher.scriptModes.system = {
  script = pkgs.writeShellScript "system-mode" ''
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
programs.kh-ui.launcher.scriptModes.windows = {
  script = pkgs.writeShellScript "window-mode" ''
    ${lib.getExe pkgs.jq} -r '
      .[] | "\(.title)\t\(.class)\t\thyprctl dispatch focuswindow address:\(.address)"
    ' <<< "$(hyprctl clients -j)"
  '';
  placeholder = "Switch window...";
};
```

### Removing the default apps mode

The built-in apps mode is registered by the apps plugin. To remove it and
only use your own modes, override the apps plugin output in your flake by
providing a custom `ModeRegistry.qml` via `generatedFiles`. However, the
simplest approach is to remove it at runtime via IPC after startup:

```bash
qs ipc -c kh-launcher call launcher removeMode apps
```

Or set up a keybind/script that removes it on each session start if you
never want it.

## Adding modes via IPC (runtime)

Modes can be registered and populated entirely at runtime without any Nix
configuration. There are two approaches:

### Script-backed mode

Register a mode with a script path. The launcher runs the script and parses
its TSV output, just like Nix-configured modes:

```bash
qs ipc -c kh-launcher call launcher registerMode \
  "bookmarks" "/path/to/bookmarks-script.sh" false false "Search bookmarks..."
```

Arguments to `registerMode`:
1. `name` (string) — mode name
2. `script` (string) — path to executable (empty string for push-based modes)
3. `frecency` (bool) — enable frecency tracking
4. `hasActions` (bool) — enable desktop-action sub-mode
5. `placeholder` (string) — search field placeholder

Then activate it:

```bash
qs ipc -c kh-launcher call launcher activateMode bookmarks
```

### Push-based mode (no script)

Register a mode with an empty script, then push items via IPC. This is useful
for modes where the caller controls the item list — e.g. an external fuzzy
finder, a daemon that streams results, or a test harness:

```bash
# Register an empty mode
qs ipc -c kh-launcher call launcher registerMode \
  "picker" "" false false "Pick an item..."

# Push items (each call adds one item to the buffer)
qs ipc -c kh-launcher call launcher addItem \
  "picker" "Option A" "First choice" "" "echo picked-a"

qs ipc -c kh-launcher call launcher addItem \
  "picker" "Option B" "Second choice" "" "echo picked-b"

# Signal that all items have been pushed (displays them)
qs ipc -c kh-launcher call launcher itemsReady picker

# Activate the mode (if not already active)
qs ipc -c kh-launcher call launcher activateMode picker
```

Items can be pre-populated before activation — they display instantly when the
mode is activated, with no flicker. `addItemWithId` accepts a 6th `id` argument
for frecency tracking:

```bash
qs ipc -c kh-launcher call launcher addItemWithId \
  "picker" "Option A" "First choice" "" "echo picked-a" "option-a"
```

### Removing modes at runtime

```bash
# Remove a specific mode (returns to default if it was active)
qs ipc -c kh-launcher call launcher removeMode picker

# List all registered modes
qs ipc -c kh-launcher call launcher listModes
```

## Mode navigation

### Keyboard (when launcher is open)

| Key | Mode | Action |
|---|---|---|
| `]` | normal | Next mode |
| `[` | normal | Previous mode |
| Click mode chip | any | Activate that mode |

### IPC

```bash
qs ipc -c kh-launcher call launcher nextMode
qs ipc -c kh-launcher call launcher prevMode
qs ipc -c kh-launcher call launcher activateMode <name>
qs ipc -c kh-launcher call launcher returnToDefault
```

## Querying state

```bash
# Current active mode name
qs ipc -c kh-launcher prop get launcher activeMode

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
| `activateMode` | `name` | Switch to a named mode |
| `returnToDefault` | — | Switch to the default mode |
| `nextMode` | — | Cycle to the next registered mode |
| `prevMode` | — | Cycle to the previous registered mode |
| `registerMode` | `name, script, frecency, hasActions, placeholder` | Register or replace a runtime mode |
| `removeMode` | `name` | Remove a mode (returns to default if active) |
| `listModes` | — | Returns space-separated list of mode names |
| `addItem` | `mode, label, description, icon, callback` | Push an item into a mode's buffer |
| `addItemWithId` | `mode, label, description, icon, callback, id` | Push an item with explicit id |
| `itemsReady` | `mode` | Flush the buffer and display items |

### Properties (read-only)

| Property | Type | Description |
|---|---|---|
| `activeMode` | string | Name of the current mode |
| `itemCount` | int | Number of visible (filtered) items |
| `selectedLabel` | string | Label of the highlighted item |
| `selectedCallback` | string | Callback of the highlighted item |
| `lastSelection` | string | Label of the last launched item |
