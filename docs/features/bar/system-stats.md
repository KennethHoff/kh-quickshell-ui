# System Stats

Stats plugins are **data-only**: each polls a source and exposes readable
properties; users compose them with a sibling `BarText` to render the value.

- [1] ✅ `CpuUsage` — samples `/proc/stat`; exposes `usage: int`
- [2] ✅ `RamUsage` — reads `/proc/meminfo`; exposes Kb props and `percent`
- [3] ✅ AMD `GpuUsage` — reads `/sys/class/drm/<card>/device/*`; exposes busy/VRAM. Nvidia deferred
- [4] ✅ `DiskUsage` — `df -B1` every 60 s; per-mount used/total
- [5] ✅ `CpuTemp`/`GpuTemp` — walk `/sys/class/hwmon/*` for matching sensor; expose `temp: int` (°C)
