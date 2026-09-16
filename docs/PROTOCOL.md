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

`start + length - 1` must be <= 512 or the node ignores the frame. Partial
updates are legal and expected: the app sends only the range it changed.

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

Node -> app:

| `t` | Fields | Meaning |
|---|---|---|
| `status` | `fw`, `id`, `name`, `hz`, `blackout`, `uptime` | Sent on `hello` and on any state change. |
| `pong` | `seq` | Heartbeat reply. |
| `error` | `code`, `message` | Malformed frame, out-of-range address. Never fatal. |

## Behaviour on disconnect

The node **holds its last look**. It does not black out. A light going dark
mid-use because WiFi hiccuped is worse than a light staying where it was, and
DHCP renewals and 2.4 GHz interference make brief drops normal rather than
exceptional.

## Reserved

Opcode `0x02` is reserved for a full 512-byte sync frame, `0x03` for
multi-universe. Universe byte is present now so adding a second one later is
not a protocol break.
