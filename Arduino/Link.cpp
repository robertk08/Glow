#include "Link.h"

#include "DmxBus.h"
#include "Net.h"

#include <ArduinoJson.h>
#include <WebSocketsServer.h>
#include <esp_timer.h>

namespace Link {
namespace {

class Sockets : public WebSocketsServerCore {
 public:
  bool adopt(NetworkClient &tcp, const char *url) {
    WEBSOCKETS_NETWORK_CLASS *held = new WEBSOCKETS_NETWORK_CLASS(tcp);
    WSclient_t *client = handleNewClient(held);
    if (!client) return false;   // it closed and deleted held itself

    String requestLine = "GET ";
    requestLine += url;
    handleHeader(client, &requestLine);
    return true;
  }
};

Sockets g_ws;

bool g_running = false;

const uint8_t OP_DMX     = 0x01;
const size_t  DMX_HEADER = 6;

const uint32_t WS_PING_MS    = 15000;
const uint32_t WS_PONG_MS    = 4000;
const uint8_t  WS_PING_TRIES = 2;

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
  doc["uptime"] = (uint32_t)(esp_timer_get_time() / 1000000LL);
  return serializeJson(doc, g_out, sizeof(g_out));
}

void sendStatus(uint8_t num) {
  size_t n = buildStatus();
  g_ws.sendTXT(num, g_out, n);
}

void broadcastStatus() {
  size_t n = buildStatus();
  g_ws.broadcastTXT(g_out, n);
}

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
    out["seq"] = seq;
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


  } else {
    sendError(num, "unknown_type", strlen(t) < 32 ? t : "unknown message type");
  }
}

void onEvent(uint8_t num, WStype_t type, uint8_t *payload, size_t length) {
  switch (type) {
    case WStype_CONNECTED:
      Serial.printf("ws[%u]: connected\n", num);
      break;

    case WStype_DISCONNECTED:
      Serial.printf("ws[%u]: gone\n", num);
      break;

    case WStype_TEXT:
      onText(num, payload, length);
      break;

    case WStype_BIN:
      onBinary(num, payload, length);
      break;

    default:
      break;
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

bool adopt(NetworkClient &tcp, const char *url) {
  return g_running ? g_ws.adopt(tcp, url) : false;
}

}  // namespace Link
