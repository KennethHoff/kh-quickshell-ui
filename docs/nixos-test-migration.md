# nixosTest Migration Roadmap

Research on replacing the existing `nix run .#screenshot` testing infrastructure
with one based on `nixosTest` / `build-vm`.

---

## 1. What the existing infrastructure actually is

The "tests" are a single `nix run .#screenshot` shell script (`flake.nix` lines 228–339). It:

1. Starts headless Sway: `WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_HEADLESS_OUTPUTS=1`
2. Polls `$xdg_runtime/wayland-*` in a 40-iteration loop (100ms sleep each) to detect the socket
3. Backgrounds `quickshell -p ${config}` and captures its PID
4. If the app has a target: retries `qs ipc --pid $pid call $target toggle` in a 30-iteration loop
5. Sleeps 0.4s after IPC calls to let animations settle
6. Runs `grim $outfile` to capture the Wayland framebuffer
7. Kills quickshell and sway, cleans up

The nixosTest migration must replicate all of this inside a QEMU VM, driven by Python instead of bash.

---

## 2. `nixosTest` fundamentals

### 2.1 Basic anatomy

```nix
pkgs.testers.nixosTest {
  name = "my-test";

  nodes.machine = { pkgs, config, ... }: {
    # Full NixOS module — any option that works in a NixOS config works here
    virtualisation.memorySize = 1024; # MB
    environment.systemPackages = [ pkgs.hello ];
  };

  # Pure Python 3 string. The test driver is imported as a library.
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("hello")
  '';
}
```

The output of `pkgs.testers.nixosTest` is a derivation. Build it with:
```bash
nix build .#checks.x86_64-linux.my-test
```
or run as a `nix flake check` by placing it in `checks.${system}`.

### 2.2 Full Python driver API (everything you'll need)

```python
machine.start()                                     # boot the VM
machine.wait_for_unit("foo.service")                # wait for systemd unit to be active
machine.wait_for_file("/path/to/file")              # wait for file to appear
machine.succeed("cmd")                              # run, assert exit 0, return stdout
machine.execute("cmd")                              # run, return (exit_code, stdout) — never fails
machine.fail("cmd")                                 # run, assert non-zero
machine.wait_until_succeeds("cmd", timeout=60)      # retry until exit 0
machine.wait_until_fails("cmd", timeout=60)         # retry until non-zero
machine.screenshot("name")                          # QEMU framebuffer dump (not grim) → $out/name.png
machine.copy_from_vm("/vm/path", "")               # copy file from VM into derivation $out
machine.wait_for_text("regex")                      # OCR — requires enableOCR = true
machine.send_key("ctrl-v")                          # send key event to VM framebuffer
machine.send_chars("hello")                         # type string into VM
machine.sleep(seconds)                              # sleep (this method exists in recent nixpkgs)
machine.log("message")                              # log to test output
```

**Critical**: `machine.succeed("cmd &")` — the `&` works. The shell running the command exits
immediately, backgrounded process stays alive. PID capture works:
`machine.succeed("cmd & echo $!")` returns the PID.

**All commands run as root inside the VM.** Use `su testuser -c 'cmd'` or
`sudo -u testuser env VAR=val cmd` to run as another user.

### 2.3 `enableOCR`

```nix
pkgs.testers.nixosTest {
  name = "test";
  enableOCR = true;  # adds Tesseract ~300MB to the closure
  nodes.machine = { ... }: { };
  testScript = ''
    machine.wait_for_text(r"\d\d:\d\d")  # regex match on screen text
  '';
}
```

OCR captures the QEMU framebuffer, not Wayland output. For headless Wayland, the framebuffer is
black. **OCR does not work on headless Wayland output.** Use `grim` inside the VM and
`machine.copy_from_vm` instead.

### 2.4 `machine.copy_from_vm`

```python
machine.copy_from_vm("/tmp/shot.png")
# → file appears in $out/shot.png (the test derivation's output directory)
```

After `nix build`, `ls result/` shows the copied files. This is how screenshots become Nix outputs.

### 2.5 Interactive driver (essential for development)

