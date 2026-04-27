# Launcher

Extensible modal launcher (`quickshell -c kh-launcher`). Each **launcher plugin**
registers a named item source (apps, open windows, emoji, …); `]` / `[` cycles
between them, Enter picks an item. The built-in **Apps** plugin has no
special-casing — it is registered alongside user-defined plugins through the
same contract.

## Core

- [1] ✅ Fuzzy search over item `label + description`
- [2] ✅ Filters: `'` exact, `^` prefix, `$` suffix, `!` negation
- [3] ✅ Description shown one line below the label
- [4] ✅ `j`/`k` navigate, `Enter` confirm; opens in insert mode
- [5] ✅ Window closes after selection
- [6] ✅ Green flash animation on selection
- [7] ✅ `?` searchable help overlay; state-aware sections
- [8] ✅ Per-item icons rendered in the list row
- [9] ✅ Plugin switching — `]`/`[` cycle, click chip; full IPC
- [10] ✅ Script plugins — push items via TSV stdout or IPC; Nix opt `programs.kh-ui.launcher.scriptPlugins`
- [11] ⬜ Combi plugin *(depends on 10)* — concatenate multiple sources rofi-style; per-source tagging and Enter semantics
- [12] ✅ Plugin-owned keybindings — Core handles only navigation; plugins declare bindings as shell templates with `{callback}` substitution; inline `helpKey`/`helpDesc` per binding. See [docs/reference/launcher.md](../reference/launcher.md)
- [13] ⬜ Plugin-owned ranking — current frecency counter is the only ranking signal; window switcher wants Hyprland focus order, snippets want alphabetical. Expose ranking as a per-plugin hook
- [14] ✅ Plugin label distinct from IPC key — `label` (chip text) defaults to the stable attribute-name `key`; lets `hyprland-windows` show as `Windows`. See [docs/reference/launcher.md](../reference/launcher.md)

## Plugins

### Apps *(default, built-in)*

Fuzzy search over installed `.desktop` applications; Enter launches.

- [1] ✅ Haystack is `name + comment` from `.desktop` entries
- [2] ✅ App icons in row — XDG resolution, SVG/PNG, label fallback
- [3] ✅ `Terminal=true` apps wrap in configured terminal
- [4] ✅ Ctrl+1–9 launches on workspace 1–9 *(see Core [12])*
- [5] ✅ Frecency ranking — per-app decayed counter (`3·log2(1+count)` boost, 14 d half-life); empty query sorts by decayed count *(see Core [13])*
- [6] ✅ `l`/Tab enters actions state (only if app has actions)
- [7] ✅ `j`/`k` navigate actions, `Enter` launches, `h`/Esc returns
- [8] ✅ Action rows show parent app's icon

### Window switcher

Compositor-specific — each compositor needs its own data source and focus
dispatch, so they ship as separate plugins.

- [1] ✅ **Hyprland window switcher** — IPC key `hyprland-windows`, chip label `Windows`. Fuzzy search over all open windows; Enter focuses via `hyprctl dispatch focuswindow address:<addr>`; sorted by `focusHistoryID`; icons via `StartupWMClass`
- [2] ⬜ Per-item lifecycle keybinds — Quit, Force Quit, move-to-workspace

### Emoji picker

- [1] ✅ Fuzzy search emoji by name; Enter copies to clipboard. Glyphs from `pkgs.unicode-emoji` joined with `pkgs.cldr-annotations` at Nix eval time. Renders via plugin-owned `iconDelegate` (`LauncherIconGlyph.qml`). Frecency enabled. ~3944 items (Unicode 17.0)

### Snippets

- [1] ⬜ Text expansion triggered by abbreviation

### System commands

- [1] ⬜ Lock, sleep, reboot, etc. as searchable actions

### Color picker *(long term)*

- [1] ⬜ Screen dropper; Enter copies hex/rgb to clipboard

### File search *(long term)*

- [1] ⬜ `fd`/`fzf` over `$HOME`; Enter opens in default app
