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

- [Apps](launcher/apps.md) — fuzzy search over installed `.desktop` apps
- [Window switcher](launcher/window-switcher.md) — fuzzy-focus open windows (Hyprland)
- [Emoji picker](launcher/emoji-picker.md) — search emoji by name; copy to clipboard
- [Snippets](launcher/snippets.md) — abbreviation-triggered text expansion
- [System commands](launcher/system-commands.md) — lock, sleep, reboot as actions
- [Color picker](launcher/color-picker.md) *(long term)* — screen dropper
- [File search](launcher/file-search.md) *(long term)* — `fd`/`fzf` over `$HOME`
