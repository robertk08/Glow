# Glow wire protocol v1

One protocol, two transports. Locally the app opens a WebSocket straight to the
node; in stage 4 the same frames travel over a Cloudflare Worker. Nothing in
this document is transport-specific, so the remote path is a new socket, not a
new protocol.

## Roles

**The app is the console.** It owns the patch, the fixture profiles and the
512-byte universe. It decides what every channel is worth.

**The node is a dumb DMX output.** It holds one universe in RAM and clocks it
onto the wire at a fixed refresh rate whether or not anything is connected. It
knows nothing about fixtures, colour or patching.

This split is deliberate. Fixture profiles change often and live in an app you
can update from the App Store; the firmware is behind a bridged jumper and a
serial cable. Keeping the node dumb means new fixture support never requires a
reflash.

## Endpoint

- mDNS service `_glow._tcp` on port 80, hostname `glow.local`
- WebSocket at `ws://<host>/ws`
- TXT records: `v=1`, `id=<mac>`, `name=<user-visible name>`

`id` is the station MAC as **12 lowercase hex digits with no separators**, and
is the same string the `status` message carries.

**The client must not offer a WebSocket subprotocol.** There is none. A client
that sends `Sec-WebSocket-Protocol` gets `arduino` echoed back by the node's
library and a strict client will then reject its own connection. This is the
most likely way a new client fails on its first attempt.

## Frames

Binary frames carry DMX. Text frames (JSON) carry everything else. A binary
frame is used because a 512-channel update is 512 bytes raw and ~700 base64,
and at 40 Hz that difference is real on a 2.4 GHz link.

### Binary: DMX update (app -> node)

```
byte 0      opcode     0x01
byte 1      universe   0 (reserved for multi-universe later)
bytes 2-3   start      uint16 LE, 1-based DMX address of the first byte
bytes 4-5   length     uint16 LE, number of channel bytes that follow
bytes 6..   values     `length` bytes
```

`start + length - 1` must be <= 512, `start` must be >= 1, and `length` must be
greater than zero — a zero-length update is answered with `bad_length` rather
than silently accepted. Partial updates are legal and expected: the app sends
only the range it changed.

### Text: JSON messages

Every message is an object with a `t` discriminator.

App -> node:

| `t` | Fields | Meaning |
|---|---|---|
| `hello` | `client`, `version` | Sent on connect. Node replies `status`. |
| `ping` | `seq` | Heartbeat. Node replies `pong` with the same `seq`. |
| `blackout` | `on` (bool) | Zero the output without touching the held universe. |
| `refresh` | `hz` (int, 10-44) | Change the DMX refresh rate. |
| `identify` | — | Flash the node's LED so you can tell which box it is. |

Types are checked strictly, because a controller that guesses at malformed
input is a controller that does something unexpected to a light. `hz` must be a
JSON integer — `40.0` is rejected — and `on` must be a real boolean, not `1`.

Node -> app:

| `t` | Fields | Meaning |
|---|---|---|
| `status` | `fw`, `id`, `name`, `hz`, `blackout`, `uptime` | Sent on `hello` and on any state change. `uptime` is whole seconds. |
| `pong` | `seq` | Heartbeat reply. |
| `error` | `code`, `message` | Malformed frame, out-of-range address. Never fatal. |

**`status` is not sent spontaneously on connect.** A client that opens the
socket and starts streaming DMX without saying `hello` never learns the node's
refresh rate or whether it is blacked out. Say `hello` first.

`code` is one of a closed set, so a client may switch on it:

`bad_frame`, `bad_opcode`, `bad_universe`, `bad_length`, `range`, `bad_json`,
`bad_message`, `bad_value`, `unknown_type`

`message` is a human-readable elaboration and is not stable — log it, do not
parse it.

## Behaviour on disconnect

The node **holds its last look**. It does not black out. A light going dark
mid-use because WiFi hiccuped is worse than a light staying where it was, and
DHCP renewals and 2.4 GHz interference make brief drops normal rather than
exceptional.

## Reserved

Opcode `0x02` is reserved for a full 512-byte sync frame, `0x03` for
multi-universe. Universe byte is present now so adding a second one later is
not a protocol break.

## Setup: getting the node onto WiFi

The node must be usable by someone who never opens the Arduino IDE, so
credentials are entered in the app, never compiled in. A node with nothing
stored brings up its own open access point and waits.

```
SSID          Glow Setup
address       192.168.4.1
lifetime      only while unprovisioned, or for 5 minutes after a long reset
```

These are plain HTTP (not the WebSocket), because the phone has to talk to the
node before either of them knows anything about the other.

| Method | Path | Body | Reply |
|---|---|---|---|
| `GET` | `/api/info` | — | `{"fw","id","name","state"}` where `state` is `unprovisioned` or `provisioned` |
| `GET` | `/api/scan` | — | `{"networks":[{"ssid","rssi","secure","channel"}]}`, strongest first, duplicates collapsed |
| `POST` | `/api/provision` | `{"ssid","password"}` | `{"ok":true}` then join, or `{"ok":false,"error":"..."}` |
| `POST` | `/api/forget` | — | `{"ok":true}` then reboot into setup |

`/api/scan` may take several seconds — a WiFi scan is not instant, and the node
is single-threaded about it. The app shows progress rather than timing out at
one second.

`/api/provision` replies **before** it tries to join, because the moment it
joins it is no longer on the setup network and the reply could never arrive.
The app confirms success by finding the node again over Bonjour on the home
network, not by the reply. A node that fails to join returns to the setup AP,
so the recovery path is to reconnect to `Glow Setup` and try again.

`/api/forget` and `/api/provision` also work on the home network, so changing
router or password never needs a cable.

**The setup AP is open**, which is a deliberate trade for hardware with no
screen and no keyboard. It exists only until the node has credentials, and
anyone close enough to join it is close enough to reach the reset button. Do
not extend the same endpoints to the general internet in stage 4.
