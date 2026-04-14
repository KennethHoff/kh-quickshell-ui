# Codebase Structure

## Terminology

Use these terms consistently everywhere — code, comments, QML property names,
Nix options, README, ROADMAP, agent skills, commit messages, IPC target names:

| Term | Concept | Examples |
|---|---|---|
| **app** | Top-level Quickshell instance | `kh-bar`, `kh-launcher`, `kh-cliphist`, `kh-view` |
| **plugin** | Extension to any app (general) | — |
| **bar plugin** | Extension to the bar (`BarPlugin` subtype) | `Clock`, `Volume`, `Workspaces`, `ControlCenter` |
| **launcher plugin** | Extension to the launcher (mode, result provider, …) | window switcher mode, emoji picker mode, script mode |
| **popup** | Small transient near-widget thing | workspace preview thumbnail, help overlay (`?`) |
| **panel** | Sizeable secondary content area that opens on demand | Control Center, Calendar, Sonarr, Docker |
| **view** | Persistent content section within an app | cliphist detail view, diff viewer left/right views, file viewer panes |
| **overlay** | Full-screen modal UI (`Overlay.qml` + dimmed backdrop) | `kh-launcher`, `kh-cliphist`, `kh-view`; also the help popup within those apps |
| **mode** | Input/navigation state within an app | `insert`, `normal`, `visual`, `actions` |

**Plugin** is the general extensibility term across all apps. Qualify it with
the app name when the context is ambiguous — **bar plugin**, **launcher plugin**,
etc. Each app may define its own plugin contract; the bar's is `BarWidget`.
Apps that don't have a plugin system yet should be written as if they will.

When updating existing files, sweep for stale synonyms and replace them:
`daemon`, `orchestrator` → **app**;
`module`, `widget` (bar context) → **bar plugin**;
`BarWidget` → `BarPlugin` (rename file and all usages);
`dropdown` (bar context) → **panel**;
`detail panel`, `pane`, `side pane` → **view**;
`window` (modal context) → **overlay**.

---

## The Rule

> If a component is only used by one app, it lives inside that app's directory.
> If it is used by two or more apps, it lives in `lib/`.

**`lib/`** = cross-app reusables only.
**`apps/<app>/`** = everything owned by exactly one app.
**`apps/<app>/plugins/`** = built-in plugins for that app; same structure as any user-supplied plugin directory.
**`apps/bar/plugins/`** = built-in bar plugins; same structure as `extraPluginDirs`.

---

## Target Layout

```
apps/
  kh-bar.qml         # app: status bar (one window per screen)
  kh-launcher.qml    # app: application launcher overlay
  kh-cliphist.qml    # app: clipboard history overlay
  kh-view.qml        # app: file/image viewer

  bar/
    plugins/              # built-in bar plugins — same structure as extraPluginDirs
      Clock.qml
      ControlCenter.qml
      MediaPlayer.qml
      Tray.qml
      Volume.qml
      Workspaces.qml
    BarPlugin.qml         # plugin base class (renamed from BarWidget)
    BarRow.qml            # layout primitives
    BarSpacer.qml
    BarDropdown.qml       # panel infrastructure
    ControlPanel.qml
    ControlTile.qml
    DropdownDivider.qml
    DropdownHeader.qml
    DropdownItem.qml
    EthernetPanel.qml
    TailscalePanel.qml
    TailscalePeers.qml

  launcher/
    AppList.qml

  cliphist/
    ClipDelegate.qml
    CliphistEntry.qml     # ← move from lib/
    ClipList.qml
    ClipPreview.qml
    MetaStore.qml

lib/                      # cross-app reusables only
  FormatBytes.qml         # utility; used by multiple apps
  FuzzyScore.qml          # used by launcher + cliphist
  HelpFilter.qml          # used by HelpOverlay (shared)
  HelpOverlay.qml         # used by launcher + cliphist
  Overlay.qml             # used by HelpOverlay + cliphist
  SearchParser.qml        # used by launcher + cliphist
  TextStats.qml           # utility
  TextViewer.qml          # used by kh-view + kh-cliphist
```

---

## Implementation

### Key insight: source layout ≠ deployment layout

QML files see the **deployed** directory, not the source tree. Each app's
`pkgs.runCommand` in `flake.nix` assembles a flat `$out/` from multiple source
paths. **No QML import paths need to change** — only the `cp` source paths in
`flake.nix` need updating.

