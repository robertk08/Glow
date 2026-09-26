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
any light already patched to it moves over. No two fixtures share a name, so
the copy needs its own before it saves. Everything a bundled definition
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

A controller that stops answering is noticed within about seven seconds, and
the show gives way to the waiting screen rather than looking live. Nothing
edited after the link is lost reaches the controller, and the show reopens as
the controller holds it.

The DMX monitor shows output after master and blackout. Switch to Source to
inspect or adjust the programmer values before those controls.

Glow ships the four fixtures here, and their channel tables come from the [Cameo F2 FC DMX table](https://www.cameolight.com/en/downloads/file/id/1419641648),
[Stairville BSW-350 manual](https://images.static-thomann.de/pics/atg/atgdata/document/manual/549467_v2_en_online.pdf),
[Stairville HL-x180 manual](https://images.static-thomann.de/pics/atg/atgdata/document/manual/c_467326_467328_524858_524859_v2_en_online.pdf),
and, for the unbranded head, the [Monoprice 612870 manual](https://downloads.monoprice.com/files/manuals/612870_Manual_170822.pdf),
which is the same 7 by 10 W RGBW platform channel for channel.

## Password

**One password guards the whole controller**, every show and every channel,
and HomeKit keeps its own pairing code. There is none until someone sets one in
Settings › Controller. From then on a device that has not given it sees a
password field instead of the rig, and the controller answers it nothing else:
no frames, no shows, no commands, no HTTP.

**Each device asks once.** The app turns the password into a key with
PBKDF2-SHA256 (100,000 rounds, salted with the controller's id) and keeps that
key in the Keychain for that controller, so every later connection unlocks by
itself. Neither the password nor the key crosses the network to unlock. The
controller keeps only the key, in NVS, never the password.

Changing or removing it asks for the current one. A change drops every other
device, and each one asks for the new password. Five wrong answers in a row
pause unlocking for 30 seconds, and each further miss doubles the pause, up to
16 minutes. When everyone has forgotten it, serial `password` or three quick
restarts remove it.

It keeps out anyone with Glow who does not know the password. It does not
encrypt the traffic, so someone capturing packets on the same Wi-Fi could still
take over a connection that is already unlocked.

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

**Two networks are remembered, the two most recent.** Joining a third pushes out
the older one. On boot the controller scans once and joins the stronger of the
two it can see, so carrying it between two places needs no setup at either end
and no time goes on a network that is not there. A hidden network never shows
in a scan, so when neither is seen it tries them in turn, every ten seconds. A
network that drops is tried again straight away. Provisioning a network it already knows just moves that one back
to the front.

**Getting back to setup:** the controller raises **Glow Setup** by itself after
a minute of finding neither stored network, and keeps it up until it joins. To
ask for it while a stored network is fine, use Change Wi-Fi Network in Glow,
or power the controller off and on three times leaving it on for less than five
seconds each time, which raises the setup network for five minutes. The three
quick restarts also remove the controller's password, and otherwise nothing is
erased. Serial `forget`, or the app's forget button, is what erases networks.
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
`partitions.csv` gives the firmware 2 MB, of which it uses about 1.6 MB,
and hands the remaining **6.2 MB to shows**. Confirm it took by checking that
`partitions.csv` appears in the build folder, because the custom scheme makes
the compiler report the whole flash as the maximum rather than the app
partition. If the binary ever passes 2 MB, `app0` is the number to raise.

Shows live in that partition, mounted as LittleFS and formatted on first boot.
Coming from an older layout moves every partition, so the first flash with this
table starts you on an empty Show 1.

Serial console at 115200: `net | setup | forget | home | unpair | password | key`. The
controller prints one line per event, led by its area (`dmx`, `wifi`, `store`,
`home`, `setup`, `link`), and HomeSpan's own output is silenced. `net` reports
the firmware, the address, the connected phones, free memory, how much of the
loop's stack is spare, the show filesystem and the stored networks. `home`
prints the HomeKit accessory database with any errors in it. `password` removes
the controller's password and `key` prints the key it keeps for it. A line
nobody reads is dropped rather than waited on, so a Mac holding the port open
never stalls the controller.

## Testing against a controller

`ControllerTests` runs two complete copies of the app, as two devices, against a
real controller on the network. It covers opening, show commands, lights,
scenes, made and edited fixtures, deletes, two devices editing one light, an
edit made while the link is down, an import, deleting the open show and the
password. It creates a show named **Hardware Test**, removes it again and
leaves the controller on the show it found, with the password it found. It is
skipped unless it is given an address. Run it with the controller on USB:

```bash
GlowTests/controller-tests.sh 192.168.68.55
```

The script asks the controller for its key over serial, so the two devices get
in whatever password is set, and it turns off Xcode's diagnostics collection,
which otherwise adds more than a minute after the run. It takes about 25
seconds and the unit tests about 5. A run stopped halfway can leave a test
password behind, which serial `password` removes.

## Toolchain

arduino-esp32 core 3.3.12 · ESP-IDF 5.5.5 · esp_dmx 4.1.0 · WebSockets 2.7.2 ·
ArduinoJson 7.4.3 · HomeSpan 2.1.8

**esp_dmx needs patching, three times.** 4.1.0 does not build against ESP-IDF ≥ 5.3,
which removed `.module` from `uart_signal_conn_t`. And its ISR only goes into
IRAM when `CONFIG_DMX_ISR_IN_IRAM` is set, which Kconfig does under ESP-IDF but
cannot under Arduino, so by default the ISR sits in flash and any flash access
that drops the cache corrupts the packet on the wire as a visible flicker. And
it times the mark after break from when the break was due to end rather than
when it did, so an interrupt that arrives late eats into the mark. Read back off
the wire, the mark fell under the 8 µs a receiver must accept about once a
second, and cheap LED fixtures dropped that packet all at once while moving
heads read it fine. Patched, the mark never measured under 15 µs. Run
`./patch_esp_dmx.sh` after installing from Library Manager. Idempotent, keeps
`.orig` backups. It marks the library once every patch is in, and the sketch
refuses to build without that mark, so a fresh machine or a library update
cannot quietly bring the flicker back.

**Use `DMX_NUM_1`.** Port 0 is the console UART, and `DMX_NUM_2` crashes in
`dmx_driver_install()`, because esp_dmx drops the third UART's context entry
([#228](https://github.com/someweisguy/esp_dmx/issues/228)).

## Wire protocol

WebSocket at `ws://glow.local/ws` on port 80, the hostname the controller
answers to over mDNS. A client that has connected before also tries the address
the controller last reported, at the same time, and keeps whichever answers
first, so a changed address costs nothing.

**The client must not offer a WebSocket subprotocol.** The node's library echoes
one back and a strict client then rejects its own connection.

DMX travels as binary frames:

```
byte 0      opcode    0x01 output, 0x02 source, 0x04 both
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
client, and answers the sender with `{"t":"wrote"}`, or `{"t":"unwritten"}` when
it could not store it, both naming the show, folder and id. A client folds an
object into what it believes the controller holds only once that answer arrives,
and a write that never lands makes the app say so and reload the show as the
controller holds it. It keeps one write per object in flight and sends a newer
edit once the answer is in.
An edit relayed from another device for an object whose write is still in flight
is ignored, because the controller stores the frames in the order they arrive
and the pending write lands after it. A document for a show the controller does
not list is refused, so a device still editing a show that was just deleted
cannot bring its folder back. Anything larger than the socket carries
comfortably still goes over HTTP.

**The opcode says what the frame is for.** `0x01` is the output, what the lamps
should be doing once master and blackout are in it, and the controller clocks it
onto the wire and tells nobody. `0x02` is the source, what the programmer holds
before master touches it, and the controller stores it and passes it to every
other client without clocking it. `0x04` is both at once, which is what the app
sends whenever master and blackout leave the look as it is, so a move is one
frame rather than two. The controller clocks it and passes it on as a source.

Everything else is JSON with a `t` discriminator. Out: `hello`, `ping`,
`blackout`, `master`, `scene`, `span`, and the show commands below. In: `status`
(`fw`, `src`, `client`, `ip`, `scene`, `master`, `blackout`), `shows`, `refused`,
`pong` (with `ram`, `ramTotal`, `store` and `storeTotal` in bytes, which the
Controller screen shows live),
plus `blackout`, `master` and `scene` relayed from another client, and the
document notices below. Types are
strict, a fraction is not an integer and a boolean is not `1`. `status` and
`shows` are sent in reply to `hello`, so say hello first. `status` also carries
`id`, `password` (whether one is set), `nonce` and `session`.

**A controller with a password answers `hello` with `locked`** (`id`, `nonce`,
`wrong`, `wait` in seconds) and ignores everything else until the client sends
`{"t":"unlock","proof"}`. The proof is HMAC-SHA256 of `"unlock"` followed by the
nonce, keyed with the password key and written in hex. A right proof gets the
usual `status`, `shows` and frame. A wrong one gets a new `locked` with a fresh
nonce. `{"t":"password","proof","key"}` sets, changes or removes it: the proof
signs `"change"` and the nonce with the current key, and the new key travels
XORed with the HMAC of `"wrap"` and the nonce, or bare when there was none. An
empty `key` removes it. Every device then gets `{"t":"password","set"}`, and a
refusal goes to the sender alone as `{"t":"password","refused":"wrong"}` with
`wait`, or `"storage"`. HTTP requests carry the session as `X-Glow-Session`,
and without a live one everything but `/api/info`, `/api/scan` and provisioning
on the setup network answers 403. A session lasts as long as its WebSocket. `client` is the slot the
controller gave you, and you send it back as `X-Glow-Client` so your own writes
are not relayed to you. Anything the controller cannot read is ignored rather
than answered.

Setup is plain HTTP on the same port: `GET /api/info`, `GET /api/scan`,
`POST /api/provision`, `POST /api/setup`, `POST /api/forget`. `/api/scan` is
served only on the setup network, and it starts the scan and answers straight
away, so the app polls until the list arrives.

## Apple Home

The controller is a HomeKit bridge as well as a desk. It serves HAP itself,
so Siri and the Home app reach the rig with no phone, no hub and no other
bridge in between.

**Apple Home belongs to one show.** The accessories are live only while the show
named **Home** is the active one, because channel 1 is this head in that show
and something else entirely in the others. Switch to another show and Home's
controls refuse the write and report a failure rather than moving a stranger's
fixture. Switch back and they pick the light up again. The binding is by name,
so renaming the show in Glow moves it.

The head arrives in Home as two accessories, so its light and its position
sit on separate tiles:

| Accessory | Control | What it drives | Channels |
|---|---|---|---|
| Moving Head | Moving Head | on, brightness, hue and saturation | 6 to 10 |
| Pan and Tilt | Pan | 0 to 100 percent across 540 degrees | 1 and 2 |
| Pan and Tilt | Tilt | 0 to 100 percent across 270 degrees | 3 and 4 |

Home has no control for an axis, so Pan and Tilt borrow the window covering
service and read as a percentage rather than in degrees. They carry shade icons
and say Open and Closed at the extremes. A light is what they would rather look
like, but every Lightbulb service answers "turn off the lights" and a Good Night
scene, which would drag the head's position to zero along with the real lamps.

**Home touches only those nine channels.** The movement speed, the colour macro,
the program speed, the program and reset are the desk's alone, and a change from
Home leaves them exactly where you put them. Each control writes only the
channels it owns, and only when the value it computes differs from what the
controller already holds, so nothing is sent for a drag that lands where it
started.

Brightness runs the dimmer band on channel 6 and never touches the emitters, so
colour keeps its full resolution at any level. Saturation crossfades the red,
green and blue emitters against the white one, which is the centre of Home's
colour wheel.

**It follows the desk.** Every control reads the controller's source back and
updates itself, so moving the head in Glow moves the sliders in Home. Position, brightness and on or off come back exactly. Colour comes back
as the nearest hue and saturation Home can show, because `EmitterMix` can reach
mixes that one pair of values cannot describe.

A change from Home enters as a source frame, the same as a change from any other
device, so the app sees the fader move and the look survives for the next
device to connect. Master and blackout are held on the controller and
scale the head's dimmer the way they do everywhere else.

**The head is the fourteen channels starting at address 1.** That is fixed in
`Config.h` as `HEAD_ADDRESS` and the channels Home drives within it, along with
the dimmer band, the pan and tilt inversions, the show name, the pairing code
and the HAP port. Nothing about it is sent from the app.

**Pairing:** HAP is on port 1201, advertised as `_hap._tcp` on the same
`glow.local`. Add Glow in Home and enter **466-37-726**. Pair with the
rig dark, because pairing writes to flash and a flash write corrupts the packet
on the wire. Removing the bridge from Home leaves the controller believing it
is paired, so serial `unpair` is what lets it be added again. Home caches the
accessory database, so a firmware change that adds or removes a control or an
accessory needs the bridge removed and added back before it shows.

## Shows on the wire

**The controller keeps the list of shows.** A device never writes the list.
It sends `show.add` (`id`, `name`), `show.rename` (`id`, `name`), `show.remove`
(`id`) or `show.open` (`id`) and the controller changes the list in one step,
stores it and sends `{"t":"shows","active","shows":[{"id","name"}]}` to every
client. A command it refuses, such as removing the last show or a name over 64
characters, goes back to the sender alone as the unchanged list, so the device
puts its screen back. When the reason is one a person can act on, a full store
or the limit of 64 shows, `{"t":"refused","reason":"storage"}` or `"limit"`
comes first and the app says so. Adding a show opens it, removing the open one opens the
first, and every device follows the active show the moment the list arrives. A
controller with no shows makes **Show 1** when it starts.

Show contents move over plain HTTP on the same port, because a made fixture
definition runs to tens of kilobytes and the WebSocket carries only small
messages.

**A download is sent from its own task**, so the controller keeps answering
every phone while one of them loads a show. The ESP32 keeps a packet in its
Wi-Fi receive buffers until the program reads it. When the main loop sent a
show itself, a few busy phones filled every buffer, and the controller stopped
hearing the acknowledgements the download was waiting for, for minutes at a
time. The sender lists a folder under the store's lock and reads each file
whole, never keeping one open, because LittleFS will not replace an open file
and a directory being written can skip entries while it is listed.

| Method | Path | |
|---|---|---|
| GET | `/api/show/<id>` | the whole show, assembled |
| GET, PUT, DELETE | `/api/show/<id>/<folder>/<objid>` | one object |

A show is a folder of folders. `lights`, `groups`, `made` and `scenes` today,
and each one holds one JSON file per object named by its id. Names are letters,
digits, hyphen and underscore, up to 39 characters, and anything else is
refused. One object can be up to 64 KB.

**The controller does not know what a folder means.** It lists the folders it
finds and assembles `GET /api/show/<id>` as `{"<folder>":[…],"<folder>":[…]}`,
streaming the files in as chunks without parsing one of them. So adding cue stacks later is a folder the app
starts writing to, and the firmware does not change. `/shows.json` is the one
file the controller reads, and it keeps it in memory.

**One file per object, not one file per show.** A whole-show write would mean
your rename wiping my new scene. Per object, both survive under the same last
writer wins rule, and one edit sends one small file rather than the show.

After an HTTP write lands, the controller sends
`{"t":"doc","show","folder","id","op"}` to every client but the sender. A client
fetches just that object and applies it, so nothing reloads the show to learn
one name changed.

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
takes it along with the master and blackout, false means there is none and the
client asserts its own. On
disconnect the controller holds its last look.
