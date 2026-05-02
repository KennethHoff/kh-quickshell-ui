# Materialise /run/kh-headless/* with deterministic content. The test bar instance
# points the CPU/RAM/GPU/temp plugins at these files instead of the real
# /proc, /sys/class/drm, /sys/class/hwmon paths.
#
# Values chosen to look plausible and stable:
#   CPU usage  ~30% (after the second tick, given the rolling-delta math)
#   RAM        8 GB used / 32 GB total (≈25%)
#   GPU        42% busy, 6 GB / 24 GB VRAM
#   CPU temp   55°C
#   GPU temp   65°C
#
# Single-line `f` rules with `\n` escapes keep the rule list compact; tmpfiles
# evaluates the content as-is.
_:
let
  # Two snapshots of /proc/stat would be the realistic mock (so the rolling
  # delta produces a stable 30%), but FileView reads the same file on every
  # tick — the plugin computes (delta_total - delta_idle) / delta_total. With
  # a static file the deltas are zero after the first sample. That's fine:
  # the bar shows 0% on the very first tick and 0% on every tick after,
  # because there's no movement. To force a non-zero reading, we'd need
  # to rotate the file's content — out of scope for fake-fs static rules.
  #
  # Trade-off accepted: CPU column shows 0% in screenshots. RAM is unaffected
  # (it's an absolute reading, not a delta).
  procStat = "cpu  100000 0 50000 850000 0 0 0 0 0 0";
  procMeminfo = ''
    MemTotal:       32768000 kB
    MemFree:        18000000 kB
    MemAvailable:   24576000 kB
    Buffers:          512000 kB
    Cached:          5000000 kB
  '';
in
{
  systemd.tmpfiles.rules = [
    "d /run/kh-headless                       0755 root root -"
    "d /run/kh-headless/proc                  0755 root root -"
    "d /run/kh-headless/drm                   0755 root root -"
    "d /run/kh-headless/drm/device            0755 root root -"
    "d /run/kh-headless/hwmon                 0755 root root -"
    "d /run/kh-headless/hwmon/hwmon0          0755 root root -"
    "d /run/kh-headless/hwmon/hwmon1          0755 root root -"

    "f+ /run/kh-headless/proc/stat                       0444 root root - ${procStat}"
    "f+ /run/kh-headless/proc/meminfo                    0444 root root - ${
      builtins.replaceStrings [ "\n" ] [ "\\n" ] procMeminfo
    }"
    "f+ /run/kh-headless/drm/device/gpu_busy_percent     0444 root root - 42"
    "f+ /run/kh-headless/drm/device/mem_info_vram_used   0444 root root - 6442450944"
    "f+ /run/kh-headless/drm/device/mem_info_vram_total  0444 root root - 25769803776"
    "f+ /run/kh-headless/hwmon/hwmon0/name               0444 root root - fake-cpu"
    "f+ /run/kh-headless/hwmon/hwmon0/temp1_input        0444 root root - 55000"
    "f+ /run/kh-headless/hwmon/hwmon1/name               0444 root root - fake-gpu"
    "f+ /run/kh-headless/hwmon/hwmon1/temp1_input        0444 root root - 65000"
  ];
}
