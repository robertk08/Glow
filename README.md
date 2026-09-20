# Glow

An iOS app that controls DMX stage lights over Wi-Fi, and the ESP32-S3 firmware
that puts the signal on the wire.

The controller is the desk. It holds the shows, and every device is a terminal
on it. Connect and you are handed the whole show. Disconnect and there is
nothing to see, because nothing is kept on the device. Two phones and an iPad on
one controller see the same patch, the same scenes and the same look, and a
scene saved on one appears on the others.

The app still decides what every channel is worth. It holds the fixture
definitions and the 512-channel universe and works out the values, and the
controller clocks them onto the DMX line and files the show away. It never reads
a show it is given, so fixture support stays a JSON file in the app, never a
reflash.

A device changes itself first and tells the controller after, the way an X32
remote does, so nothing waits on a round trip. The controller passes the change
to every other device and never back to the sender. Last writer wins, per
object, with no locking and nothing to resolve.

Selecting lights is how you control them. Tap one or several in Lights and the
programmer drives the whole selection at once, the way a grandMA programmer
does. On iPhone it takes over the tab bar accessory and raises a sheet, on iPad
it is an inspector beside the grid. The selection stays until you clear it, and
holding Clear resets those lights to their defaults. A group is a saved
selection, not a container, so a light can be in several. The master fader and
blackout hold the accessory whenever nothing is selected.

The programmer is the fixture's own feature groups along the top, the only
thing that stays put, and under them the group you are on in named sections
that scroll with everything else. Everything is a system control unless there
is nothing that fits: position is a pad reading real degrees with a fine mode
that moves a sixth as far for the same gesture, and beam and strobe draw the
light itself against a dark stage, the cone widening with zoom and softening
with focus. Wheels are a picker with their slots under it, coloured or drawn as the
shape they throw and turning when the wheel turns, and a shutter is the same
picker, so every band it carries is reachable and a rate runs the width of
the band it belongs to. Anything the definition carries but the group
does not show is under All Channels, on its raw value. Selecting lights of
different kinds leaves the groups they can be driven by together.

Blackout latches and pulls only the dimmers down, the same channels and the same
way the master fader does, so a head keeps its position and its colour through
one.

The patch, the groups, the fixtures built here and the scenes sit in one store
in memory with an undo manager, so editing is undoable. Removing a light writes zeros
across its channels on the way out. A light whose fixture definition is gone
says so on its tile and opens straight into a picker to point it at another
one, keeping its name, address and group.

A moving head can be told to invert pan, tilt or both. The fixture definition
carries what is usual for that model and each patched light can differ.

A fixture type is one file, whether Glow ships it or you build it here, and the
app reads both through the same decoder. A channel names the attribute it
drives rather than an index, so the same control reaches pan on any head and
the dimmer on any lamp. A channel can claim a second address as its fine half,
carry a default, and split into named functions with named sets inside them,
which is how a gobo wheel offers its gobos and a colour wheel its slots. A function can say what it stands for, the
dimmer band, fully open, blacked out, or handing colour back to the mixer, and
what it means in the world, so a strobe reads in hertz and a zoom in degrees.
A channel can also name the channel and range it depends on, for a fixture
whose colour channels go dead while a built-in pattern runs.

Editing a fixture Glow ships keeps the original and saves yours beside it, and
any light already patched to it moves over. Everything a bundled definition
can say, the builder can write: 16-bit pairs and their defaults, named
functions, the slots inside them and their swatches, real units, and the
channel a channel depends on. A test fails if a bundled definition ever uses a
field the builder cannot set.

Every channel has a default, and defaults are not settings. A light patched
and brought up reads plain white, centred, no gobo and no strobe, because that
is where its channels sit, and none of it counts as chosen. Raising the dimmer
marks the dimmer and nothing else, so colour and position stay available to
whatever you do next, and resetting puts every channel back to its default.

Color is one control for two kinds of fixture. An LED fixture adds emitters
together, and a discharge head subtracts cyan, magenta and yellow flags from a
white lamp. A type says which it is with `mixing`, and a fixture built in the
app can declare itself subtractive too.

A scene records lights rather than addresses, so re-addressing one later does
not point its scenes at whatever now sits on those channels.

