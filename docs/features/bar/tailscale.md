# Tailscale

- [1] ✅ Status polling — `tailscale status --json` every 10 s; exposes `connected`/`selfIp`/`peers`
- [2] ✅ Tile appearance — `BarControlTile` pill with IP sublabel; highlights when connected
- [3] ✅ Toggle on click — runs `tailscale up`/`down` and re-polls; requires user as operator (see [Notes](#notes))
- [4] ✅ IPC — `bar.tailscale` exposes `isConnected`/`getSelfIp`/`toggle`
- [5] ✅ Pending state — pulses opacity, `…` sublabel
- [6] ⬜ Toggle error feedback — surface non-zero exit visibly; common cause is operator not configured
- [7] ✅ Peer ping — click peer row to run `tailscale ping -c 1 <ip>`; latency shown inline in `base0E` for 5 s
- [8] ✅ Exit node selection — exit-capable peers in separate section; click to set/clear; active highlighted in `base0A`
- [9] ⬜ Advertise exit node toggle
- [10] ⬜ Shields-up toggle
- [11] ✅ Hover highlight on peer/exit-node rows

## Notes

**Operator setup** *([3])* — toggling Tailscale via `tailscale up`/`down`
requires the user to be set as operator once:

```
sudo tailscale up --operator=$USER
```

`tailscale set --operator` is [broken
upstream](https://github.com/tailscale/tailscale/issues/18294); the
NixOS module's `extraUpFlags` only applies when `authKeyFile` is set.
