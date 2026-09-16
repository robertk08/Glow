# Moving Head DMX + HomeKit Project

## Goal
Control a DMX moving-head light from the ESP32-S3 built into an Arduino Uno R4
WiFi, standalone — not using the board's main RA4M1 chip. Two control surfaces:
a custom iOS app (local + internet) and Apple HomeKit (local only, for now).

## Build order
1. ~~Local control + DMX~~ — **done, working.**
2. **HomeKit integration** — next.
3. **Cloudflare remote access + iOS app** — last.

## Hardware
- **Board:** Arduino Uno R4 WiFi. Only the onboard ESP32-S3 is used.
- **Light:** mini LED moving head, no-name, 3-pin DMX, 14-channel mode,
  address 001 (display shows `d001`).
- **Transceiver:** RS485 module marked TTL485-V2.0 (V700). 4-pin TTL side
  (`VCC`/`TXD`/`RXD`/`GND`), 3-pin screw terminal (`GND`/`D-/B`/`D+/A`),
  auto-direction — no `DE`/`RE` pins to wire.

## Wiring

| From | To |
|---|---|
| POWER header `3V3` | module `VCC` |
| POWER header `GND` | module `GND` |
| ESP 2×3 header `ESP_IO42` | module **`RXD`** |
| — | module `TXD` left unconnected |
| module `D+/A` | XLR pin 3 (Data+) |
| module `D-/B` | XLR pin 2 (Data−) |
| module `GND` | XLR pin 1 (shield) |

Three things here are easy to get wrong and all three break it silently:

- **The ESP's transmit pin goes to `RXD`, not `TXD`.** The module's pin names
  are from the module's point of view: `RXD` is its `DI` input, `TXD` is its
  `RO` output.
- **GPIO42, not GPIO43.** GPIO43 is `ESP_TXD0` and is wired to the RA4M1
  through a level translator that holds it up. GPIO41/42 are free.
- **Module power comes from the main POWER header** — the 2×3 ESP header has
  no 3V3 pin. 3.3 V, not 5 V.

DMX reverses the audio-XLR pin 2/3 convention but keeps the gender convention:
the controller end is male. A/B labelling varies between manufacturers — if
nothing decodes, swap `D+/A` and `D-/B`.

## Flashing
Bridge `GND` and `ESP_DOWNLOAD` on the 2×3 header, connect USB, flash, then
**un-bridge them** or the chip stays in the bootloader.

Board settings — all four are required, and they are per-IDE-window, not saved
with the sketch:

- Board: **ESP32S3 Dev Module** (not "Arduino UNO R4 WiFi" — that targets the RA4M1)
- **USB CDC On Boot: Enabled** — or `Serial` never reaches the USB port
- Flash Size: **8MB**
- Partition Scheme: **Huge APP (3MB No OTA/1MB SPIFFS)**

A correct compile reports `Maximum is 3145728 bytes`. If it says ~1.25 MB the
partition scheme didn't take, and HomeSpan won't fit later.

## Toolchain
arduino-esp32 core 3.3.11 · ESP-IDF 5.5.5 · esp_dmx 4.1.0 · HomeSpan 2.1.8

**esp_dmx needs patching on this core.** Version 4.1.0 doesn't build against
ESP-IDF ≥ 5.3 — ESP-IDF removed `.module` from `uart_signal_conn_t`. After
installing esp_dmx from Library Manager, run `./patch_esp_dmx.sh` (idempotent,
keeps a `.orig` backup). Once patched it builds and runs fine.

