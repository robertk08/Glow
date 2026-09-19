# Glow

An iOS app that controls DMX stage lights over Wi-Fi, and the ESP32-S3 firmware
that puts the signal on the wire.

The app is the console: it holds the patch, the fixture profiles and the
512-channel universe, and decides what every channel is worth. The controller is
a dumb output that clocks whatever it is sent onto the DMX line. Fixture support
is therefore a JSON file in the app, never a reflash.

```
Glow/          the iOS app
  App/         the shell, the first screen and Settings
  Lights/      the rig you patched: the lights, the groups, the tiles
  Fixtures/    the kinds of light that exist, and how one is built here
    BuiltIn/   bundled fixture profiles
  Programmer/  everything that drives the selection
  Console/     the universe, what goes out of it, and the monitor
  Color/       emitters, mixing, colour temperature
  Controller/  socket, discovery, Wi-Fi setup, and their screens
  Shows/       the show list, the store behind it, the file it exports
  Scenes/      saved looks
  Controls/    controls used by more than one of the above
  Resources/   assets, icon, privacy manifest
Arduino/       the ESP32-S3 sketch
```

Selecting lights is how you control them. Tap one or several in Lights and the
programmer drives the whole selection at once, the way a grandMA programmer
does. On iPhone the programmer takes over the tab bar accessory the moment
something is selected, and tapping it raises a sheet low enough to keep tapping
the grid behind it. On iPad it is an inspector beside the grid. The selection
stays until you clear it. Tapping Clear drops the selection, and holding it
offers Release Values, which puts every selected light back where its profile
says it starts. A group is a saved selection, not a container, so a light can be
reached on its own or through any group it belongs to. The master fader and
blackout hold the accessory whenever nothing is selected. Lights and groups can
be reordered from Reorder, or by dragging on iOS 27.

Blackout latches and pulls only the dimmers down, the same channels and the same
way the master fader does. A head keeps its position and its colour through a
blackout, so bringing it back does not mean finding the look again.

Editing is undoable. The patch, the groups, the fixtures built here and the
scenes all sit in one store with an undo manager, so removing a light or a group
is one tap away from coming back. The light returns where it was and off, since
its channels were zeroed on the way out and undo does not put light back on a
stage.

A light whose fixture profile no longer exists is removed on the next launch.
Nothing can drive it and nothing can read it, so leaving it in the patch only
makes a tile that does nothing. This only runs when the fixture library loaded,
so a bad build cannot take the patch with it.

A moving head can be told to invert pan, tilt or both, because a head hung upside
down answers a move the wrong way round. The fixture profile carries what is
usual for that model and each patched light can differ, since it is about how
that one is rigged.

A light tile is a pane of glass carrying the fixture's own colour in its chip
and its level bar, and the bar fills to the intensity the light is actually at.
Removing a light writes zeros across its channels on the
way out, because a patch entry disappearing is not a reason for the lamp to stay
lit.

Color is one control for two kinds of fixture. An LED fixture adds emitters
together, and a discharge head subtracts cyan, magenta and yellow flags from a
white lamp. A profile says which it is with `colorMixing`, the same swatches and
the same colour picker drive both, and a fixture built in the app can declare
itself subtractive too.

A scene stores where every patched light is and puts it back on one tap. It
records lights rather than addresses, so re-addressing one later does not point
its scenes at whatever now sits on those channels.

A show is a store of its own on disk, holding one patch, its groups, the
fixtures built here and its scenes. Switching show swaps the store underneath
the app, so a house rig and a touring rig never see each other. The controller
you send to belongs to the device, not the show, because it is about where you
are standing. An existing patch becomes the first show on upgrade.

A show exports as one JSON file and imports as a new show, so it travels by
AirDrop, Files or anything else that carries a document. It leaves as readable
text rather than the store itself, because a store is a schema version and a
pile of journal files, and a show has to open on a device that is a build or
two behind.

The file carries the date its format was settled and the date it was written.
A file from a format newer than the app knows is refused rather than half read,
and one with no version at all is from before this and is taken as it comes.

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

The controller answers before it joins and keeps its setup network available
until the app confirms. Glow reconnects to the chosen personal Wi-Fi network
and checks the controller identity before reporting Ready.

Credentials are written only after the join succeeds, so a wrong password cannot
displace a working network.

**Getting back to setup:** the controller raises **Glow Setup** by itself after
a minute of not finding its stored network, and keeps it up until it joins, so
one carried somewhere new is reachable without being touched. To ask for it
while the stored network is fine, use Change Wi-Fi Network in Glow. Alternatively,
power the controller off and on three times,
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

## Wire protocol

WebSocket at `ws://<host>/ws`, advertised over mDNS as `_glow._tcp` on port 80,
hostname `glow.local`, TXT `v`, `id` (MAC as 12 hex digits), `name`.

**The client must not offer a WebSocket subprotocol.** The node's library echoes
one back and a strict client then rejects its own connection.

DMX travels as binary frames, because a universe update is 512 bytes raw against
about 700 base64, and at 40 Hz that difference is real on 2.4 GHz:

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

That split is what lets two devices drive one rig. Sending only the output and
relaying it meant the second device read the first device's master-scaled values
as its own truth, so master stopped meaning anything and a blackout could be
written in permanently. A source frame is the same on the way out as on the way
in, so an echo changes nothing.

Everything else is JSON with a `t` discriminator. Out: `hello`, `ping`,
`blackout`, `master`. In: `status` (`fw`, `id`, `name`, `blackout`, `uptime` in
seconds, `src`), `pong`, `error`, plus `blackout` and `master` relayed from
another client. Types are strict, an integer is not a float and a boolean is not
`1`. `status` is only sent in reply to `hello`, so say hello first.

Setup is plain HTTP on the same port: `GET /api/info`, `GET /api/scan`,
`POST /api/provision`, `POST /api/setup`, `POST /api/forget`. `/api/scan` is served only on the
setup network, because scanning takes the radio off the air and must not be able
to disturb a running show. It starts the scan and answers straight away, so the
app polls until the list arrives.

**A source frame is relayed to every other client, an output frame to nobody.**
Two devices on the same node see each other's changes, so an iPad patching and
an iPhone running scenes stay in step. Master and blackout travel the same way,
as commands the controller passes on, so both devices' faders move together.
Both devices then send the same output, which is redundant on the wire and
correct on the stage.

The app sends a full universe only on connect, because WebSocket is TCP and a
delta cannot be lost. Re-asserting the whole universe on a timer is what makes
two clients fight over it.

**Who has the look on connect is settled by `src`.** The controller keeps the
last source it was given, across client churn and disconnects. A joining client
reads `src` in the status: true means the controller has a look and the client
takes it, false means there is none and the client asserts its own. Without that
the second device would overwrite the rig with whatever it happened to have
saved.

**On disconnect the controller holds its last look.** A light going dark because
Wi-Fi hiccuped is worse than a light staying put, and drops are routine.
