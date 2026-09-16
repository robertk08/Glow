#include "Link.h"

#include "DmxBus.h"
#include "Net.h"

#include <ArduinoJson.h>
#include <WebSocketsServer.h>
#include <esp_timer.h>

namespace Link {
namespace {

// Markus Sattler's WebSockets rather than an async web stack. The entire HTTP
// surface this protocol needs is one upgrade on one path, and an async server
// would cost flash and a second TCP task for nothing. Its reads block, but
// they block loop(), and loop() has not driven DMX since DmxBus grew a task.
WebSocketsServer g_ws(GLOW_WS_PORT);

bool g_running = false;

// PROTOCOL.md: 0x01 is a DMX update, 0x02 and 0x03 are reserved. An unknown
// opcode is therefore a client running ahead of this firmware, not line noise.
const uint8_t OP_DMX     = 0x01;
const size_t  DMX_HEADER = 6;

// A phone that walks out of range leaves a half-open TCP connection holding
// one of five client slots until the stack gives up on it. Ping it instead.
// This is the WebSocket's own ping, unrelated to the protocol's ping/pong,
// which measures the app's round trip rather than the socket's liveness.
const uint32_t WS_PING_MS    = 15000;
const uint32_t WS_PONG_MS    = 4000;
const uint8_t  WS_PING_TRIES = 2;

// Every message this file sends fits; status is the longest. Only ever touched
// from the loop task, which is the only task that runs any of this.
char g_out[256];

void sendError(uint8_t num, const char *code, const char *message) {
  JsonDocument doc;
  doc["t"] = "error";
  doc["code"] = code;
  doc["message"] = message;
  size_t n = serializeJson(doc, g_out, sizeof(g_out));
  g_ws.sendTXT(num, g_out, n);
}

size_t buildStatus() {
  JsonDocument doc;
  doc["t"] = "status";
  doc["fw"] = GLOW_FW_VERSION;
  doc["id"] = Net::id();
  doc["name"] = GLOW_NODE_NAME;
  doc["hz"] = DmxBus::refreshHz();
  doc["blackout"] = DmxBus::blackout();
  // Seconds since boot, from esp_timer and not millis(): millis() wraps after
  // 49 days, and a node that has been powered since the last gig should not
  // claim it booted four minutes ago.
  doc["uptime"] = (uint32_t)(esp_timer_get_time() / 1000000LL);
  return serializeJson(doc, g_out, sizeof(g_out));
}

void sendStatus(uint8_t num) {
  size_t n = buildStatus();
  g_ws.sendTXT(num, g_out, n);
}

// "on any state change", so everyone sees the same node. Two apps on the same
// universe is already possible and blackout is not a per-client setting.
void broadcastStatus() {
  size_t n = buildStatus();
  g_ws.broadcastTXT(g_out, n);
}

// ------------------------------------------------------------------ frames --
// Nothing below may do anything worse than answer with an error. A frame off
// the network is untrusted input, and the failure the app must never provoke
// is the one where the light goes out because the node rebooted.

void onBinary(uint8_t num, const uint8_t *p, size_t len) {
  if (len < DMX_HEADER) {
    sendError(num, "bad_frame", "binary frame is shorter than its header");
    return;
  }
  if (p[0] != OP_DMX) {
    sendError(num, "bad_opcode", "only opcode 0x01 exists in v1");
    return;
  }
  if (p[1] != 0) {
    sendError(num, "bad_universe", "only universe 0 exists in v1");
    return;
  }

  // uint16 little endian, assembled by hand rather than cast: the ESP32-S3 is
  // little endian and would survive the cast, but the protocol says LE and the
  // next port should not have to find that out the hard way.
  uint16_t start = (uint16_t)p[2] | ((uint16_t)p[3] << 8);
  uint16_t length = (uint16_t)p[4] | ((uint16_t)p[5] << 8);

  if (len - DMX_HEADER != length) {
    sendError(num, "bad_length", "declared length does not match the frame");
    return;
  }
  if (!DmxBus::writeRange(start, p + DMX_HEADER, length)) {
    sendError(num, "range", "start + length - 1 must be within 1..512");
    return;
  }
}

void onText(uint8_t num, const uint8_t *p, size_t len) {
  JsonDocument doc;
  DeserializationError err = deserializeJson(doc, p, len);
  if (err) {
    sendError(num, "bad_json", err.c_str());
    return;
  }

  const char *t = doc["t"];
  if (!t) {
    sendError(num, "bad_message", "every message needs a t");
    return;
  }

  if (!strcmp(t, "hello")) {
    sendStatus(num);

  } else if (!strcmp(t, "ping")) {
    JsonVariant seq = doc["seq"];
    if (seq.isNull()) {
      sendError(num, "bad_message", "ping needs a seq");
      return;
    }
    JsonDocument out;
    out["t"] = "pong";
    out["seq"] = seq;   // echoed back exactly as it arrived, any type
    size_t n = serializeJson(out, g_out, sizeof(g_out));
    g_ws.sendTXT(num, g_out, n);

  } else if (!strcmp(t, "blackout")) {
    JsonVariant on = doc["on"];
    if (!on.is<bool>()) {
      sendError(num, "bad_value", "blackout needs on as a bool");
      return;
    }
    DmxBus::setBlackout(on.as<bool>());
    broadcastStatus();

  } else if (!strcmp(t, "refresh")) {
    JsonVariant hz = doc["hz"];
    if (!hz.is<int>()) {
      sendError(num, "bad_value", "refresh needs hz as an int");
      return;
    }
    if (!DmxBus::setRefreshHz(hz.as<int>())) {
      sendError(num, "range", "hz must be 10..44");
      return;
    }
    broadcastStatus();

  } else if (!strcmp(t, "identify")) {
    // Not a state change: nothing in status describes it, so nothing to send.
    DmxBus::identify();

  } else {
    // Echoed back so the app can see what the node did not like - but only if
    // it is short. t is the one string in any of these messages whose length
    // the client chooses, and g_out has to hold whatever comes back out.
    sendError(num, "unknown_type", strlen(t) < 32 ? t : "unknown message type");
  }
}

void onConnect(uint8_t num, const char *url, size_t len) {
  // The library finishes the handshake before handing the URL over, so a wrong
  // path costs one upgrade and then a close. A query string is allowed through:
  // stage 4 will want somewhere to put a token.
  size_t path = 0;
  while (path < len && url[path] != '?') path++;
  if (path != strlen(GLOW_WS_PATH) || strncmp(url, GLOW_WS_PATH, path) != 0) {
    Serial.printf("ws[%u]: refused %.*s\n", num, (int)len, url);
    g_ws.disconnect(num);
    return;
  }
  // No greeting. PROTOCOL.md sends status on hello and on state changes, and a
  // client that has not said hello yet has not agreed to hear anything.
  Serial.printf("ws[%u]: connected\n", num);
}

void onEvent(uint8_t num, WStype_t type, uint8_t *payload, size_t length) {
  switch (type) {
    case WStype_CONNECTED:
      onConnect(num, (const char *)payload, length);
      break;

    case WStype_DISCONNECTED:
      // Hold the last look. Doing nothing here is the feature, not an
      // omission: PROTOCOL.md would rather the rig stayed where it was than
      // go dark because a DHCP renewal took too long.
      Serial.printf("ws[%u]: gone\n", num);
      break;

    case WStype_TEXT:
      onText(num, payload, length);
      break;

    case WStype_BIN:
      onBinary(num, payload, length);
      break;

    default:
      break;   // pings, pongs and fragments are the library's business
  }
}

}  // namespace

void begin() {
  g_ws.begin();
  g_ws.onEvent(onEvent);
  g_ws.enableHeartbeat(WS_PING_MS, WS_PONG_MS, WS_PING_TRIES);
  g_running = true;
  Serial.printf("ws: ws://%s.local%s\n", GLOW_HOSTNAME, GLOW_WS_PATH);
}

void tick() {
  if (g_running) g_ws.loop();
}

int clients() { return g_running ? g_ws.connectedClients() : 0; }

}  // namespace Link
