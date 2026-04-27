# Apps

Fuzzy search over installed `.desktop` applications; Enter launches.

- [1] ✅ Haystack is `name + comment` from `.desktop` entries
- [2] ✅ App icons in row — XDG resolution, SVG/PNG, label fallback
- [3] ✅ `Terminal=true` apps wrap in configured terminal
- [4] ✅ Ctrl+1–9 launches on workspace 1–9 *(see [Launcher Core](../launcher.md#core) [12])*
- [5] ✅ Frecency ranking — per-app decayed counter (`3·log2(1+count)` boost, 14 d half-life); empty query sorts by decayed count *(see [Launcher Core](../launcher.md#core) [13])*
- [6] ✅ `l`/Tab enters actions state (only if app has actions)
- [7] ✅ `j`/`k` navigate actions, `Enter` launches, `h`/Esc returns
- [8] ✅ Action rows show parent app's icon
