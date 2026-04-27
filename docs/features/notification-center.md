# Notification Center

Standalone Quickshell daemon replacing `mako`/`dunst`. Shows incoming toasts
and a persistent history panel (toggle via SUPER or bar button). Groups
notifications by app, supports action buttons, and integrates a Do Not
Disturb toggle.

## Toasts

- [1] ⬜ Incoming toast — popup with icon/summary/body; auto-dismiss
- [2] ⬜ Urgency — `critical` ignores DND, persists; `low` skips toast

## History Panel

- [1] ⬜ Persistent panel — toggle via SUPER/bar; grouped by app
- [2] ⬜ Action buttons — execute via DBus reply
- [3] ⬜ DND toggle — suppresses toasts; history still accumulates
