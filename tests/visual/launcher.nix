# Visual test cases for kh-launcher.
# Each case: { name, description, calls } where calls are IPC strings.
# Run all cases: nix run .#test-launcher
# Run one case:  nix run .#test-launcher -- <name>
[
  {
    name        = "default";
    description = "Launcher opens in insert mode showing all apps";
    calls       = [];
  }
  {
    name        = "search";
    description = "Fuzzy search filters the app list";
    calls       = [ "type chrome" ];
  }
  {
    name        = "normal-mode";
    description = "Normal mode shows NOR badge with app selected";
    calls       = [ "setMode normal" ];
  }
  {
    name        = "actions-chrome";
    description = "Tab on Google Chrome enters Actions mode with both desktop actions visible";
    calls       = [ "type chrome" "enterActionsMode" ];
  }
  {
    name        = "actions-no-stale-cache";
    description = "After viewing Chrome actions, Tab on Rider (no actions) must stay in normal mode";
    calls       = [ "type chrome" "enterActionsMode" "key escape" "nav down" "enterActionsMode" ];
  }
]
