# Glow

An iOS app that controls DMX stage lights over Wi-Fi, and the ESP32-S3 firmware
that puts the signal on the wire.

The app is the console: it holds the patch, the fixture profiles and the
512-channel universe, and decides what every channel is worth. The controller is
a dumb output that clocks whatever it is sent onto the DMX line. Fixture support
is therefore a JSON file in the app, never a reflash.

Selecting lights is how you control them. Tap one or several in Lights and the
programmer drives the whole selection at once, the way a grandMA programmer
does. On iPhone it takes over the tab bar accessory and raises a sheet, on iPad
it is an inspector beside the grid. The selection stays until you clear it, and
holding Clear offers Release Values. A group is a saved selection, not a
container. The master fader and blackout hold the accessory whenever nothing is
selected.

Blackout latches and pulls only the dimmers down, the same channels and the same
way the master fader does, so a head keeps its position and its colour through
one.

The patch, the groups, the fixtures built here and the scenes sit in one store
with an undo manager, so editing is undoable. Removing a light writes zeros
across its channels on the way out. A light whose fixture profile no longer
exists is removed on the next launch, unless the fixture library failed to load.

A moving head can be told to invert pan, tilt or both. The fixture profile
carries what is usual for that model and each patched light can differ.

Color is one control for two kinds of fixture. An LED fixture adds emitters
together, and a discharge head subtracts cyan, magenta and yellow flags from a
white lamp. A profile says which it is with `colorMixing`, and a fixture built
in the app can declare itself subtractive too.

A scene records lights rather than addresses, so re-addressing one later does
not point its scenes at whatever now sits on those channels.

A show is a store of its own on disk, holding one patch, its groups, the
fixtures built here and its scenes. Switching show swaps the store underneath
the app. The controller you send to belongs to the device, not the show. A show
exports and imports as one JSON file carrying the date its format was settled
and the date it was written. A file from a newer format is refused, one with no
version at all is taken as it comes.

The DMX monitor shows output after master and blackout. Switch to Source to
inspect or adjust the programmer values before those controls.

Bundled fixture channel tables come from the [Cameo F2 FC DMX table](https://www.cameolight.com/en/downloads/file/id/1419641648),
[Stairville BSW-350 manual](https://images.static-thomann.de/pics/atg/atgdata/document/manual/549467_v2_en_online.pdf),
and [Stairville HL-x180 manual](https://images.static-thomann.de/pics/atg/atgdata/document/manual/c_467326_467328_524858_524859_v2_en_online.pdf).

## Setting up a controller

Nothing is entered on the Arduino, including Wi-Fi. A controller with no stored
credentials raises its own open network called **Glow Setup**. In Glow, open
Settings › Controller › Change Wi-Fi Network and allow the Wi-Fi connection.
The app lists what the controller can see, takes the password and hands it over.
A network that signs you in by name takes a username too. The app requires the
Hotspot Configuration capability when signing for a device.

The controller keeps its setup network available until the app confirms. Glow
reconnects to the chosen network and checks the controller identity before
reporting Ready. Credentials are written only after the join succeeds, so a
wrong password cannot displace a working network.

**Getting back to setup:** the controller raises **Glow Setup** by itself after
a minute of not finding its stored network, and keeps it up until it joins. To
ask for it while the stored network is fine, use Change Wi-Fi Network in Glow,
or power the controller off and on three times leaving it on for less than five
seconds each time, which raises the setup network for five minutes. Neither
erases anything. Serial `forget`, or the app's forget button, is what erases.
Reflashing does not, because credentials live in NVS.

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
partition scheme did not take.

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

**Use `DMX_NUM_1`.** Port 0 is the console UART, and `DMX_NUM_2` crashes in
`dmx_driver_install()`, because esp_dmx drops the third UART's context entry
([#228](https://github.com/someweisguy/esp_dmx/issues/228)).

## Wire protocol

WebSocket at `ws://<host>/ws`, advertised over mDNS as `_glow._tcp` on port 80,
hostname `glow.local`, TXT `v`, `id` (MAC as 12 hex digits), `name`.

**The client must not offer a WebSocket subprotocol.** The node's library echoes
one back and a strict client then rejects its own connection.

DMX travels as binary frames:

```
byte 0      opcode    0x01 output, 0x02 source
byte 1      universe  0
bytes 2-3   start     uint16 LE, 1-based
bytes 4-5   length    uint16 LE
bytes 6..   values
```

**The opcode says what the frame is for.** `0x01` is the output, what the lamps
should be doing once master and blackout are in it, and the controller clocks it
onto the wire and tells nobody. `0x02` is the source, what the programmer holds
before master touches it, and the controller stores it and passes it to every
other client without clocking it.

Everything else is JSON with a `t` discriminator. Out: `hello`, `ping`,
`blackout`, `master`. In: `status` (`fw`, `id`, `name`, `blackout`, `uptime` in
seconds, `src`), `pong`, `error`, plus `blackout` and `master` relayed from
another client. Types are strict, an integer is not a float and a boolean is not
`1`. `status` is only sent in reply to `hello`, so say hello first.

Setup is plain HTTP on the same port: `GET /api/info`, `GET /api/scan`,
`POST /api/provision`, `POST /api/setup`, `POST /api/forget`. `/api/scan` is
served only on the setup network, and it starts the scan and answers straight
away, so the app polls until the list arrives.

Master and blackout are relayed the same way a source frame is, so two devices
on one node stay in step and both send the same output. The app sends a full
universe on connect and deltas after, never re-asserting the whole universe on
a timer.

**Who has the look on connect is settled by `src`.** The controller keeps the
last source it was given, across client churn and disconnects. A joining client
reads `src` in the status: true means the controller has a look and the client
takes it, false means there is none and the client asserts its own. On
disconnect the controller holds its last look.
