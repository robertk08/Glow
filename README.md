# Glow

An iOS 26 app (SwiftUI, SwiftData) that controls DMX stage lights over Wi-Fi,
and the ESP32-S3 firmware in `Arduino/` that puts the signal on the wire.
Bundled fixture definitions are `Glow/Fixtures/BuiltIn/*.json`, the demo show is
`Glow/Resources/Demo.json`.

## Build and test

```bash
xcodebuild test -quiet -scheme Glow -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -collect-test-diagnostics never
```

`ControllerTests` is skipped unless `TEST_RUNNER_GLOW_CONTROLLER` holds an
address. Against a real controller on USB and the LAN:

```bash
GlowTests/controller-tests.sh glow.local
```

The script reads the controller's password key over serial (`key`) and passes
it as `TEST_RUNNER_GLOW_KEY`, so it works whatever password is set. It runs two
app instances as two devices, creates a show named **Hardware Test**, removes
it, and leaves the controller on the show and password it found. A run stopped
halfway can leave a test password behind, which serial `password` removes.
Only one process can hold the serial port, so close any serial monitor first.

Firmware: install the libraries under Toolchain, run
`Arduino/patch_esp_dmx.sh`, then build and upload with
`arduino-cli` (bundled in the Arduino IDE at
`/Applications/Arduino IDE.app/Contents/Resources/app/lib/backend/resources/`)
using FQBN `esp32:esp32:esp32s3:CDCOnBoot=cdc,FlashSize=8M,PartitionScheme=custom`
and the port from `ls /dev/cu.usbmodem*`.

## Architecture

The controller is the desk. It stores every show, and devices are terminals
with nothing on disk. On connect a device loads the whole show into an
in-memory SwiftData store with an undo manager. Disconnected, it shows a waiting
screen with controller setup and a demo that runs on `Demo.json` and sends
nothing. Any number of devices share one controller and see the same show.

The app computes every channel value from the fixture definitions and the
512-channel universe. The controller clocks frames onto the wire, stores show
objects without parsing them, and relays. Fixture support is a JSON file in the
app, never a firmware change.

Sync works like an X32 and its remotes. A device applies a change locally at
once and tells the controller after. The controller relays it to every other
device, never back to the sender. Last writer wins per object, with no locking,
revisions or conflict handling. Do not round-trip a change through the
controller before showing it.

A controller silent for 5 seconds (`NodeLink.silenceLimit`) counts as lost, and
the show gives way to the waiting screen within about seven seconds. Edits made
after the link is lost never reach the controller, and on reconnect the show
reloads exactly as the controller holds it. There is no queue or replay of
edits.

**The controller is the only copy of the shows.** Export is the backup.

## App behaviour

**Lights and the programmer.** Selecting lights is how they are controlled: the
programmer drives the whole selection, as a tab bar accessory plus sheet on
iPhone and an inspector beside the grid on iPad. The selection stays until
cleared, and holding Clear resets those lights to their defaults. With nothing
selected, the accessory holds the master fader and blackout. A group is a saved
selection, not a container, so a light can be in several. The programmer shows
the fixture's feature groups as a fixed header over scrolling sections, and a
selection of mixed types shows only the groups they share. Controls are system
controls where one fits. Position is a pad in real degrees with a fine mode at
a sixth of the travel. Beam and strobe draw the light itself. Wheels and
shutters are a picker over their slots. Channels no group shows are under All
Channels as raw values.

**Defaults are not settings.** A freshly patched light reads plain white,
centred, no gobo, no strobe, and none of that counts as chosen. Raising the
dimmer marks only the dimmer. Reset returns every channel to its default.

**Master and blackout** scale only dimmer channels, so position and colour hold
through a blackout, which latches. The DMX monitor shows output after master and
blackout, and its Source view shows programmer values before them.

**Patch.** Removing a light writes zeros across its channels. A light whose
definition is gone says so on its tile and opens a picker to re-point it,
keeping its name, address and group. Pan and tilt inversion defaults from the
definition and can differ per light.

**Fixture definitions.** A fixture type is one JSON file, bundled or built in the
app, read by one decoder. A channel names the attribute it drives rather than
an index. A channel can claim a second address as its fine half, carry a
default, split into named functions with named slots (gobos, colour wheel
slots, with swatches), give a function a role (dimmer band, open, blackout,
hand colour back to the mixer) and real units (Hz, degrees), and depend on
another channel's range. `mixing` says whether colour is additive (LED
emitters) or subtractive (CMY flags on a white lamp). Editing a bundled fixture
saves a copy under a new name, since names are unique, and moves patched lights
to it. The builder must be able to write every field a bundled definition uses,
and a test enforces it.

