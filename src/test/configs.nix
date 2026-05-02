# Test-time qs configs. Only kh-bar needs overrides (Virtual-1 screen,
# fake /run/kh-headless fixtures, mock binaries). Other apps reuse the dev
# configs unchanged — they don't depend on hardware-specific paths or a
# specific screen name.
{
  pkgs,
  lib,
  dev,
  mocks,
}:
let
  bar = dev.mkBarConfig {
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

                CpuUsage  { id: cpuUsage;  path: "/run/kh-headless/proc/stat" }
                RamUsage  { id: ramUsage;  path: "/run/kh-headless/proc/meminfo" }
                GpuUsage  { id: gpuUsage;  cardPath: "/run/kh-headless/drm/device" }
                DiskUsage { id: diskUsage }
                CpuTemp   { id: cpuTemp;   sensor: "fake-cpu"; hwmonGlob: "/run/kh-headless/hwmon/hwmon*" }
                GpuTemp   { id: gpuTemp;   sensor: "fake-gpu"; hwmonGlob: "/run/kh-headless/hwmon/hwmon*" }

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
  };
in
{
  kh-bar-headless = bar;
  # The launcher's dev config already does the right thing — the headless
  # variant is currently identical, exposed under a `*-headless` alias for
  # naming symmetry with the bar. The screenshot harness relies on
  # XDG_DATA_DIRS (set in vm.nix) and the curated app fixture
  # (launcher-fixture.nix) to populate the Apps plugin.
  kh-launcher-headless = dev.packages.kh-launcher;
}
