# Curated XDG application fixture for the headless launcher.
#
# Produces a derivation with the standard XDG layout under $out/share:
#   share/applications/<id>.desktop      one entry per app, NoDisplay=false
#   share/icons/hicolor/scalable/apps/   per-app SVG, plus the
#     application-x-executable.svg fallback
#
# Pointing the VM's XDG_DATA_DIRS at this derivation gives the launcher's
# Apps plugin a deterministic set of items to show in screenshots, with
# matching SVG icons (no letter-tile fallbacks).
#
# Each .desktop also sets StartupWMClass to the binary that fake-clients.sh
# runs — when those are open, the hyprland-windows plugin can resolve their
# class to the same icon shown in the apps list, keeping both screenshots
# visually consistent.
{
  pkgs,
  lib,
}:
let
  apps = [
    {
      id = "kh-files";
      name = "Files";
      comment = "Browse and manage files";
      exec = "foot -a Files -T Files";
      class = "Files";
      icon = "kh-files";
      svg = ''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
          <rect x="6" y="14" width="52" height="42" rx="4" fill="#5c8bd6"/>
          <path d="M6 14h22l6 6h24v8H6z" fill="#3b6db5"/>
        </svg>
      '';
    }
    {
      id = "kh-browser";
      name = "Browser";
      comment = "Open the web browser";
      exec = "foot -a Browser -T Browser";
      class = "Browser";
      icon = "kh-browser";
      svg = ''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
          <circle cx="32" cy="32" r="26" fill="#e07a5f"/>
          <circle cx="32" cy="32" r="10" fill="#f4f1de"/>
          <path d="M32 6v52M6 32h52" stroke="#3d405b" stroke-width="2"/>
        </svg>
      '';
    }
    {
      id = "kh-terminal";
      name = "Terminal";
      comment = "A simple terminal emulator";
      exec = "foot -a Terminal -T Terminal";
      class = "Terminal";
      icon = "kh-terminal";
      svg = ''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
          <rect x="4" y="10" width="56" height="44" rx="4" fill="#1d3557"/>
          <path d="M14 26l8 6-8 6M26 38h16" stroke="#a8dadc" stroke-width="3" fill="none" stroke-linecap="round"/>
        </svg>
      '';
    }
    {
      id = "kh-calculator";
      name = "Calculator";
      comment = "Perform basic arithmetic";
      exec = "foot -a Calculator -T Calculator";
      class = "Calculator";
      icon = "kh-calculator";
      svg = ''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
          <rect x="10" y="6" width="44" height="52" rx="4" fill="#2a9d8f"/>
          <rect x="14" y="10" width="36" height="12" fill="#e9f5f3"/>
          <g fill="#e9f5f3">
            <rect x="14" y="26" width="8" height="8"/>
            <rect x="26" y="26" width="8" height="8"/>
            <rect x="38" y="26" width="8" height="8"/>
            <rect x="14" y="38" width="8" height="8"/>
            <rect x="26" y="38" width="8" height="8"/>
            <rect x="38" y="38" width="8" height="8"/>
            <rect x="14" y="50" width="8" height="4"/>
            <rect x="26" y="50" width="20" height="4"/>
          </g>
        </svg>
      '';
    }
    {
      id = "kh-music";
      name = "Music";
      comment = "Play your music library";
      exec = "foot -a Music -T Music";
      class = "Music";
      icon = "kh-music";
      svg = ''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
          <circle cx="32" cy="32" r="26" fill="#9d4edd"/>
          <path d="M28 18v22a6 6 0 1 1-4-5.6V20l16-4v18a6 6 0 1 1-4-5.6V14z" fill="#fff"/>
        </svg>
      '';
    }
    {
      id = "kh-settings";
      name = "Settings";
      comment = "Configure the system";
      exec = "foot -a Settings -T Settings";
      class = "Settings";
      icon = "kh-settings";
      svg = ''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
          <circle cx="32" cy="32" r="22" fill="#6c757d"/>
          <circle cx="32" cy="32" r="8" fill="#f8f9fa"/>
          <g fill="#6c757d" stroke="#f8f9fa" stroke-width="2">
            <rect x="29" y="4"  width="6" height="10"/>
            <rect x="29" y="50" width="6" height="10"/>
            <rect x="4"  y="29" width="10" height="6"/>
            <rect x="50" y="29" width="10" height="6"/>
          </g>
        </svg>
      '';
    }
    {
      id = "kh-mail";
      name = "Mail";
      comment = "Read your email";
      exec = "foot -a Mail -T Mail";
      class = "Mail";
      icon = "kh-mail";
      svg = ''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
          <rect x="4" y="14" width="56" height="36" rx="4" fill="#f4a261"/>
          <path d="M4 18l28 18 28-18" stroke="#3d405b" stroke-width="3" fill="none"/>
        </svg>
      '';
    }
    {
      id = "kh-photos";
      name = "Photos";
      comment = "Browse your photo library";
      exec = "foot -a Photos -T Photos";
      class = "Photos";
      icon = "kh-photos";
      svg = ''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
          <rect x="4" y="14" width="56" height="40" rx="3" fill="#264653"/>
          <circle cx="22" cy="32" r="8" fill="#e9c46a"/>
          <path d="M14 50l16-14 12 10 6-4 12 8v4H4z" fill="#2a9d8f"/>
          <rect x="20" y="8" width="24" height="8" rx="2" fill="#264653"/>
        </svg>
      '';
    }
  ];

  fallbackSvg = ''
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
      <rect x="6" y="6" width="52" height="52" rx="6" fill="#888"/>
      <path d="M22 22l20 20M42 22L22 42" stroke="#fff" stroke-width="4" stroke-linecap="round"/>
    </svg>
  '';

  mkDesktop =
    a:
    pkgs.writeText "${a.id}.desktop" ''
      [Desktop Entry]
      Type=Application
      Name=${a.name}
      Comment=${a.comment}
      Exec=${a.exec}
      Icon=${a.icon}
      Terminal=false
      StartupWMClass=${a.class}
      Categories=Utility;
    '';

  mkIcon = a: pkgs.writeText "${a.icon}.svg" a.svg;

  installLines = lib.concatMapStringsSep "\n" (a: ''
    install -Dm644 ${mkDesktop a} $out/share/applications/${a.id}.desktop
    install -Dm644 ${mkIcon a} $out/share/icons/hicolor/scalable/apps/${a.icon}.svg
  '') apps;
in
pkgs.runCommand "kh-launcher-fixture" { } ''
  ${installLines}
  install -Dm644 ${pkgs.writeText "fallback.svg" fallbackSvg} \
    $out/share/icons/hicolor/scalable/apps/application-x-executable.svg
''
