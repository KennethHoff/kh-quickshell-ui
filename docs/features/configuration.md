# Configuration / Portability

Hardcoded assumptions that should be user-configurable.

- [1] ✅ Configurable terminal — `programs.kh-ui.launcher.terminal`, injected as `bin.terminal`
- [2] ✅ `kitty` removed from universal `ffi.nix` bins; lives in launcher's `extraBins`
- [3] ✅ Compositor-agnostic autostart — systemd-user services bound to `graphical-session.target`
