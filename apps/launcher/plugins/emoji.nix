# Launcher plugin: emoji picker.
#
# Source of truth:
#   - `pkgs.unicode-emoji` — authoritative emoji list (emoji-test.txt, v17.0).
#     Canonical status + name per glyph, maintained by Unicode.org.
#   - `pkgs.cldr-annotations` — authoritative multilingual keyword annotations
#     (annotations/en.xml, v48.2). Same source used by GTK/GNOME emoji pickers.
#
# Only `fully-qualified` status emoji are exposed — skin-tone / hair components
# and the minimally-qualified / unqualified alt forms would just pollute the
# picker.
#
# Enter copies the glyph to the Wayland clipboard via `wl-copy` (no trailing
# newline, to match what a literal emoji character in a text field looks like).
#
# The (emoji, name, keywords) triple is joined at Nix eval time so the scan
# script stays a trivial `cat` — the join cost is paid once per build instead
# of on every plugin activation.
#
# Returns: { plugins :: AttrSet }
{
  pkgs,
  lib,
}:
let
  emojiTestTxt = "${pkgs.unicode-emoji}/share/unicode/emoji/emoji-test.txt";
  cldrXml = "${pkgs.cldr-annotations}/share/unicode/cldr/common/annotations/en.xml";
  wlCopy = lib.getExe' pkgs.wl-clipboard "wl-copy";

  # Pre-join Unicode emoji-test.txt with CLDR keyword annotations into the
  # final launcher TSV (`label\tdescription\ticon\tcallback\tid`).
  emojiData = pkgs.runCommand "kh-emoji-data.tsv" { } ''
    ${pkgs.python3}/bin/python3 - > $out <<'PY'
    import re, xml.etree.ElementTree as ET

    EMOJI_TEST = "${emojiTestTxt}"
    CLDR_XML   = "${cldrXml}"
    WL_COPY    = "${wlCopy}"

    # cp → keyword list, drawn from CLDR annotations.  The "tts" variant is the
    # canonical name; the plain variant carries the pipe-separated keywords.
    # CLDR strips the FE0F variation selector from cp values, so we fall back
    # to an FE0F-less lookup when the exact key is missing.
    kws = {}
    root = ET.parse(CLDR_XML).getroot()
    ns = {"ldml": ""}
    for a in root.iter("annotation"):
        cp = a.get("cp")
        if not cp or a.get("type") == "tts" or not a.text:
            continue
        kws[cp] = ", ".join(part.strip() for part in a.text.split("|"))

    # Format: "<hex...> ; <status>  # <emoji> E<x>.<y> <name>"
    # Use the version marker as the anchor between glyph and name so a name
    # containing spaces (e.g. "face with tears of joy") round-trips cleanly.
    line_re = re.compile(r"^(.+?) E\d+\.\d+ (.+)$")

    with open(EMOJI_TEST, encoding="utf-8") as f:
        for raw in f:
            if "; fully-qualified" not in raw:
                continue
            rhs = raw.split("# ", 1)[-1].rstrip()
            m = line_re.match(rhs)
            if not m:
                continue
            emoji, name = m.group(1), m.group(2)
            kw = kws.get(emoji) or kws.get(emoji.replace("\ufe0f", "")) or ""
            callback = f"printf '%s' '{emoji}' | {WL_COPY}"
            # icon carries the glyph verbatim — Image won't load it, so the
            # delegate's text fallback renders it directly in the icon slot.
            print(f"{name}\t{kw}\t{emoji}\t{callback}\t{name}")
    PY
  '';

  scanScript = pkgs.writeShellScript "kh-scan-emoji" ''
    exec ${pkgs.coreutils}/bin/cat ${emojiData}
  '';
in
{
  plugins = {
    emoji = {
      script = toString scanScript;
      frecency = true;
      hasActions = false;
      placeholder = "Search emoji...";
      label = "Emoji";
      default = false;
      # Icon column carries the emoji glyph directly; the shared glyph
      # primitive renders it as centred text.
      iconDelegate = "LauncherIconGlyph.qml";
    };
  };
}