**Use `DMX_NUM_1`.** Port 0 is the console UART, and `DMX_NUM_2` crashes in
`dmx_driver_install()` — esp_dmx drops the third UART's context entry
([#228](https://github.com/someweisguy/esp_dmx/issues/228)).

## Fixture channel map (14-channel mode)

| CH | Value | Function |
|----|-------|----------|
| 1–4 | 0–255 | Pan, Pan fine, Tilt, Tilt fine |
| 5  | 0–255 | XY speed |
| 6  | 0–7 / 8–134 / 135–239 / 240–255 | off / dimmer / strobe / open |
| 7–10 | 0–255 | Red / Green / Blue / White |
| 11 | 0–7 / 8–231 / 232–255 | RGBW mix / colour macro / colour jumping |
| 12 | 0–255 | Colour jumping speed |
| 13 | 0–7 / 8–63 / 64–127 / 128–191 / 192–255 | manual / auto fast / auto slow / sound 1 / sound 2 |
| 14 | 150–200 | Reset |

**Four channels decide whether the fixture responds to DMX at all.**
`Fixture::lampOn()` sets all four, and any new control path must keep them set:

- **CH6 ≥ 8** (240–255 for full open). 0–7 is a blackout.
- **CH13 must be 0–7**, or the fixture runs its own auto/sound program and
  ignores DMX. It keeps moving while doing so, which looks like it's responding.
- **CH11 must be 0–7** for CH7–CH10 to control colour.
- **CH14 must stay outside 150–200** or the head resets continuously.

If the fixture ever turns out not to match this table, edit `FIXTURE_PROFILE`
in `Config.h` — nothing else hard-codes a channel number.

## Repository layout

```
Glow.xcodeproj              the iOS app
Glow/                       app source, Assets.xcassets, Icon.icon,
                            PrivacyInfo.xcprivacy
design/icon-layers/         app icon layer sources (SVG, 1024 canvas)
design/sf-symbol/           the custom moving-head symbol artwork
firmware/dmx_console/       the ESP32-S3 sketch
PROJECT.md                  this file
```

Firmware files:

```
dmx_console.ino   setup/loop + a red/green/blue serial console
Config.h          pins, wiring, fixture profile   <- the file to edit
DmxBus.h/.cpp     the 513-byte universe + esp_dmx. Bounds-checks every write
Fixture.h/.cpp    channel map -> meaning. No transport
patch_esp_dmx.sh  the ESP-IDF 5.3+ fix for esp_dmx
```

## Brand

Accent colour, as a Color Set with Any/Dark appearances:

| Appearance | Hex |
|---|---|
| Any (light) | `#C47F08` |
| Dark | `#FFB340` |

Both sit on the same hue line (36-38 deg) as the icon's centre beam. Amber is
deliberately the brand colour rather than red or blue: the UI will constantly
display whatever colour the user has set the fixture to, and the accent has to
read as *the app* rather than as *the light's current state*.

Boots lit (centred, white, shutter open) and stays lit. Typing `red`, `green`
or `blue` at 115200 changes the colour.

`Fixture` is the seam: it's transport-agnostic, so a HomeSpan service and a
WebSocket handler can both call `Fixture::setColor()` without either knowing
DMX exists. That's what makes stages 2 and 3 additive rather than a rewrite.
`DmxBus` is the only code that touches the frame.

## Stage 2 — HomeKit
- **HomeSpan**, native Apple HAP (not Matter). Pairing and control from the
  Home app already confirmed with a test `Switch` service. Default pairing code
  for new accessories: `466-37-726`.
- Expose **on/off and brightness only**. Full moving-head control belongs to
  the custom app.
- No Apple Home hub is owned, so HomeKit works only on the same WiFi. Adding a
  hub later extends the same accessory to work remotely with zero code changes.
- **One thing to handle:** under Arduino the DMX ISR lives in flash, and
  HomeSpan writes to NVS when pairing, which disables the flash cache and can
  corrupt DMX output. Bracket those writes with `dmx_driver_disable()` /
  `dmx_driver_enable()`.

## Stage 3 — iOS app and remote access
- One app, two modes: local (same WiFi) and internet, with all moving-head
  functions in both.
- Local mode: the app talks directly to the ESP32-S3 over WiFi.
- Remote mode: **Cloudflare Workers + Durable Objects**, not Cloudflare Tunnel.
  A Tunnel needs an always-on local daemon, defeating the goal of no
  Pi/NAS/server. A Worker lets the ESP32 hold an outgoing WebSocket to it, with
  the app connecting to the same Worker — no open ports.
- The remote endpoint needs its own auth/token check: Worker subdomains are
  internet-scannable, not merely reachable from local WiFi.
- The app should handle WiFi reconnect gracefully — timeout, retry, and a
  visible connection-status indicator. ESP32 drops and reconnects are normal
  (DHCP renewals, router reboots, 2.4 GHz interference).

## References
- [someweisguy/esp_dmx](https://github.com/someweisguy/esp_dmx) — the DMX library
- [HomeSpan](https://github.com/HomeSpan/HomeSpan) — HomeKit, supports core 3.x
- [doctormord/Standalone-WIFI-ESP32-Moving-Head-Controller](https://github.com/doctormord/Standalone-WIFI-ESP32-Moving-Head-Controller) — ESP32-S3 → RS485 → moving head with a web UI; closest prior art
