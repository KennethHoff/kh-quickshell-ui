# Visual Testing Roadmap

## What the QML-native rewrite enables

Previously, QML was Nix string templates — visual testing required a full Nix build to produce
runnable QML, coupling testing to the Nix toolchain.

Now that components are real `.qml` files, they can be instantiated directly in test code.
The `NixFFI.qml` stub in this repo provides **deterministic test values** (greyscale colors,
fixed font) so golden images remain stable across Stylix theme changes.

---

## Tier 1 — `qmltestrunner` + `grabImage()` (no compositor)

For components that only import `QtQuick` and `lib/` types, `qmltestrunner` with
`QT_QPA_PLATFORM=offscreen` can render and screenshot them without any compositor.

```qml
TestCase {
    name: "SearchBox visual"
    when: windowShown

    NixFFI    { id: ffi }
    SearchBox { id: subject; ffi: ffi; width: 400; height: 44 }

    function test_empty_state_snapshot() {
        var img = grabImage(subject)
        img.save("actual/searchbox-empty.png")
        // diff against goldens/searchbox-empty.png
    }
}
```

Golden images live in the repo. Diffs via `imagemagick compare` or `pixelmatch`.

**Scope:** Pure visual components — list delegates, search box, detail panel, etc. — once
extracted from Quickshell-specific parents.

---

## Tier 2 — Headless wlroots compositor (full shell)

`WlrLayershell`, `ShellRoot`, and `Process` require a real Wayland compositor.
Use a headless wlroots compositor, then capture with `grim` (wlr-screencopy protocol).

```bash
sway --config /dev/null &   # or: weston --backend=headless
WAYLAND_DISPLAY=wayland-1 quickshell -c kh-cliphist
grim -o headless actual/cliphist-open.png
imagemagick compare goldens/cliphist-open.png actual/cliphist-open.png diff.png
```

Because the source tree is real QML files, `quickshell` can run directly against it using
the stub `NixFFI.qml` — no Nix build needed to get runnable QML for testing.

**Scope:** Full panel rendering including layer shell positioning, backdrop, and animations.

---

## Why Playwright / Greenfield don't apply

- **Playwright** is browser automation only; it cannot capture or interact with Wayland surfaces.
- **Greenfield** (the browser-based Wayland compositor) only implements `core` + `xdg-shell`.
  It does not implement `zwlr_layer_shell_v1`, which Quickshell requires for `WlrLayershell`.

---

## Decision boundary

| Component imports        | Test method              |
|--------------------------|--------------------------|
| `QtQuick` + `lib/` only  | Tier 1 — `grabImage()`   |
| `Quickshell.Io.Process`  | Tier 1 with stubbed Process, or Tier 2 |
| `WlrLayershell` / `ShellRoot` | Tier 2 only         |
