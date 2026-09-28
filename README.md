# Glow

An iOS 26 app (SwiftUI, SwiftData) that controls DMX stage lights over Wi-Fi,
and the ESP32-S3 firmware in `Arduino/` that puts the signal on the wire. The
code is the reference for byte layouts, limits and timings. This file holds what
the code does not say.

| Where | What |
|---|---|
| `Glow/Controller/Wire.swift` | every message the app sends or reads |
| `Glow/Shows/ShowContents.swift`, `ByteWriter.swift` | object encodings |
| `Glow/Console/Console.swift` | programmer and playback |
| `Glow/Controller/NodeLink.swift`, `NodeStore.swift` | WebSocket link, HTTP |
| `Arduino/Link.cpp` | WebSocket handling and relaying |
| `Arduino/Stage.c` | playback engine: fades, delays, follows, master |
| `Arduino/Store.cpp`, `Shows.cpp`, `Http.cpp` | show storage, show list, HTTP |
| `Arduino/Config.h` | pins, timings, the Apple Home head |
| `Glow/Fixtures/BuiltIn/*.json` | bundled fixture definitions |
| `Glow/Resources/Demo.json` | the demo show |

`Arduino/Stage.c` is compiled into the app too, through
`Glow/Glow-Bridging-Header.h`, where it runs the demo and scales the output
monitor. Keep it plain C with no Arduino includes.

## Build and test

```bash
xcodebuild test -quiet -scheme Glow -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -collect-test-diagnostics never
```

`ControllerTests` is skipped unless `TEST_RUNNER_GLOW_CONTROLLER` is set. To run
it against the real controller on USB and the LAN:

```bash
GlowTests/controller-tests.sh glow.local
```

The script reads the controller's key over serial, so it works with any
password set, and leaves the controller on the show and password it found. A run
stopped halfway can leave a test password or a show named **Hardware Test**
behind. Serial `password` removes the password. Only one process can hold the
serial port, so close any serial monitor first.

Firmware: install the libraries under Toolchain, run `Arduino/patch_esp_dmx.sh`,
then compile and upload `Arduino/` with the `arduino-cli` bundled at
`/Applications/Arduino IDE.app/Contents/Resources/app/lib/backend/resources/`,
FQBN `esp32:esp32:esp32s3:CDCOnBoot=cdc,FlashSize=8M,PartitionScheme=custom`,
port from `ls /dev/cu.usbmodem*`. If an upload cannot reach the bootloader,
bridge `GND` and `ESP_DOWNLOAD` on the ESP 2×3 header, upload, then remove the
bridge.

## Rules

- **The controller is the desk.** It stores every show and runs playback.
  Devices are terminals with nothing on disk: on connect a device loads the show
  into an in-memory SwiftData store, and disconnected it shows a waiting screen
  with setup and a demo. The controller is the only copy of the shows, and
  export is the backup.
- **The app owns meaning, the controller does not.** The app computes channel
  values from fixture definitions and sends the patch map. The controller never
  parses a show object and does not know what a folder means, so a new kind of
  object is a new folder the app writes, with no firmware change. Fixture support
  is a JSON file, never a firmware change.
- **Sync works like an X32 and its remotes.** A device applies a change locally
  at once and tells the controller after. The controller relays it to every
  other device, never back to the sender. Last writer wins per object, with no
  locking, revisions or conflict handling. Never round-trip a change through the
  controller before showing it.
- **One record per object**, never a whole-show write, so two editors' changes
  both survive.
- **No replay after a lost link.** Edits made while the link is down never reach
  the controller, and on reconnect the show reloads as the controller holds it.
- **Nothing on the firmware's main loop waits on flash or a slow client.** HTTP,
  show writes and playback have their own tasks, and a client that accepts
  nothing for a second is dropped.
- **Writing flash pauses DMX** (`Flash::guarded`), so the app writes only on
  change, never on a timer.
- **Decoders are additive.** Every field decodes with a fallback, so a missing
  field or folder reads as empty. An export is read only when its `format` and
  `version` match `ShowFile` exactly. There is no migration. An object the app
  cannot read in a known folder is erased from the controller when its show
  opens.
- **Ids are random**, eleven base64url characters. **Order is a fractional
  `Double`**, so a drag writes one object.

## Behaviour

These are product decisions the code implements without explaining.

- Selecting lights is how they are controlled. The programmer drives the whole
  selection, which stays until cleared. A group is a saved selection, not a
  container, so a light can be in several.
- Defaults are not settings. A freshly patched light reads white, centred, no
  gobo, no strobe, and none of that counts as chosen. Raising the dimmer marks
  only the dimmer.
- Master and blackout scale only dimmer channels, so position and colour hold
  through a blackout.
- A fixture channel names the attribute it drives, never an index. Editing a
  bundled fixture saves a copy under a new name and moves patched lights to it.
  The fixture builder must be able to write every field a bundled definition
  uses, and a test enforces it.
- A scene (`Look`) records lights, not addresses, and works like a desk
  executor: on, off (lights return to what they were doing), flash, and stepping
  cues. Scenes can be on together and the one turned on or stepped last wins a
  shared light. Turning a scene off hands each light it wins to the scene under
  it, or back to what the devices last set, so a light touched while a scene
  holds it keeps the touch.
- Cues track. A cue holds only the lights and aspects stored into it, the rest
  keeps what earlier cues set, and going back undoes what later cues changed.
  After the last cue, Next wraps to the first.
- A store takes the selected lights, or every light when none is selected.
  Storing into a cue replaces only the chosen aspects.
- Fades, delays and follows run on the controller, so they carry on when the
  device that started them sleeps or drops. Touching a channel mid-fade, on any
  device, releases it from the fade.
