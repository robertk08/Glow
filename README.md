# Glow

An iOS app that controls DMX stage lights over Wi-Fi, and the ESP32-S3 firmware
that puts the signal on the wire.

The app is the console: it holds the patch, the fixture profiles and the
512-channel universe, and decides what every channel is worth. The controller is
a dumb output that clocks whatever it is sent onto the DMX line. Fixture support
is therefore a JSON file in the app, never a reflash.

```
Glow/        the iOS app
  Models/    value types - universe, profiles, colour maths
  Services/  console, socket, discovery, setup, library
  Views/     one file per screen
  Profiles/  bundled fixture profiles
Arduino/     the ESP32-S3 sketch
```

Selecting lights is how you control them. Tap one or several in Lights and the
programmer drives the whole selection at once, the way a grandMA programmer
does. On iPhone it opens as a sheet low enough to keep tapping the list behind
it, on iPad it sits in a column beside the list. The selection stays until you
clear it. A group is a saved selection, not a container, so a light can be
reached on its own or through any group it belongs to. The master fader and the
momentary blackout sit in the tab bar accessory and stay reachable everywhere.

A scene stores where every patched light is and puts it back on one tap. It
records lights rather than addresses, so re-addressing one later does not point
its scenes at whatever now sits on those channels.

A show is a store of its own on disk, holding one patch, its groups, the
fixtures built here and its scenes. Switching show swaps the store underneath
the app, so a house rig and a touring rig never see each other. The controller
you send to belongs to the device, not the show, because it is about where you
are standing. An existing patch becomes the first show on upgrade.

## Setting up a controller

Nothing is entered on the Arduino, including Wi-Fi. A controller with no stored
credentials raises its own open network called **Glow Setup**. Join it from iOS
Wi-Fi settings, then in Glow: Settings › Controller › Change Wi-Fi Network. The
app lists what the controller can see, takes the password and hands it over. A
network that signs you in by name takes a username too.

The controller answers *before* it joins, because once it joins it is no longer
on its own network. The app confirms by finding it again afterwards.

Credentials are written only after the join succeeds, so a wrong password cannot
displace a working network.

**Getting back to setup:** the controller raises **Glow Setup** by itself after
a minute of not finding its stored network, and keeps it up until it joins, so
one carried somewhere new is reachable without being touched. To ask for it
while the stored network is fine, power the controller off and on three times,
leaving it on for less than five seconds each time, which raises the setup
network for five minutes. Neither erases anything. Serial `forget`, or the app's
forget button, is what erases. Reflashing does not, because credentials live in
NVS.

Only 2.4 GHz: the ESP32-S3 has no 5 GHz radio, so a 5 GHz-only network never
appears in the list.

## Hardware

Arduino Uno R4 WiFi, using only its onboard ESP32-S3. RS485 module TTL485-V2.0,
auto-direction, so there is no DE/RE pin to wire.

| From | To |
|---|---|
| POWER header `3V3` | module `VCC` |
| POWER header `GND` | module `GND` |
| ESP 2×3 header `ESP_IO42` | module `RXD` |
| module `D+/A` | XLR pin 3 |
| module `D-/B` | XLR pin 2 |
| module `GND` | XLR pin 1 |

Three things break this silently:

- **The ESP's transmit pin goes to `RXD`, not `TXD`.** The module's names are
  from its own point of view.
- **GPIO42, not GPIO43.** GPIO43 is `ESP_TXD0` and the RA4M1 holds it up
  through a level translator.
- **Module power comes from the main POWER header.** The 2×3 ESP header has no
  3V3 pin. 3.3 V, not 5 V.

DMX reverses the audio-XLR pin 2/3 convention but keeps the gender convention:
the controller end is male. If nothing decodes, swap `D+/A` and `D-/B`.

## Flashing

Bridge `GND` and `ESP_DOWNLOAD` on the 2×3 header, connect USB, flash, then
**un-bridge them** or the chip stays in the bootloader.

All four board settings are required, and none are saved with the sketch:

- Board: **ESP32S3 Dev Module**, not "Arduino UNO R4 WiFi", which targets the RA4M1
- **USB CDC On Boot: Enabled**, or `Serial` never reaches the USB port
- Flash Size: **8MB**
- Partition Scheme: **Huge APP (3MB No OTA/1MB SPIFFS)**

A correct compile reports `Maximum is 3145728 bytes`. If it says ~1.25 MB the
partition scheme did not take, and HomeKit will not fit later.

Serial console at 115200: `red | green | blue | net | setup | forget`.

## Toolchain

arduino-esp32 core 3.3.11 · ESP-IDF 5.5.5 · esp_dmx 4.1.0 · WebSockets 2.7.2 ·
ArduinoJson 7.4.3

**esp_dmx needs patching, twice.** 4.1.0 does not build against ESP-IDF ≥ 5.3,
which removed `.module` from `uart_signal_conn_t`. And its ISR only goes into
IRAM when `CONFIG_DMX_ISR_IN_IRAM` is set, which Kconfig does under ESP-IDF but
cannot under Arduino, so by default the ISR sits in flash and any flash access
that drops the cache corrupts the packet on the wire as a visible flicker. Run
`./patch_esp_dmx.sh` after installing from Library Manager. Idempotent, keeps
`.orig` backups.

The core does not set `CONFIG_GPTIMER_ISR_IRAM_SAFE`, so the timer half of the
driver stays in flash even after the patch.

**Use `DMX_NUM_1`.** Port 0 is the console UART, and `DMX_NUM_2` crashes in
`dmx_driver_install()`, because esp_dmx drops the third UART's context entry
([#228](https://github.com/someweisguy/esp_dmx/issues/228)).

Current build is 990,541 bytes, 31% of the partition. With HomeSpan 2.1.8 and
one service on top it is 46%, so the HomeKit stage fits.

## Wire protocol

WebSocket at `ws://<host>/ws`, advertised over mDNS as `_glow._tcp` on port 80,
hostname `glow.local`, TXT `v`, `id` (MAC as 12 hex digits), `name`.

**The client must not offer a WebSocket subprotocol.** The node's library echoes
one back and a strict client then rejects its own connection.

DMX travels as binary frames, because a universe update is 512 bytes raw against
about 700 base64, and at 40 Hz that difference is real on 2.4 GHz:

```
byte 0      opcode    0x01
byte 1      universe  0
bytes 2-3   start     uint16 LE, 1-based
bytes 4-5   length    uint16 LE
bytes 6..   values
```

Everything else is JSON with a `t` discriminator. Out: `hello`, `ping`,
`blackout`. In: `status` (`fw`, `id`, `name`, `uptime` in seconds),
`pong`, `error`. Types are strict, an integer is not a float and a boolean is not
`1`. `status` is only sent in reply to `hello`, so say hello first.

Setup is plain HTTP on the same port: `GET /api/info`, `GET /api/scan`,
`POST /api/provision`, `POST /api/forget`. `/api/scan` is served only on the
setup network, because scanning takes the radio off the air and must not be able
to disturb a running show. It starts the scan and answers straight away, so the
app polls until the list arrives.

**On disconnect the controller holds its last look.** A light going dark because
Wi-Fi hiccuped is worse than a light staying put, and drops are routine.

## Next

HomeKit, via HomeSpan on the controller, exposing on/off and brightness only.
`Fixture` in the firmware is the seam it attaches to. Note that HomeSpan writes
NVS when pairing, which disables the flash cache and can corrupt DMX output, so
those writes need the same `DmxBus::pause()`/`resume()` bracket the credential
writes use.

Then remote access over a Cloudflare Worker, which is a second socket rather
than a second protocol.