Bundled channel tables come from the
[Cameo F2 FC DMX table](https://www.cameolight.com/en/downloads/file/id/1419641648),
[Stairville BSW-350 manual](https://images.static-thomann.de/pics/atg/atgdata/document/manual/549467_v2_en_online.pdf),
[Stairville HL-x180 manual](https://images.static-thomann.de/pics/atg/atgdata/document/manual/c_467326_467328_524858_524859_v2_en_online.pdf)
and, for the unbranded 7 by 10 W RGBW head, the
[Monoprice 612870 manual](https://downloads.monoprice.com/files/manuals/612870_Manual_170822.pdf).

**Scenes** (the `Look` model) record lights, not addresses, so re-addressing a
light never points a scene at whatever now sits on its channels. A scene works
like a desk executor: on (its lights take the stored values), off (they return
to what they were doing), flash (on while held), and stepping cues. `tap`
chooses what a tile tap does (next cue, on and off, flash, open) and `buttons`
which of Next, Back, On and Off, Flash and Update sit on the tile, in order. A
tile with buttons is double width and every tile has one height, so the grid
packs without holes. A tap only ever runs the scene's own action. The corner
button opens the scene and a long press opens its menu, except on a flash tile,
where holding the tile flashes and the corner button's long press opens the
menu. A new scene asks for its name first and gets its own colour. Its second
cue sets the tap to Next and the buttons to Back and On and Off. Scenes can be
on together and the one turned on last wins a shared light. All Off in the
toolbar turns every scene off and is disabled while none is on.

**Cues** track. A cue holds only the lights and aspects stored into it,
everything else keeps what earlier cues set, and going back undoes what later
cues changed. The first Next starts cue 1 and after the last cue it wraps. A cue
has a label, a fade, a delay, and an optional follow that runs the next cue once
it has faded in. A scene opens as one page: cue list with one transport (Back,
Next Cue, Off), then the tile settings, then name, icon and colour folded away.
Tap a cue to jump to it, swipe to update or delete, hold to rename or set
timing. On iPad the scene sits in the right sidebar and the arrow keys or a
presentation clicker step its cues. On iPhone it is a sheet, and the bar above
the tabs shows the scene on stage like the Music mini player.

**Storing.** Store All under the plus button makes a one-cue scene of every
light. Empty Scene, or Add Cues on a scene, switches to Lights and pins the
builder bar with the scene's cues, Update and Store Cue. Every store takes the
selected lights, or all lights when none are selected. The hint under the
scene's name says which and opens the options: lights, aspects (intensity,
colour, position, gobo, beam, control), name and fade. Store inserts after the
cue on stage, or at the end, and puts the stage on the new cue without a light
moving. Update stores into the cue on stage. Storing into a cue replaces only
what was chosen. The selection stays. Deleting the cue on stage moves the stage
to the cue before it, or turns the scene off if it was the last. Done returns to
the page the builder started from, and Cancel on a scene without cues removes
it.

**Fades** run on the device that started them and reach others as ordinary
frames. Intensity, colour mixing, position, zoom, focus, iris and frost glide, a
16-bit channel glides as one value, and a dimmer sharing its channel with a
strobe fades only inside its dimming band. Everything else snaps at the start.
Touching a channel mid-fade releases it from the fade.

**Shows.** A show holds a patch, its groups, fixtures built in the app, and
scenes with their cues. It stores no DMX values, so lights come back on their
defaults. Switching show swaps the store without leaving the current screen and
switches every device. The controller address belongs to the device, not the
show. Export is one JSON file (`ShowFile`) with `format` `glow.show`, `version`
(the date the format was settled, `ShowFile.current`) and `exportedAt`. Import
reads only an exact format and version match. There is no migration.

## Password

One optional password guards the whole controller. Once set in Settings ›
Controller, a device without it gets a password field and nothing else: no
frames, shows, commands or HTTP. HomeKit keeps its own pairing code.

The app derives a key with PBKDF2-SHA256 (100,000 rounds, salted with the
controller's `id`) and keeps it in the Keychain per controller, so each device
asks once. Neither password nor key crosses the network to unlock. The
controller keeps only the key, in NVS. Changing or removing it needs the current
one, and a change drops every other device. Five misses in a row pause
unlocking for 30 seconds, doubling per further miss up to 16 minutes. Serial
`password` or three quick restarts remove it. Traffic is not encrypted.

## Wi-Fi setup

A controller with no stored network raises the open network **Glow Setup**
(192.168.4.1). In the app, Settings › Controller › Change Wi-Fi Network lists
what the controller sees, takes the password (and a username for enterprise
networks) and hands it over. This needs the Hotspot Configuration entitlement.
The controller keeps the setup network up until the app confirms, the app
checks the controller's identity on the new network before reporting Ready, and
credentials are written only after the join succeeds.

The two most recent networks are kept in NVS, surviving reflashes. On boot the
controller scans once and joins the stronger one it sees. When neither is seen
(a hidden network) it tries each in turn every ten seconds. A dropped network is
retried at once. After a minute without either it raises **Glow Setup** until it
joins. Three power cycles of under five seconds each raise it for five minutes
and also remove the password. Serial `forget` or the app's forget button erase
the networks. 2.4 GHz only.

## Hardware

Arduino Uno R4 WiFi, using only its onboard ESP32-S3, and an auto-direction
RS485 module TTL485-V2.0 (no DE/RE pin).

| From | To |
|---|---|
| POWER header `3V3` | module `VCC` |
| POWER header `GND` | module `GND` |
| ESP 2×3 header `ESP_IO42` | module `RXD` |
| module `D+/A` | XLR pin 3 |
| module `D-/B` | XLR pin 2 |
| module `GND` | XLR pin 1 |

The transmit pin goes to `RXD` (the module names pins from its own side).
GPIO42, not GPIO43, which the RA4M1 holds up. 3.3 V from the POWER header, since
the 2×3 header has no 3V3. The controller end of the XLR is male. If nothing
decodes, swap `D+/A` and `D-/B`.

If an upload cannot reach the bootloader, bridge `GND` and `ESP_DOWNLOAD` on the
2×3 header, upload, then remove the bridge or the chip stays in the bootloader.

`partitions.csv` gives `app0` 2 MB (the firmware uses about 1.6 MB) and 6.2 MB
to a LittleFS partition for shows, formatted on first boot. With the custom
scheme the compiler reports the whole flash as the maximum, so size against
`app0`. At boot the controller deletes any file there that is not the show list
or part of a listed show.

Serial console at 115200: `net` (firmware, address, clients, memory, loop stack,
filesystem, stored networks), `setup`, `forget`, `home` (HomeKit database),
`unpair`, `password` (removes it), `key` (prints the stored key). Log lines lead
with their area (`dmx`, `wifi`, `store`, `home`, `setup`, `link`). Unread output
is dropped, never waited on.

## Toolchain

arduino-esp32 core 3.3.12, ESP-IDF 5.5.5, esp_dmx 4.1.0, WebSockets 2.7.2,
ArduinoJson 7.4.3, HomeSpan 2.1.8.

**esp_dmx must be patched.** `Arduino/patch_esp_dmx.sh` (idempotent, keeps
`.orig` backups, defaults to `~/Documents/Arduino/libraries/esp_dmx/src`) makes
it build against ESP-IDF 5.3 and later, forces its ISR into IRAM, and restarts
the mark-after-break timer after the break actually ends. Without the last two,
cheap LED fixtures flicker because the mark drops under 8 µs. The script stamps
`GLOW_ESP_DMX_PATCHED 3` into `esp_dmx.h` and `DmxBus.cpp` refuses to build
without it. Never remove the patches, the stamp or the check. A new patch bumps
the number in both places.

**Use `DMX_NUM_1`.** Port 0 is the console and `DMX_NUM_2` crashes in
`dmx_driver_install()` ([esp_dmx#228](https://github.com/someweisguy/esp_dmx/issues/228)).

## Wire protocol

WebSocket at `ws://glow.local/ws`, port 80, found over mDNS. A client that has
connected before also tries the last address the controller reported, in
parallel, and keeps whichever answers first. The client must not offer a
WebSocket subprotocol.

DMX frames are binary:

```
byte 0      opcode    0x01 output, 0x02 source, 0x04 both
byte 1      universe  0
bytes 2-3   start     uint16 LE, 1-based
bytes 4-5   length    uint16 LE
bytes 6..   values
```

`0x01` is output after master and blackout: clocked, not relayed. `0x02` is the
programmer's source before master: stored and relayed, not clocked. `0x04` is
both, sent whenever master and blackout leave the look unchanged: clocked, then
relayed as a source. The app sends a full universe on connect and deltas after,
never on a timer.

`0x03` is a document, how an edit reaches the controller and every other device
in one hop:

```
byte 0      opcode    0x03 document
byte 1      0 put, 1 delete
byte 2      show name length
byte 3      folder name length
byte 4      object id length
bytes 5-6   body length, uint16 LE
bytes 7..   show, folder, id, body
```

The controller stores the body, relays the frame to every other client, and
answers the sender `{"t":"wrote"}` or `{"t":"unwritten"}` with `show`, `folder`
and `id`. The app folds an object into what it believes the controller holds
only on that answer, reloads the show when a write fails, keeps one write per
object in flight, and ignores a relayed edit to an object whose own write is in
flight. A document for a show the controller does not list is refused. Objects
over 12,000 bytes (`ShowLibrary.frameLimit`) go over HTTP instead.

`0x05` is playback state, at most 2560 bytes. The controller keeps the latest in
memory only, relays it, sends it to joining clients, and clears it on show
switch. Layout: a count of playing scenes, each scene id and its current cue id
in the order they were turned on, then address and value pairs to the end
holding what those channels were before a scene took them.

Everything else is JSON with a `t` discriminator. Types are strict: a fraction
is not an integer, a boolean is not `1`. Unreadable messages are ignored.

- Client to controller: `hello`, `ping` (`seq`), `blackout` (`on`), `master`
  (`level`), `span` (`slots`), `unlock`, `password`, and the show commands.
- Controller to client: `status`, `shows`, `refused`, `pong`, `locked`,
  `password`, `wrote`, `unwritten`, `doc`, plus `blackout` and `master` relayed
  from other clients.

Send `hello` first. It is answered with `status` (`fw`, `src`, `client`, `ip`,
`master`, `blackout`, `id`, `password`, `nonce`, `session`), `shows` and the
source frame. `pong` carries `seq`, `ram`, `ramTotal`, `store` and `storeTotal`
in bytes. `src` true means the controller holds a look and the client adopts it
with master and blackout. False means the client asserts its own. The
controller keeps its last source across disconnects. Master and blackout are
relayed like source frames so every device sends the same output.

**With a password set**, `hello` gets `locked` (`id`, `nonce`, `wrong`, `wait`
in seconds) and everything else is ignored until `{"t":"unlock","proof"}`. The
proof is hex HMAC-SHA256 of `"unlock"` followed by the nonce, keyed with the
key. A wrong proof gets a new `locked` with a fresh nonce.
`{"t":"password","proof","key"}` sets, changes or removes it: the proof signs
`"change"` plus the nonce with the current key, the new key travels XORed with
the HMAC of `"wrap"` plus the nonce (bare when none was set), and an empty `key`
removes it. Every device then gets `{"t":"password","set"}`. A refusal goes to
the sender alone as `{"t":"password","refused":"wrong"}` with `wait`, or
`"storage"`.

HTTP requests carry `X-Glow-Session` (valid while its WebSocket lives) and
`X-Glow-Client` (the `client` slot from `status`, so the sender's own writes are
not relayed back). Without a live session everything answers 403 except
`/api/info`, `/api/scan`, and `/api/provision` from the setup network.

Setup routes: `GET /api/info`, `GET /api/scan`, `POST /api/provision`,
`POST /api/setup`, `POST /api/forget`. `/api/scan` works only on the setup
network, returns at once and is polled until the list arrives.

## Show storage

**The controller owns the show list** (`/shows.json`, held in memory). Devices
send `show.add` (`id`, `name`), `show.rename` (`id`, `name`), `show.remove`
(`id`) and `show.open` (`id`), and the controller broadcasts
`{"t":"shows","active","shows":[{"id","name"}]}`. A refused command (last show,
name over 64 characters) returns the unchanged list to the sender alone,
preceded by `{"t":"refused","reason":"storage"}` or `"limit"` (64 shows) when a
person can act on it. Adding a show opens it, removing the open one opens the
first, and every device follows the active show. With no shows the controller
creates **Show 1**.

| Method | Path | |
|---|---|---|
| GET | `/api/show/<id>` | the show's eight files concatenated, as stored |
| GET, PUT | `/api/show/<id>/<folder>/<objid>` | one object |

After a PUT lands, every other client gets `{"t":"doc","show","folder","id"}`
and fetches that object.

A show is eight append-only files, `<id>` and `<id>.1` to `<id>.7`. An object
always lands in the file its folder and id hash to. Each write appends:

```
byte 0      0 put, 1 delete
byte 1      folder name length
byte 2      object id length
bytes 3-4   body length, uint16 LE
bytes 5..   folder, id, body
```

The newest record per folder and id is the object, and a delete record removes
it. The controller never parses a body and does not know what a folder means,
so a new kind of object is a new folder the app writes, with no firmware
change. Folders today: `lights`, `groups`, `made`, `scenes`, `cues`. Names are
letters, digits, `-` and `_`, up to 39 characters. An object is at most 64 KB.
One record per object, never a whole-show write, is what lets two editors'
changes both survive.

A file is rewritten with only its live records once it passes twice their size.
The controller keeps an eighth of the flash free for rewrites: a put that would
reach into it is refused, a delete never is, and a refused put first compacts
its show once until something is deleted. Rewrites sort in a fixed 32 KB table
one key slice at a time and yield every 16 KB for the watchdog. The store task
commits up to 32 queued writes per flash write. About 5.3 MB is usable for
objects, roughly 25,000 twelve-light cues.

**Nothing on the main loop waits on flash or a slow client.** HTTP has its own
task, every show write goes through the store task, and a client that accepts
nothing for a second is dropped. A download reads in pieces under the store lock
and never holds a file open, because LittleFS will not replace an open file.

**Writing flash pauses DMX** (`Flash::guarded`), since a flash write drops the
cache and would corrupt the packet on the wire. Fixtures hold their last value
for a frame or two. The app writes only on change, never on a timer.

**Output timing.** The controller clocks only up to the highest slot it has been
sent, sends as soon as new values arrive capped at `DMX_BURST_HZ` (100), and
refreshes at `DMX_REFRESH_HZ` (40) when idle.

**Object encoding.** `lights`, `groups` and `made` are JSON. Numbers in the
binary formats are unsigned LEB128, a text is a length then UTF-8. An order is
a fractional `Double`, so a drag writes one object. It is encoded as the number
`order * 256 << 1` when exact, else `1` then a little-endian double. An id is 64
random bits as eleven base64url characters (older ids are sixteen hex digits,
still valid), written as `header << 2` plus eight bytes for hex, `header << 2 |
1` plus eight bytes for base64url, or `header << 2 | 2` plus a text.

A scene: format byte `4`, the `SceneAction` raw value of `tap`, a button count
and one raw value per button, order, then name, icon and colour as texts. Each
cue is its own object:

```
byte 0      7 plain, 8 the rest is raw DEFLATE, whichever is smaller
then        scene id (header 0), order, fade and delay in tenths of a
            second, follow (0 never, else tenths plus one), label, levels
per light   header (mask length in bytes), id, channel mask, one byte per
            channel the mask sets
```

Every field decodes with a fallback, so a missing folder or field reads as
empty. An object the app cannot read in a known folder is erased from the
controller the next time its show opens.

## Apple Home

The controller serves HAP itself as a HomeKit bridge (port 1201, `_hap._tcp` on
`glow.local`, HomeSpan default code **466-37-726**). Its accessories are live
only while the show named **Home** (`HOMEKIT_SHOW`) is active, and refuse
writes otherwise. The binding is by name.

The head is the fourteen channels at `HEAD_ADDRESS` 1, fixed in `Config.h`
along with the channels Home drives, the dimmer band, the inversions and the
show name. Nothing about it comes from the app.

| Accessory | Control | What it drives | Channels |
|---|---|---|---|
| Moving Head | Moving Head | on, brightness, hue and saturation | 6 to 10 |
| Pan and Tilt | Pan | 0 to 100 percent across 540 degrees | 1 and 2 |
| Pan and Tilt | Tilt | 0 to 100 percent across 270 degrees | 3 and 4 |

Pan and Tilt are window coverings, not lightbulbs, so "turn off the lights" and
Good Night scenes leave the head's position alone. Home writes only these nine
channels, and only when the computed value differs from what the controller
holds. Brightness runs the dimmer band on channel 6 and never the emitters.
Saturation crossfades red, green and blue against white.

Every control follows the controller's source, so Glow and Home stay in step.
Colour reads back as the nearest hue and saturation. A change from Home enters
as a source frame like any device's, and master and blackout scale it.

Pair with the rig dark, because pairing writes flash. Removing the bridge in
Home leaves the controller paired, so serial `unpair` is needed before adding it
again. After a firmware change that adds or removes a control or accessory,
remove and re-add the bridge.
