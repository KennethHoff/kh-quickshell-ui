# Future Laptop Support

Features deferred until the system runs on a laptop.

## Plugins

### Bar

- **Battery module** — percentage + charging via `/sys/class/power_supply`
- **WiFi module** — connection name + signal strength; nearby networks dropdown
- **WiFi tile** — toggle WiFi; pairs with the bar module
- **Power profiles** — cycle `power-profiles-daemon` profiles
- **Bluetooth manager** — paired devices, toggle, connect/disconnect

### OSD

- **OsdBrightness** — brightness on step changes; IPC-driven
- **OsdBattery** — plug/unplug + threshold crossings (20/10/5 %); via UPower