A show is a folder on the controller, holding one patch, its groups, the
fixtures built here and its scenes, one file per object. Switching show swaps
the store underneath the app without moving you off the screen you are on, and
switches it on every other device too. A show stores no DMX values, so every
light comes back on its defaults. The controller you send to belongs to the
device, not the show. The show you are in exports and imports as one JSON file
carrying the date its format was settled and the date it was written. A file
from a newer format is refused.

**The controller is the only copy of your shows.** A dead board or an erased
filesystem loses them, and there is no local cache softening that. Export is the
backup.

With no controller reachable, Glow shows a waiting screen with a way into
controller setup and a way into a demo. The demo runs the whole app on a show
built into the app, changes go nowhere, and quitting throws it away.

The DMX monitor shows output after master and blackout. Switch to Source to
inspect or adjust the programmer values before those controls.

Glow ships the four fixtures here, and their channel tables come from the [Cameo F2 FC DMX table](https://www.cameolight.com/en/downloads/file/id/1419641648),
[Stairville BSW-350 manual](https://images.static-thomann.de/pics/atg/atgdata/document/manual/549467_v2_en_online.pdf),
[Stairville HL-x180 manual](https://images.static-thomann.de/pics/atg/atgdata/document/manual/c_467326_467328_524858_524859_v2_en_online.pdf),
and, for the unbranded head, the [Monoprice 612870 manual](https://downloads.monoprice.com/files/manuals/612870_Manual_170822.pdf),
which is the same 7 by 10 W RGBW platform channel for channel.

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
- Partition Scheme: **Custom**, which takes `partitions.csv` from the sketch folder

The stock schemes spend only half the 8 MB and leave under a megabyte for shows.
`partitions.csv` gives the firmware 2 MB, which is roughly twice what it uses,
and hands the remaining **6.15 MB to shows**. Confirm it took by checking that
`partitions.csv` appears in the build folder, because the custom scheme makes
the compiler report the whole flash as the maximum rather than the app
partition. If the binary ever passes 2 MB, `app0` is the number to raise.

Shows live in that partition, mounted as LittleFS and formatted on first boot.
Coming from an older layout moves every partition, so the first flash with this
table starts you with no shows.

Serial console at 115200: `net | setup | forget`. `net` also reports how much of
the show filesystem is used.

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

`0x03` is a document, which is how an edit reaches the controller and the other
devices in one hop. Opening a TCP connection per object was what made saving a
scene feel slow, and it made every other device fetch the object back over HTTP
before it could show it.

```
byte 0      opcode    0x03 document
byte 1      0 put, 1 delete
byte 2      show name length
byte 3      folder name length
byte 4      object id length
bytes 5-6   body length, uint16 LE
bytes 7..   show, folder, id, body
```

The controller stores the body, relays the frame untouched to every other
client, and answers the sender with `{"t":"wrote"}`. A client folds an object
into what it believes the controller holds only once that answer arrives, so a
write that never lands is simply sent again with the next edit. Anything larger
than the socket carries comfortably still goes over HTTP.

**The opcode says what the frame is for.** `0x01` is the output, what the lamps
should be doing once master and blackout are in it, and the controller clocks it
onto the wire and tells nobody. `0x02` is the source, what the programmer holds
before master touches it, and the controller stores it and passes it to every
other client without clocking it.

Everything else is JSON with a `t` discriminator. Out: `hello`, `ping`,
`blackout`, `master`. In: `status` (`fw`, `id`, `name`, `uptime` in seconds,
`src`, `client`), `pong`, `error`, plus `blackout` and `master` relayed from
another client, and the document notices below. Types are strict, an integer is
not a float and a boolean is not `1`. `status` is only sent in reply to `hello`,
so say hello first. `client` is the slot the controller gave you, and you send
it back as `X-Glow-Client` so your own writes are not relayed to you.

Setup is plain HTTP on the same port: `GET /api/info`, `GET /api/scan`,
`POST /api/provision`, `POST /api/setup`, `POST /api/forget`. `/api/scan` is
served only on the setup network, and it starts the scan and answers straight
away, so the app polls until the list arrives.

## The browser

`Web/index.html` is the same desk in a browser, one file with no build step.
The controller serves it, so opening `http://glow.local` on any phone, tablet or
laptop reaches the desk on the same origin, with no mixed content block and no
CORS. Upload it with

```
curl -X PUT --data-binary @Web/index.html http://glow.local/api/web
```

It speaks the protocol below and nothing else, so it is a client like any other:
the lights grid with its groups and gauges, the programmer with the feature
groups a fixture actually has, scenes with the live one lit, shows, the fixture
types the show carries and a DMX monitor. It adapts the way the app does, a tab
bar and a sheet on a phone, a sidebar and an inspector on a laptop.

It can do this because a show carries its fixture definitions, so the browser
resolves channels and scales the master over the right dimmers without the
app's bundle. Patching is limited to the types a show already holds.

## Shows on the wire

Shows move over plain HTTP on the same port, because a made fixture definition
runs to tens of kilobytes and the WebSocket carries only small messages.

| Method | Path | |
|---|---|---|
| GET, PUT | `/api/shows` | the list of shows and which one is active |
| GET | `/api/show/<id>` | the whole show, assembled |
| DELETE | `/api/show/<id>` | the show and everything in it |
| GET, PUT, DELETE | `/api/show/<id>/<folder>/<objid>` | one object |

A show is a folder of folders. `lights`, `groups`, `made` and `scenes` today,
and each one holds one JSON file per object named by its id. Names are letters,
digits, hyphen and underscore, up to 39 characters, and anything else is
refused.

**The controller does not know what a folder means.** It lists the folders it
finds and assembles `GET /api/show/<id>` as `{"<folder>":[…],"<folder>":[…]}`,
measuring the files to write the `Content-Length` and then splicing the bytes in
without parsing one of them. So adding cue stacks later is a folder the app
starts writing to, and the firmware does not change. `/shows.json` is the one
file the controller reads, and it only ever hands it back.

**One file per object, not one file per show.** A whole-show write would mean
your rename wiping my new scene. Per object, both survive under the same last
writer wins rule, and one edit sends one small file rather than the show.

After a write lands, the controller sends `{"t":"doc","show","folder","id","op"}`
to every client but the sender, or `{"t":"shows"}` when the list changed. A
client fetches just that object and applies it, so nothing reloads the show to
learn one name changed.

A scene is a base64 blob of raw channel bytes per light, not an array of
numbers, which is where a show with many scenes would otherwise spend its space.
It still records lights rather than addresses, so re-addressing later does not
point a scene at whatever now sits on those channels.

An id is sixteen hex characters, not a UUID. A scene names every light it holds,
so the id is most of what a scene weighs, and the odds of two devices minting
the same one are still far past never.

**Order is a fraction, not a position.** Dragging a light to a new place gives
it a value between its new neighbours and leaves every other light alone, so one
drag is one small write rather than one per light in the list. Each write pauses
DMX, which is the real reason this matters. If a gap ever gets too small to
divide, that list renumbers itself once and carries on.

Every field is read with a fallback rather than a requirement, so a folder or a
field that is not there yet reads as empty instead of failing the whole show.
That is what makes adding to the format safe.

A show exports as one file carrying `format`, `version`, the date it was written
and the show itself. Glow reads a file only when both the format and the version
are the ones it writes today. There is no migration and no reader for anything
older.

**Writing to flash pauses DMX**, because a flash write drops the cache and
corrupts the packet on the wire. `Flash::guarded` takes the driver down for the
length of one write, the same guard the Wi-Fi credentials have always used. A
frame or two is lost and fixtures hold their last value, which is why the app
only writes when you change something and never on a timer.

**The controller clocks only the slots the rig uses.** A full 512 slot packet
takes 23 ms on the wire whatever is patched, which is most of the delay you can
feel between touching a fader and the lamp moving. The controller tracks the
highest slot it has ever been sent and clocks only that far, so a rig ending at
channel 124 spends 5 ms per packet instead of 23. It also sends the moment new
values arrive rather than waiting for the next scheduled slot, capped at 100 Hz,
and falls back to a 40 Hz refresh when nothing is changing.

If a fixture ever misbehaves at that rate, `DMX_BURST_HZ` in `Config.h` is the
one number to lower.

Master and blackout are relayed the same way a source frame is, so two devices
on one node stay in step and both send the same output. The app sends a full
universe on connect and deltas after, never re-asserting the whole universe on
a timer.

**Who has the look on connect is settled by `src`.** The controller keeps the
last source it was given, across client churn and disconnects. A joining client
reads `src` in the status: true means the controller has a look and the client
takes it, false means there is none and the client asserts its own. On
disconnect the controller holds its last look.