```bash
# Build the interactive driver:
nix build .#checks.x86_64-linux.kh-osd-test.driverInteractive

# Run it:
./result/bin/nixos-test-driver --interactive
```

You get a Python REPL with the `machine` object. You can call any driver method manually, debug
timing issues, try grim captures, etc.

---

## 3. Headless Wayland setup inside a VM

The existing screenshot script gives you the exact recipe. Translated to nixosTest:

### 3.1 NixOS module side

```nix
nodes.machine = { pkgs, ... }: {
  virtualisation.memorySize = 1536;

  users.users.testuser = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "audio" "video" ];
  };

  environment.systemPackages = [
    pkgs.sway
    pkgs.grim
    pkgs.quickshell
  ];

  # Same fonts as the screenshot script
  fonts.packages = [
    pkgs.dejavu_fonts
    pkgs.nerd-fonts.symbols-only
  ];

  # Hermetic fontconfig — same alias as the screenshot script
  fonts.fontconfig.defaultFonts.monospace = [ "DejaVu Sans Mono" ];
};
```

### 3.2 Test script side — starting Sway

```python
machine.start()
machine.wait_for_unit("multi-user.target")

# Create XDG_RUNTIME_DIR (logind normally does this on login; we don't have a PAM session)
machine.succeed("install -d -o testuser -m 700 /run/user/1000")

# Sway config: headless output with fixed resolution
machine.succeed("echo 'output HEADLESS-1 resolution 3840x2160' > /tmp/sway.conf")

# Start sway as testuser
machine.succeed(
    "su testuser -c '"
    "  XDG_RUNTIME_DIR=/run/user/1000"
    "  WLR_BACKENDS=headless"
    "  WLR_RENDERER=pixman"
    "  WLR_HEADLESS_OUTPUTS=1"
    "  sway --config /tmp/sway.conf"
    "' &>/tmp/sway.log &"
)

# Wait for Wayland socket — mirrors the 40-iteration loop in the screenshot script
machine.wait_until_succeeds(
    "ls /run/user/1000/wayland-* 2>/dev/null | grep -v '\\.lock$' | head -1 | grep .",
    timeout=20
)

# Get the socket name
wayland_display = machine.succeed(
    "ls /run/user/1000/wayland-* | grep -v lock | head -1 | xargs basename"
).strip()
# wayland_display is now e.g. "wayland-0" or "wayland-1"
```

**Gotcha**: `machine.succeed("cmd &")` with the `&` inside `su -c '...'` is tricky. The shell
inside `su -c '...'` must be told to background, and `su` must exit. The `&` after the closing `'`
puts the *su process* in the background from root's perspective. Both approaches work but test
carefully.

**Gotcha**: `install -d -o testuser -m 700` is cleaner than `mkdir -p && chown && chmod` for
creating the runtime dir.

### 3.3 Starting Quickshell

