# Test-only bar config. Re-uses dev.nix's mkBarConfig but with:
#   - screen pinned to "Virtual-1" (vkms output name in the test VM)
#   - plugin properties pointing at /run/khtest/* fake files
#   - extraBins overridden with the mock binaries
#
# The structure is intentionally a near-copy of dev.nix's structure rather
# than a shared string — duplication keeps test stability decoupled from
# dev plumbing changes (a new dev-only plugin shouldn't auto-appear here).
{
  dev,
  mocks,
}:
dev.mkBarConfig {
  instances.testbar = {
    screen = "Virtual-1";
    structure = ''
      BarRow {
          Workspaces {}
          MediaPlayer {}
          BarSpacer {}
          BarGroup {
              label: "stats"
              ipcName: "stats"
              panelWidth: 320

              CpuUsage  { id: cpuUsage;  path: "/run/khtest/proc/stat" }
              RamUsage  { id: ramUsage;  path: "/run/khtest/proc/meminfo" }
              GpuUsage  { id: gpuUsage;  cardPath: "/run/khtest/drm/device" }
              DiskUsage { id: diskUsage }
              CpuTemp   { id: cpuTemp;   sensor: "fake-cpu"; hwmonGlob: "/run/khtest/hwmon/hwmon*" }
              GpuTemp   { id: gpuTemp;   sensor: "fake-gpu"; hwmonGlob: "/run/khtest/hwmon/hwmon*" }

              Column {
                  spacing: 8

                  Column {
                      spacing: 2
                      BarText { text: "usage"; color: mutedColor }
                      BarText { text: "  cpu · " + cpuUsage.usage   + "%" }
                      BarText { text: "  ram · " + ramUsage.percent + "%" }
                      BarText { text: "  gpu · " + gpuUsage.busy    + "% (" + gpuUsage.vramUsedMb + "M/" + gpuUsage.vramTotalMb + "M)" }
                  }

                  Column {
                      spacing: 2
                      BarText { text: "temperature"; color: mutedColor }
                      BarText {
                          text:  "  cpu · " + cpuTemp.temp + "°"
                          color: cpuTemp.temp >= 80 ? errorColor
                               : cpuTemp.temp >= 60 ? warnColor
                               :                      normalColor
                      }
                      BarText {
                          text:  "  gpu · " + gpuTemp.temp + "°"
                          color: gpuTemp.temp >= 80 ? errorColor
                               : gpuTemp.temp >= 60 ? warnColor
                               :                      normalColor
                      }
                  }

                  Column {
                      spacing: 2
                      BarText { text: "storage"; color: mutedColor }
                      Repeater {
                          model: diskUsage.results
                          BarText {
                              text: "  " + modelData.mount + " · "
                                  + Math.round(modelData.usedB  / 1e9) + "G/"
                                  + Math.round(modelData.totalB / 1e9) + "G"
                          }
                      }
                  }
              }
          }
          BarPipe {}
          Tray {}
          Notifications {}
          BarPipe {}
          Clock {}
          Volume {}
          BarPipe {}
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
      }
    '';
  };
  extraBins = {
    df = "${mocks}/bin/df";
    nmcli = "${mocks}/bin/nmcli";
    tailscale = "${mocks}/bin/tailscale";
    swayncClient = "${mocks}/bin/swaync-client";
  };
}
