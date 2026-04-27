# Features

Per-component feature lists — what's done (✅), what's planned (⬜), and
what's deferred. Organised by component so one file shows one area's full
state.

**UX principles:**

- Overlays are reachable from multiple entry points: bar widgets open their
  corresponding overlay on click, and all overlays are searchable and
  openable from the launcher.
- Overlays are modal, following vim bindings as closely as the UI context allows.
- Everything controllable via keyboard must also be controllable via IPC, so
  overlays can be driven programmatically (automation, agentic development).
- Keyboard-first. Mouse support is a future concern.

---

## Components

- [Configuration / Portability](docs/features/configuration.md)
- [Clipboard History](docs/features/cliphist.md) — `kh-cliphist`
- [Launcher](docs/features/launcher.md) — `kh-launcher`
- [Bar](docs/features/bar.md) — `kh-bar`
- [Notification Center](docs/features/notification-center.md)
- [Audio Mixer](docs/features/audio-mixer.md)
- [Patchbay](docs/features/patchbay.md)
- [OSD](docs/features/osd.md) — `kh-osd`
- [File Viewer](docs/features/view.md) — `kh-view`
- [Process Manager](docs/features/process-manager.md)
- [Window Inspector](docs/features/window-inspector.md)
- [Diff Viewer](docs/features/diff-viewer.md)
- [Screenshot](docs/features/screenshot.md)
- [Dev Tooling](docs/features/dev-tooling.md)

## Backlog buckets

Cross-component piles of deferred ideas — kept separate so they don't
clutter the active component files.

- [Possibly](docs/features/possibly.md) — clear value, no committed timeline
- [Probably Not](docs/features/probably-not.md) — considered and deprioritised, kept here to avoid re-litigating
- [Future Laptop Support](docs/features/future-laptop.md) — deferred until the system runs on a laptop