Quickshell configs are Nix derivations (built at eval time in the flake's `let` block). Make them
available in the VM via `environment.etc`:

```nix
nodes.machine = { pkgs, ... }: {
  # ...
  environment.etc."kh-osd-config".source = osdConfig;
  # osdConfig is the derivation from the flake.nix let block, in scope here
};
```

Then in the test script:

```python
qs_env = (
    f"XDG_RUNTIME_DIR=/run/user/1000 "
    f"WAYLAND_DISPLAY={wayland_display} "
)

machine.succeed(
    f"su testuser -c '"
    f"  {qs_env}"
    f"  quickshell -p /etc/kh-osd-config"
    f"' &>/tmp/qs.log & echo $! > /tmp/qs.pid"
)
qs_pid = machine.succeed("cat /tmp/qs.pid").strip()
```

**Gotcha**: The `echo $! > /tmp/qs.pid` must be OUTSIDE the `su -c '...'` quotes so the outer
shell (root) gets the backgrounded su PID. Then `quickshell --pid` can be set to that. But
actually: if sway is child of su and su is child of root shell, the quickshell PID is a grandchild
and you won't capture it.

**Better pattern** — use a wrapper script:

```python
machine.succeed(
    "cat > /tmp/run-qs.sh << 'SCRIPT'\n"
    "#!/bin/sh\n"
    "export XDG_RUNTIME_DIR=/run/user/1000\n"
    f"export WAYLAND_DISPLAY={wayland_display}\n"
    "quickshell -p /etc/kh-osd-config &\n"
    "echo $! > /tmp/qs.pid\n"
    "SCRIPT\n"
    "chmod +x /tmp/run-qs.sh"
)
machine.succeed("su testuser -c '/tmp/run-qs.sh'")
qs_pid = machine.succeed("cat /tmp/qs.pid").strip()
```

### 3.4 IPC retry — mirrors the 30-iteration loop

```python
# mirrors: for i in $(seq 30); do sleep 0.1; qs ipc --pid $pid call target fn && break; done
machine.wait_until_succeeds(
    f"su testuser -c '"
    f"  env {qs_env}"
    f"  quickshell ipc --pid {qs_pid} call osd showVolume 75"
    f"'",
    timeout=10
)
```

**Gotcha**: `quickshell ipc --pid N` uses the PID to find the Unix socket at
`/run/user/1000/quickshell/pid-N/`. If the env/UID mismatch, it won't find it. The `su testuser`
ensures the right UID.

### 3.5 Screenshot with grim

```python
# Settle delay — mirrors "sleep 0.4" in the screenshot script
machine.sleep(0.5)

machine.succeed(
    f"su testuser -c '"
    f"  env {qs_env}"
    f"  grim /tmp/shot.png"
    f"'"
)

machine.copy_from_vm("/tmp/shot.png")
```

---

## 4. Per-app specifics and gotchas

### 4.1 `kh-osd`

**Works under headless Sway.** The OSD uses `WlrLayershell` (Sway supports wlr-layer-shell-v1).

**Critical gotcha**: The OSD panel starts with `opacity: 0.0` and only becomes visible after an IPC
trigger. If you screenshot before calling `showVolume`, you get a transparent window and grim
captures just the desktop background.

**Correct sequence**: trigger IPC → settle → screenshot.

The OSD also subscribes to `Pipewire.defaultAudioSink`. Without PipeWire running, `audio.valid` is
false, which is fine — the IPC path (`showVolume`, `showMuted`) works independently without
PipeWire.

**PipeWire not needed** for IPC-driven OSD tests. The reactive path (volume scroll triggering OSD)
does need PipeWire if you want to test it:

```nix
services.pipewire = {
  enable = true;
  pulse.enable = true;
};
hardware.pulseaudio.enable = false; # must be false when pipewire is used
```

### 4.2 `kh-view`

**Works under headless Sway.** No Hyprland dependencies.

Seeding files:

```python
machine.succeed("echo 'Hello from kh-view test' > /tmp/test-file.txt")
machine.succeed("echo /tmp/test-file.txt > /tmp/kh-view-list.txt")
```

`kh-view` reads `KH_VIEW_LIST` from the environment at startup:

```python
machine.succeed(
    f"su testuser -c '"
    f"  {qs_env}"
    f"  KH_VIEW_LIST=/tmp/kh-view-list.txt"
    f"  quickshell -p /etc/kh-view-config"
    f"' &>/tmp/qs.log &"
    " echo $! > /tmp/qs.pid"
)
```

`kh-view` has no IPC toggle (it opens immediately). Use `machine.sleep(2)` to wait for rendering
instead of the IPC retry loop.

### 4.3 `kh-cliphist`

**Works under headless Sway.** No Hyprland dependencies.

Seeding the cliphist database:

```python
# cliphist store reads from stdin. Each call adds one entry.
machine.succeed(
    f"su testuser -c '"
    f"  {qs_env}"
    f"  echo -n \"Hello Clipboard\" | cliphist store"
    f"'"
)
machine.succeed(
    f"su testuser -c '"
    f"  {qs_env}"
    f"  echo -n \"Second entry\" | cliphist store"
    f"'"
)
```

Cliphist stores its database at `$XDG_DATA_HOME/cliphist/db` (default
`~testuser/.local/share/cliphist/db`). You must have `cliphist` in `environment.systemPackages`.

The IPC target is `viewer`:

```python
machine.wait_until_succeeds(
    f"su testuser -c '{qs_env} quickshell ipc --pid {qs_pid} call viewer toggle'",
    timeout=10
)
```

**Gotcha**: The `cliphistDecodeAll` script is a wrapper that calls `cliphist list` and
`cliphist decode`. In the VM, these must be real binaries from the Nix store. Use the same config
derivation from the flake (`cliphistConfig`) which already embeds the right paths.

**Gotcha**: `MetaStore.qml` reads/writes to `$XDG_DATA_HOME/kh-cliphist/`. Ensure `testuser` has a
proper `HOME` and `XDG_DATA_HOME`.

### 4.4 `kh-launcher`

**Partially works under headless Sway.** The launcher UI starts without Hyprland, but
`impl.launchApp` calls `bin.hyprctl dispatch exec ...` for workspace-qualified launches. The
launcher *opens and displays* fine; IPC launch will fail for workspace mode.

For screenshot tests (not functional launch tests), this is acceptable:

```python
machine.wait_until_succeeds(
    f"su testuser -c '{qs_env} quickshell ipc --pid {qs_pid} call launcher toggle'",
    timeout=10
)
# Type a search term via IPC:
machine.succeed(
    f"su testuser -c '{qs_env} quickshell ipc --pid {qs_pid} call launcher type firefox'"
)
machine.sleep(0.5)
# Screenshot
```

The `scanApps` script reads `.desktop` files from `$XDG_DATA_DIRS`. In the VM, you need some apps
installed to have results:

```nix
environment.systemPackages = [
  pkgs.firefox  # or any app with a .desktop file
  pkgs.xterm
];
```

Or you can write fake `.desktop` files manually into the VM.

### 4.5 `kh-bar`

**Does NOT work under headless Sway.** `kh-bar.qml` imports `Quickshell.Hyprland` and uses
`HyprlandIpc`. This is a hard runtime failure, not a soft degradation — Quickshell will fail to
connect to Hyprland and crash or hang.

This requires either:

1. VKMS + Hyprland (see §8 below)
2. A mock/stub approach (Quickshell doesn't support this)
3. Defer bar testing until VKMS is available

---

## 5. Wiring config derivations into the VM

The config derivations (`osdConfig`, `barConfig`, etc.) are already built in the `let` block of
`flake.nix`. You can reference them directly in the nixosTest since both live in the same file's
scope.

**Option A — `environment.etc` (recommended)**:

```nix
nodes.machine = { ... }: {
  environment.etc."kh-osd-config".source = osdConfig;
  # Accessible at /etc/kh-osd-config inside the VM
};
```

**Option B — package in PATH**:

```nix
environment.systemPackages = [
  (pkgs.writeShellScriptBin "run-kh-osd" ''
    exec ${pkgs.quickshell}/bin/quickshell -p ${osdConfig}
  '')
];
```

**Option C — symlink in `/var`**:

```nix
systemd.tmpfiles.rules = [
  "L+ /var/kh-osd-config - - - - ${osdConfig}"
];
```

Option A is recommended because `environment.etc` is idiomatic and the path is predictable.

---

## 6. The `mkVmTest` helper (what it should look like)

```nix
# tests/lib.nix
{ pkgs, lib }:

let
  baseModule = { pkgs, ... }: {
    virtualisation.memorySize = 1536;
    users.users.testuser = {
      isNormalUser = true;
      uid = 1000;
      extraGroups = [ "audio" "video" ];
    };
    environment.systemPackages = [ pkgs.sway pkgs.grim pkgs.quickshell pkgs.cliphist ];
    fonts.packages = [ pkgs.dejavu_fonts pkgs.nerd-fonts.symbols-only ];
    fonts.fontconfig.defaultFonts.monospace = [ "DejaVu Sans Mono" ];
  };

  swayBootstrap = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("install -d -o testuser -m 700 /run/user/1000")
    machine.succeed("echo 'output HEADLESS-1 resolution 1920x1080' > /tmp/sway.conf")
    machine.succeed(
        "su testuser -c '"
        "  XDG_RUNTIME_DIR=/run/user/1000"
        "  WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_HEADLESS_OUTPUTS=1"
        "  sway --config /tmp/sway.conf"
        "' &>/tmp/sway.log &"
    )
    machine.wait_until_succeeds(
        "ls /run/user/1000/wayland-* 2>/dev/null | grep -v '\\.lock$' | head -1 | grep .",
        timeout=20
    )
    wayland = machine.succeed(
        "ls /run/user/1000/wayland-* | grep -v lock | head -1 | xargs basename"
    ).strip()
    qs_env = f"XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY={wayland}"
  '';

in
{
  mkVmTest = { name, appConfig, target, extraModule ? { }, testScript }:
    pkgs.testers.nixosTest {
      inherit name;
      nodes.machine = lib.mkMerge [
        baseModule
        ({ ... }: { environment.etc."qs-config".source = appConfig; })
        extraModule
      ];
      testScript = swayBootstrap + testScript;
    };
}
```

---

## 7. Complete working example: kh-osd test

```nix
# tests/kh-osd.nix
{ pkgs, osdConfig }:

pkgs.testers.nixosTest {
  name = "kh-osd-screenshot";

  nodes.machine = { pkgs, ... }: {
    virtualisation.memorySize = 1536;
    users.users.testuser = {
      isNormalUser = true;
      uid = 1000;
      extraGroups = [ "audio" "video" ];
    };
    environment.systemPackages = [ pkgs.sway pkgs.grim pkgs.quickshell ];
    fonts.packages = [ pkgs.dejavu_fonts pkgs.nerd-fonts.symbols-only ];
    fonts.fontconfig.defaultFonts.monospace = [ "DejaVu Sans Mono" ];
    environment.etc."kh-osd-config".source = osdConfig;
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("install -d -o testuser -m 700 /run/user/1000")
    machine.succeed("echo 'output HEADLESS-1 resolution 1920x1080' > /tmp/sway.conf")

    machine.succeed(
        "su testuser -c '"
        "  XDG_RUNTIME_DIR=/run/user/1000"
        "  WLR_BACKENDS=headless"
        "  WLR_RENDERER=pixman"
        "  WLR_HEADLESS_OUTPUTS=1"
        "  sway --config /tmp/sway.conf"
        "' &>/tmp/sway.log &"
    )

    machine.wait_until_succeeds(
        "ls /run/user/1000/wayland-* 2>/dev/null | grep -v '\\.lock$' | head -1 | grep .",
        timeout=20
    )

    wayland = machine.succeed(
        "ls /run/user/1000/wayland-* | grep -v lock | head -1 | xargs basename"
    ).strip()
    qs_env = f"XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY={wayland}"

    # Launch quickshell via wrapper so we capture the real qs PID
    machine.succeed(
        "cat > /tmp/run-qs.sh << 'SCRIPT'\n"
        "#!/bin/sh\n"
        f"export {qs_env}\n"
        "quickshell -p /etc/kh-osd-config &\n"
        "echo $! > /tmp/qs.pid\n"
        "SCRIPT\n"
        "chmod +x /tmp/run-qs.sh"
    )
    machine.succeed("su testuser -c '/tmp/run-qs.sh'")
    qs_pid = machine.succeed("cat /tmp/qs.pid").strip()

    # IPC retry — like the screenshot script's 30-iteration loop
    machine.wait_until_succeeds(
        f"su testuser -c '"
        f"  env {qs_env}"
        f"  quickshell ipc --pid {qs_pid} call osd showVolume 75"
        f"'",
        timeout=15
    )

    machine.sleep(0.5)

    machine.succeed(f"su testuser -c 'env {qs_env} grim /tmp/osd-75.png'")
    machine.copy_from_vm("/tmp/osd-75.png")

    # Second shot: muted
    machine.succeed(
        f"su testuser -c 'env {qs_env} quickshell ipc --pid {qs_pid} call osd showMuted'"
    )
    machine.sleep(0.5)
    machine.succeed(f"su testuser -c 'env {qs_env} grim /tmp/osd-mute.png'")
    machine.copy_from_vm("/tmp/osd-mute.png")
  '';
}
```

---

## 8. Integrating into `flake.nix`

```nix
outputs = { self, nixpkgs }:
  let
    # ... existing let bindings (pkgs, osdConfig, barConfig, etc.) ...
  in
  {
    # ... existing outputs ...

    checks.${system} = {
      kh-osd-screenshot      = import ./tests/kh-osd.nix      { inherit pkgs osdConfig; };
      kh-view-screenshot     = import ./tests/kh-view.nix     { inherit pkgs viewConfig; };
      kh-cliphist-screenshot = import ./tests/kh-cliphist.nix { inherit pkgs cliphistConfig; };
      kh-launcher-screenshot = import ./tests/kh-launcher.nix { inherit pkgs launcherConfig; };
    };
  };
```

**Gotcha — the `self` reference**: The existing `mkAppConfig` uses `${self}/apps/...` and
`${self}/lib/...`. Since `self` is the git-tracked source tree, **any new `tests/*.nix` file you
add must be `git add`-ed before `nix build` will see it**. This is documented in the project's
agent notes and is a critical gotcha.

---

## 9. GitHub Actions

### 9.1 KVM enablement

GitHub `ubuntu-latest` runners have KVM available but the `/dev/kvm` device permissions need
fixing:

```yaml
name: NixOS VM Tests
on: [push, pull_request]

jobs:
  vm-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Enable KVM group perms
        run: |
          echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' \
            | sudo tee /etc/udev/rules.d/99-kvm4all.rules
          sudo udevadm control --reload-rules
          sudo udevadm trigger --name-match=kvm

      - uses: DeterminateSystems/nix-installer-action@main

      - uses: DeterminateSystems/magic-nix-cache-action@main
        # Free binary cache from Determinate — caches Nix closure builds in CI

      - name: Run VM tests
        run: |
          nix build \
            .#checks.x86_64-linux.kh-osd-screenshot \
            .#checks.x86_64-linux.kh-view-screenshot \
            -j2

      - name: Upload screenshots
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: screenshots-${{ github.sha }}
          path: result*/
```

**Gotcha**: `nix build` with multiple outputs creates `result`, `result-2`, etc. The `result*/`
glob in `path:` captures all of them.

**Gotcha**: Without the udev KVM rules, Nix's QEMU will use TCG emulation (software CPU) which is
~100x slower. A test that takes 30s with KVM may take 50 minutes without it.

### 9.2 Confirming KVM is available

```bash
# In CI, check before running:
ls -la /dev/kvm
```

If absent, the test still runs but through TCG. Add `virtualisation.qemu.options = [ "-enable-kvm" ]`
to the test module to force KVM (will fail fast if unavailable rather than silently slow).

---

## 10. Known gotchas and things to verify

### 10.1 `WlrLayershell` needs wlr-layer-shell-unstable-v1

Sway supports this protocol. Verify by checking `sway --version` in nixpkgs. The version in this
flake's `nixos-unstable` pin is current and supports it.

### 10.2 `quickshell -p` vs `quickshell -c`

- `-p <path>`: Use an explicit config directory (used in all flake.nix apps and the screenshot script)
- `-c <name>`: Use a named config from the quickshell config registry (used in hm-module)

Use `-p /etc/kh-osd-config` in VM tests — no home-manager config registry exists.

### 10.3 Quickshell IPC socket location

Quickshell puts its IPC socket at: `${XDG_RUNTIME_DIR}/quickshell/pid-${pid}/`

The `quickshell ipc --pid N` command discovers this automatically. You must run the IPC command
**as the same user** that started Quickshell (testuser), with the same `XDG_RUNTIME_DIR`.
Mismatched uid or XDG_RUNTIME_DIR = "no such process" error.

### 10.4 Sway starting before XDG_RUNTIME_DIR exists

`install -d -o testuser -m 700 /run/user/1000` before starting Sway. Sway itself may try to create
it, but there's a race. Do it explicitly first.

### 10.5 Sway config: output line required

Without `output HEADLESS-1 resolution WxH`, sway may start with no outputs, causing Quickshell's
`PanelWindow` to never create its surface. The headless output must be explicitly configured.

### 10.6 grim needs the Wayland socket explicitly

`grim` uses `WAYLAND_DISPLAY` from the environment. Since we're running as root calling
`su testuser`, we must pass `WAYLAND_DISPLAY` explicitly in the command. The `qs_env` string
pattern handles this.

### 10.7 Font rendering differences

The VM fonts are the hermetic set (DejaVu + Symbols Nerd Font). The screenshot script uses
`FONTCONFIG_FILE` pointing to a temp file. In the VM, use `fonts.packages` +
`fonts.fontconfig.defaultFonts.monospace` — this configures the system fontconfig, which
Quickshell/Qt picks up automatically. No manual `FONTCONFIG_FILE` needed.

### 10.8 `HOME` for testuser

`su testuser -c 'cmd'` may not set `HOME` correctly. Use `su - testuser -c 'cmd'` (login shell) or
explicitly pass `HOME=/home/testuser`. Without HOME, `~/.local/share/` won't be in the right place
for cliphist, MetaStore, etc.

### 10.9 Quickshell startup time

Quickshell loads QML, connects to Wayland, registers IPC handlers. This takes ~0.5–2s depending on
app. The 30-iteration / 100ms-each retry (= up to 3 seconds) in the screenshot script translates to
`timeout=10` in `wait_until_succeeds`. Increase to 30s if needed in CI.

### 10.10 `kh-cliphist` extraBins path

`cliphistConfig` uses `cliphistDecodeAll = toString cliphistDecodeAllScript`. This is a path to a
script in the Nix store. When the config is mounted at `/etc/kh-cliphist-config`, the `NixBins.qml`
inside it has the absolute Nix store paths baked in. These store paths must exist in the VM. They
will exist if `cliphistDecodeAllScript` (and all its dependencies) are in the VM's closure — which
they are if `cliphistConfig` is in `environment.etc`.

### 10.11 `runCommand` sandbox

In `flake.nix`, `mkAppConfig` uses `pkgs.runCommand` (sandboxed). This means the config
derivations are built in the Nix sandbox and their contents are static store paths — exactly what
you want for VM tests.

### 10.12 `machine.copy_from_vm` target

`machine.copy_from_vm("/vm/path")` copies to `os.environ.get("out", ".")`. In a normal `nix build`,
`$out` is the output directory. Files copied go into the derivation output. After building, they
appear in `./result/`.

### 10.13 Multiple screenshots in one test

Each `machine.copy_from_vm` call copies one file. For multiple screenshots:

```python
machine.copy_from_vm("/tmp/shot1.png")
machine.copy_from_vm("/tmp/shot2.png")
# → result/shot1.png, result/shot2.png
```

Or copy a directory:

```python
machine.succeed("mkdir -p /tmp/shots && mv /tmp/shot*.png /tmp/shots/")
machine.copy_from_vm("/tmp/shots")
# → result/shots/shot1.png, result/shots/shot2.png
```

---

## 11. Things to investigate further

### 11.1 Quickshell's exact IPC socket path

Verify empirically that `quickshell ipc --pid N` works across user boundary (root invoking for
testuser's process). Alternatively: confirm the socket path format, then call the socket directly:

```bash
quickshell ipc --socket /run/user/1000/quickshell/pid-1234/ipc.sock call target fn
```

(Actual socket path may differ — check quickshell source or run
`ls /run/user/1000/quickshell/` after starting qs.)

### 11.2 Does `WlrLayershell` require a specific protocol extension in Sway?

Run `quickshell -p /etc/kh-osd-config` under headless Sway in the VM and check `/tmp/qs.log` for
protocol errors. If wlr-layer-shell fails, the OSD window won't appear and grim will capture a
blank desktop.

### 11.3 The `su testuser -c 'cmd &' echo $!` PID race

The `echo $!` after the `su` captures sway's PID from the *outer* shell's perspective — it's the
`su` process PID, not the actual app. When su exits, its child gets reparented to PID 1. This is
generally fine — you don't need to kill sway explicitly. But if you need to know the actual
Quickshell PID (for IPC), use a wrapper that writes the PID from inside the su (see §3.3).

### 11.4 Does `machine.sleep()` actually exist?

It's in the nixpkgs Python test driver as of recent nixos-unstable. Confirm with:

```python
# In the interactive driver:
help(machine.sleep)
```

If absent, use `import time; time.sleep(0.5)` — the test script is plain Python.

### 11.5 QEMU display for interactive use

By default, nixosTest VMs use `-display none`. For interactive development, you can override:

```nix
virtualisation.qemu.options = [ "-display" "gtk" ];
```

But this is a headless Wayland setup — the QEMU framebuffer is black. The Wayland session output
only exists inside the Wayland socket, not on the virtual VGA. `machine.screenshot("name")` will
give you a black image. Use grim + copy_from_vm instead.

### 11.6 Memory requirements under load

Quickshell + Sway + Qt + grim: 1536MB should be enough but hasn't been empirically verified. If the
VM OOM-kills processes during the test, increase `virtualisation.memorySize`.

### 11.7 `programs.sway.enable` vs bare `sway` package

`programs.sway.enable = true` does a lot more than adding the binary — it sets up pam rules,
polkit, xwayland, etc. For minimal tests, just `environment.systemPackages = [ pkgs.sway ]` is
simpler and avoids pulling in unnecessary services. But if you need proper session integration
(D-Bus, polkit for Pipewire), enabling the module may be needed.

### 11.8 D-Bus session bus for Quickshell

Some Quickshell features (MPRIS, SystemTray, Notifications) need a D-Bus session bus. For OSD and
view tests this doesn't matter. For launcher/cliphist: check if Quickshell crashes on startup
without D-Bus, or just silently skips those features.

To add a session bus in tests:

```nix
services.dbus.enable = true;
```

And set `DBUS_SESSION_BUS_ADDRESS` in the Quickshell environment.

### 11.9 Nix sandbox and the `self` reference in flake outputs

`checks.${system}.my-test = pkgs.testers.nixosTest { ... }` in `flake.nix` — this call happens at
evaluation time. The test's NixOS module config (including
`environment.etc."kh-osd-config".source = osdConfig`) is evaluated then. The `osdConfig`
derivation is already in the `let` block. This should work with no surprises, but verify that
`nix eval .#checks.x86_64-linux.kh-osd-screenshot` doesn't error before building.

### 11.10 `kh-bar` and VKMS

The kernel's VKMS (Virtual Kernel Modesetting) driver allows Hyprland to start without real GPU
hardware. Hyprland under VKMS is known to work in some configurations. This would unblock `kh-bar`
testing. Relevant NixOS options to investigate:

```nix
boot.kernelModules = [ "vkms" ];
hardware.opengl.enable = true; # may be needed by Hyprland
```

Then start Hyprland instead of Sway: `WLR_BACKENDS=headless hyprland` or `HYPRLAND_NO_RT=1 hyprland`.

---

## 12. Rough implementation sequence

1. Add `tests/` directory — **`git add` immediately** before any `nix build` invocation.
2. Write `tests/kh-osd.nix` first — simplest: IPC-driven, no state seeding, no Hyprland.
3. Add `checks.${system}.kh-osd-screenshot` to `flake.nix` referencing it.
4. Build: `nix build .#checks.x86_64-linux.kh-osd-screenshot` — debug until screenshot appears
   in `result/`.
5. Iterate: build the `driverInteractive` target and poke at it manually.
6. Port `kh-view` (state seeding via files), then `kh-cliphist` (cliphist DB seeding), then
   `kh-launcher`.
7. Add GHA workflow referencing `checks.*`.
8. `kh-bar` waits for VKMS investigation.