### File moves (git mv)

```bash
# rename qml/ → apps/
git mv qml apps

# bar plugins into apps/bar/plugins/
mkdir -p apps/bar/plugins
git mv apps/bar/Clock.qml         apps/bar/plugins/Clock.qml
git mv apps/bar/ControlCenter.qml apps/bar/plugins/ControlCenter.qml
git mv apps/bar/MediaPlayer.qml   apps/bar/plugins/MediaPlayer.qml
git mv apps/bar/Tray.qml          apps/bar/plugins/Tray.qml
git mv apps/bar/Volume.qml        apps/bar/plugins/Volume.qml
git mv apps/bar/Workspaces.qml    apps/bar/plugins/Workspaces.qml

# bar-specific infrastructure out of lib/
git mv lib/BarWidget.qml       apps/bar/BarPlugin.qml
git mv lib/BarRow.qml          apps/bar/BarRow.qml
git mv lib/BarSpacer.qml       apps/bar/BarSpacer.qml
git mv lib/BarDropdown.qml     apps/bar/BarDropdown.qml
git mv lib/ControlPanel.qml    apps/bar/ControlPanel.qml
git mv lib/ControlTile.qml     apps/bar/ControlTile.qml
git mv lib/DropdownDivider.qml apps/bar/DropdownDivider.qml
git mv lib/DropdownHeader.qml  apps/bar/DropdownHeader.qml
git mv lib/DropdownItem.qml    apps/bar/DropdownItem.qml
git mv lib/EthernetPanel.qml   apps/bar/EthernetPanel.qml
git mv lib/TailscalePanel.qml  apps/bar/TailscalePanel.qml
git mv lib/TailscalePeers.qml  apps/bar/TailscalePeers.qml

# launcher components
mkdir -p apps/launcher
git mv apps/AppList.qml apps/launcher/AppList.qml

# cliphist components
mkdir -p apps/cliphist
git mv apps/ClipDelegate.qml apps/cliphist/ClipDelegate.qml
git mv apps/ClipList.qml     apps/cliphist/ClipList.qml
git mv apps/ClipPreview.qml  apps/cliphist/ClipPreview.qml
git mv apps/MetaStore.qml    apps/cliphist/MetaStore.qml
git mv lib/CliphistEntry.qml apps/cliphist/CliphistEntry.qml
```

### flake.nix changes

Update `cp` source paths for each app to reflect the new `apps/` root and
subdirectory layout. The deployed `$out/` structure stays flat — only the
source paths change.

**`barConfig`** — plugins are now under `apps/bar/plugins/`:
```nix
# was: cp ${self}/qml/bar/*.qml $out/
cp ${self}/apps/bar/*.qml         $out/
cp ${self}/apps/bar/plugins/*.qml $out/
```

**`launcherConfig`**:
```nix
# was: cp ${self}/qml/AppList.qml $out/
cp ${self}/apps/launcher/AppList.qml $out/
```

**`cliphistConfig`**:
```nix
# was: cp ${self}/qml/Clip*.qml $out/ + cp ${self}/qml/MetaStore.qml $out/
cp ${self}/apps/cliphist/ClipDelegate.qml  $out/
cp ${self}/apps/cliphist/CliphistEntry.qml $out/
cp ${self}/apps/cliphist/ClipList.qml      $out/
cp ${self}/apps/cliphist/ClipPreview.qml   $out/
cp ${self}/apps/cliphist/MetaStore.qml     $out/
```

**`viewConfig`** — update root path from `qml/` to `apps/`; no other changes.

### Terminology sweep

After moving files, update all occurrences of stale terminology across:
- QML source files (comments, property names, string literals)
- Nix files (option names, comments)
- `README.md`, `ROADMAP.md`, `AGENTS.md`
- `.claude/skills/` skill files
- `docs/` files

Replace as per the terminology table at the top of this document.

### Verification

After the moves, flake edits, and terminology sweep, rebuild each app:

```bash
nix build .#kh-bar
nix build .#kh-launcher
nix build .#kh-cliphist
nix build .#kh-view
```

Check the deployed output:
```bash
ls result/      # for each app — should be flat, no subdirs
ls result/lib/  # should only contain cross-app lib files
```
