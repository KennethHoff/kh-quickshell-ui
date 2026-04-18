# Stylix integration for kh-ui.
#
# Auto-imported alongside the main hm-module. When Stylix is present,
# sets programs.kh-ui.theme options from the Stylix palette and fonts.
# When Stylix is absent, this module does nothing.
{
  config,
  lib,
  ...
}:
let
  stylixAvailable =
    (config ? lib)
    && (config.lib ? stylix)
    && (config.lib.stylix ? colors)
    && (config ? stylix)
    && (config.stylix ? fonts);
in
{
  config = lib.mkIf (config.programs.kh-ui.enable && stylixAvailable) {
    programs.kh-ui.theme = {
      colors = lib.mkDefault config.lib.stylix.colors;
      fontName = lib.mkDefault config.stylix.fonts.sansSerif.name;
      fontSize = lib.mkDefault config.stylix.fonts.sizes.applications;
    };
  };
}
