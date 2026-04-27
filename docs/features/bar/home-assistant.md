# Home Assistant

Surface Home Assistant entity state in the bar and dispatch service calls
from click/IPC. One generic plugin reads any entity; users compose widgets
declaratively per bar instance.

- [1] ⬜ Connection — HA base URL + long-lived access token via
  `programs.kh-ui.bar.environment`/`environmentFiles` (sops-friendly); plugin
  reads `HA_URL`/`HA_TOKEN` via `Quickshell.env()` (see [Notes](#notes))
- [2] ⬜ Entity subscription — websocket `/api/websocket` with
  `subscribe_entities`; auto-reconnect on drop
- [3] ⬜ REST fallback — poll `/api/states/<entity_id>` when websocket
  unavailable
- [4] ⬜ Generic entity widget — `BarHaEntity { entityId; format }`; exposes
  `state`/`attributes`; renders via sibling `BarText`/`BarIcon`
- [5] ⬜ Service calls — `callService(domain, service, data)` posts
  `/api/services/<domain>/<service>`
- [6] ⬜ IPC — `bar.homeassistant` exposes `getState(entityId)`,
  `callService(...)`, and per-widget `<entityId>` targets

## Examples

- [1] ⬜ Phone battery — `sensor.<phone>_battery_level`; warn/error colours
  via thresholds (e.g. <20% warn, <10% error)
- [2] ⬜ Phone notifications — count from
  `sensor.<phone>_active_notification_count`; bell icon hidden when zero
- [3] ⬜ Door/window — iconic state for `binary_sensor.front_door`
- [4] ⬜ Climate — current temperature and setpoint from
  `climate.<room>`; click cycles preset modes
- [5] ⬜ Energy — live grid/solar power from a Riemann-sum sensor
- [6] ⬜ Presence — `person.<name>` chip with home/away colour

## Notes

**Authentication** *([1])* — generate a long-lived access token under
Profile → Security in the Home Assistant UI, then pass via a sops-managed
env file:

```nix
programs.kh-ui.bar.environmentFiles = [ config.sops.secrets.ha-token.path ];
```