- A show stores no DMX values, so lights come back on their defaults. The
  controller address belongs to the device, not the show.

Bundled channel tables come from the
[Cameo F2 FC DMX table](https://www.cameolight.com/en/downloads/file/id/1419641648),
[Stairville BSW-350 manual](https://images.static-thomann.de/pics/atg/atgdata/document/manual/549467_v2_en_online.pdf),
[Stairville HL-x180 manual](https://images.static-thomann.de/pics/atg/atgdata/document/manual/c_467326_467328_524858_524859_v2_en_online.pdf)
and, for the unbranded 7 by 10 W RGBW head, the
[Monoprice 612870 manual](https://downloads.monoprice.com/files/manuals/612870_Manual_170822.pdf).

## Protocol

WebSocket at `ws://glow.local/ws` on port 80. The client must not offer a
WebSocket subprotocol, because the controller's library echoes it and a strict
client then rejects its own connection. The app tries the last address the
controller reported first, the other addresses half a second apart, and keeps
whichever answers first.

- Send `hello` first. Nothing else arrives before it is answered with `status`,
  `shows`, the source frame when the controller has one, and the playback
  state. JSON types are strict: a fraction is not an integer, a boolean is not
  `1`.
- `0x02` frames carry the source, values before master and blackout, and only
  the channels that changed, after a 16-bit sequence number. A device numbers
  its frames, the controller answers each device with the last number it applied
  from it, and the device ignores values for channels it wrote after that.
  `0x03` documents carry one show object. `0x05` is a playback command from a
  device and the playback state from the controller. `0x06` is the patch map,
  telling the controller which channels fade and which master scales.
- A document is answered `wrote` or `unwritten`. The app counts an object as
  stored only on `wrote`, reloads the show on `unwritten`, keeps one write per
  object and at most 12,000 bytes of documents in flight, and ignores a relayed
  edit to an object whose own write is still in flight. Objects over 12,000
  bytes go over HTTP instead (`/api/show/<id>/<folder>/<objid>`), and other
  devices then get a `doc` notice and fetch that object.
- A playback chain longer than one command's budget (6,000 bytes) is sent in
  parts. Halfway through a part the state asks the device that last commanded
  the scene for the next one, and any device once the part has run out or that
  device has left. The controller picks the answer up at whichever cue it has
  reached.
- The controller owns the show list. Devices send `show.add`, `show.rename`,
  `show.remove` and `show.open`, and the controller broadcasts the whole list.
- With a password set, `hello` is answered `locked` until the client proves the
  key with an HMAC over a nonce. Neither password nor key crosses the network to
  unlock, and the controller keeps only the key. HTTP needs the `X-Glow-Session`
  from `status`, except `/api/info`, `/api/scan` and provisioning over the
  setup network. Traffic is not encrypted.

## Controller

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

The transmit pin goes to `RXD`, because the module names pins from its own side.
GPIO43 does not work, the RA4M1 holds it up. The 2×3 header has no 3V3 pin. The
XLR is male. If nothing decodes, swap `D+/A` and `D-/B`.

`partitions.csv` gives `app0` 2 MB and the rest of the 8 MB flash to LittleFS
for shows. With the custom scheme the compiler reports the whole flash as the
maximum, so check the binary against `app0`.

Serial console at 115200: `net`, `setup`, `forget`, `home`, `unpair`,
`password`, `key`.

**Restarts keep the look.** Before the controller restarts itself it keeps the
DMX output, the source, master and blackout in memory that survives a restart,
and sends the same output again as soon as it boots. Running fades and chases
stop. It also restarts itself when free memory stays under 24 KB for five
seconds, because the network stops receiving at that point.

**Recovery.** A controller with no stored network raises the open network **Glow
Setup**, and the app provisions it from Settings › Controller. Three power
cycles of under five seconds each raise the setup network and remove the
password. Networks and the password live in NVS and survive reflashing.

## Toolchain

arduino-esp32 core 3.3.12, ESP-IDF 5.5.5, esp_dmx 4.1.0, WebSockets 2.7.2,
ArduinoJson 7.4.3, HomeSpan 2.1.8.

**esp_dmx must be patched.** `Arduino/patch_esp_dmx.sh` (idempotent, defaults
to `~/Documents/Arduino/libraries/esp_dmx/src`) makes it build against ESP-IDF
5.3 and later, forces its ISR into IRAM, and restarts the mark-after-break timer
once the break has really ended. Without the last two, cheap LED fixtures
flicker because the mark drops under 8 µs. The script stamps
`GLOW_ESP_DMX_PATCHED 3` into `esp_dmx.h` and `DmxBus.cpp` refuses to build
without it. Never remove the patches, the stamp or the check. A new patch bumps
the number in both places. Changing the DMX library means measuring the mark
again first.

**Use `DMX_NUM_1`.** Port 0 is the console and `DMX_NUM_2` crashes in
`dmx_driver_install()` ([esp_dmx#228](https://github.com/someweisguy/esp_dmx/issues/228)).

## Apple Home

The controller is a HomeKit bridge itself (HomeSpan, default code
**466-37-726**). It runs only while the show named **Home** is open, so Apple
Home sees the bridge as not responding otherwise. Leaving **Home** restarts the
controller to free its memory. Devices reconnect after about seven seconds. Its accessories drive the moving head defined in `Config.h` and are
live only while **Home** is active. Pan and tilt are window coverings, not
lightbulbs, so "turn off the lights" and Good Night scenes leave the head's
position alone.

Pair with the rig dark, because pairing writes flash. Removing the bridge in
Home leaves the controller paired, so serial `unpair` is needed before adding it
again. After a firmware change that adds or removes a control or accessory,
remove the bridge from Home and add it again.
