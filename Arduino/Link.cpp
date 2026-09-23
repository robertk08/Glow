#include "Link.h"

#include "DmxBus.h"
#include "Net.h"
#include "Store.h"

#include <ArduinoJson.h>
#include <WebSocketsServer.h>
#include <esp_timer.h>
#include <string.h>

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

const uint8_t  OP_OUTPUT   = 0x01;
const uint8_t  OP_SOURCE   = 0x02;
const uint8_t  OP_DOCUMENT = 0x03;
const size_t   DMX_HEADER  = 6;
const size_t   DOC_HEADER  = 7;
const uint16_t SLOTS       = 512;

uint8_t      g_source[DMX_HEADER + SLOTS];
uint8_t      g_frame[DMX_HEADER + SLOTS];
bool         g_haveSource = false;
int          g_changedFrom = 0;
int          g_changedTo   = 0;
portMUX_TYPE g_lock = portMUX_INITIALIZER_UNLOCKED;
char         g_scene[Store::NAME_LIMIT] = "";
float        g_master = 1;
bool         g_blackout = false;

const uint8_t NO_CLIENT = 0xFF;

const uint32_t WS_PING_MS    = 4000;
const uint32_t WS_PONG_MS    = 2000;
const uint8_t  WS_PING_TRIES = 2;

char g_out[320];

void header(uint8_t *frame, int start, int length) {
  frame[0] = OP_SOURCE;
  frame[1] = 0;
  frame[2] = (uint8_t)(start & 0xFF);
  frame[3] = (uint8_t)(start >> 8);
  frame[4] = (uint8_t)(length & 0xFF);
  frame[5] = (uint8_t)(length >> 8);
}

void sendError(uint8_t num, const char *code, const char *message) {
  JsonDocument doc;
  doc["t"] = "error";
  doc["code"] = code;
  doc["message"] = message;
  size_t n = serializeJson(doc, g_out, sizeof(g_out));
  g_ws.sendTXT(num, g_out, n);
}

void sendStatus(uint8_t num) {
  JsonDocument doc;
  doc["t"] = "status";
  doc["fw"] = GLOW_FW_VERSION;
  doc["id"] = Net::id();
  doc["name"] = GLOW_NODE_NAME;
  doc["src"] = g_haveSource;
  doc["uptime"] = (uint32_t)(esp_timer_get_time() / 1000000LL);
  doc["client"] = num;
  doc["ip"] = Net::up() ? Net::ip().toString() : String();
  doc["scene"] = g_scene;
  doc["master"] = g_master;
  doc["blackout"] = g_blackout;
  size_t n = serializeJson(doc, g_out, sizeof(g_out));
  g_ws.sendTXT(num, g_out, n);
}

void relayBinary(uint8_t from, const uint8_t *p, size_t len) {
  for (uint8_t i = 0; i < WEBSOCKETS_SERVER_CLIENT_MAX; i++) {
    if (i != from) g_ws.sendBIN(i, const_cast<uint8_t *>(p), len);
  }
}

void relayText(uint8_t from, const uint8_t *p, size_t len) {
  for (uint8_t i = 0; i < WEBSOCKETS_SERVER_CLIENT_MAX; i++) {
    if (i != from) g_ws.sendTXT(i, const_cast<uint8_t *>(p), len);
  }
}

void sendSource(uint8_t num) {
  portENTER_CRITICAL(&g_lock);
  memcpy(g_frame, g_source, sizeof(g_source));
  portEXIT_CRITICAL(&g_lock);
  g_ws.sendBIN(num, g_frame, sizeof(g_frame));
}

void relayChanges() {
  if (!g_changedTo) return;

  portENTER_CRITICAL(&g_lock);
  int start  = g_changedFrom;
  int length = g_changedTo - g_changedFrom + 1;
  memcpy(g_frame + DMX_HEADER, g_source + DMX_HEADER + (start - 1), length);
  g_changedFrom = 0;
  g_changedTo   = 0;
  portEXIT_CRITICAL(&g_lock);

  header(g_frame, start, length);
  relayBinary(NO_CLIENT, g_frame, DMX_HEADER + length);
}

void sendWritten(uint8_t num, bool stored, const char *show, const char *folder, const char *id) {
  JsonDocument doc;
  doc["t"] = stored ? "wrote" : "unwritten";
  doc["show"] = show;
  doc["folder"] = folder;
  doc["id"] = id;
  size_t n = serializeJson(doc, g_out, sizeof(g_out));
  g_ws.sendTXT(num, g_out, n);
}

void onDocument(uint8_t num, const uint8_t *p, size_t len) {
  if (len < DOC_HEADER) {
    sendError(num, "bad_frame", "document frame is shorter than its header");
    return;
  }

  size_t showLen = p[2];
  size_t folderLen = p[3];
  size_t idLen = p[4];
  size_t bodyLen = (size_t)p[5] | ((size_t)p[6] << 8);

  if (len != DOC_HEADER + showLen + folderLen + idLen + bodyLen) {
    sendError(num, "bad_length", "declared lengths do not match the frame");
    return;
  }
  if (showLen >= Store::NAME_LIMIT || folderLen >= Store::NAME_LIMIT || idLen >= Store::NAME_LIMIT) {
    sendError(num, "bad_name", "a name is longer than the store allows");
    return;
  }

  char show[Store::NAME_LIMIT];
  char folder[Store::NAME_LIMIT];
  char id[Store::NAME_LIMIT];
  const uint8_t *cursor = p + DOC_HEADER;

  memcpy(show, cursor, showLen);
  show[showLen] = '\0';
  cursor += showLen;
  memcpy(folder, cursor, folderLen);
  folder[folderLen] = '\0';
  cursor += folderLen;
  memcpy(id, cursor, idLen);
  id[idLen] = '\0';
  cursor += idLen;

  char path[Store::PATH_LIMIT];
  bool stored = Store::ready() && Store::objectPath(path, sizeof(path), show, folder, id);
  if (stored) stored = p[1] == 0 ? Store::write(path, cursor, bodyLen) : Store::remove(path);
  if (stored) relayBinary(num, p, len);
  sendWritten(num, stored, show, folder, id);
}

void onBinary(uint8_t num, const uint8_t *p, size_t len) {
  if (len < 1) {
    sendError(num, "bad_frame", "binary frame is empty");
    return;
  }
  if (p[0] == OP_DOCUMENT) {
    onDocument(num, p, len);
    return;
  }
  if (len < DMX_HEADER) {
    sendError(num, "bad_frame", "binary frame is shorter than its header");
    return;
  }
  if (p[0] != OP_OUTPUT && p[0] != OP_SOURCE) {
    sendError(num, "bad_opcode", "opcode must be 0x01 output, 0x02 source or 0x03 document");
    return;
  }
  if (p[1] != 0) {
    sendError(num, "bad_universe", "only universe 0 exists");
    return;
  }

  uint16_t start = (uint16_t)p[2] | ((uint16_t)p[3] << 8);
  uint16_t length = (uint16_t)p[4] | ((uint16_t)p[5] << 8);

  if (len - DMX_HEADER != length) {
    sendError(num, "bad_length", "declared length does not match the frame");
    return;
  }
  if (start < 1 || length == 0 || (uint32_t)start + length - 1 > SLOTS) {
    sendError(num, "range", "start + length - 1 must be within 1..512");
    return;
  }

  if (p[0] == OP_OUTPUT) {
    DmxBus::writeRange(start, p + DMX_HEADER, length);
    return;
  }

  portENTER_CRITICAL(&g_lock);
  memcpy(g_source + DMX_HEADER + (start - 1), p + DMX_HEADER, length);
  g_haveSource = true;
  portEXIT_CRITICAL(&g_lock);
  relayBinary(num, p, len);
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
    if (g_haveSource) sendSource(num);

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
    g_blackout = on.as<bool>();
    relayText(num, p, len);

  } else if (!strcmp(t, "scene")) {
    const char *id = doc["id"];
    if (!id || strlen(id) >= Store::NAME_LIMIT) {
      sendError(num, "bad_value", "scene needs id as a short string");
      return;
    }
    snprintf(g_scene, sizeof(g_scene), "%s", id);
    relayText(num, p, len);

  } else if (!strcmp(t, "span")) {
    JsonVariant slots = doc["slots"];
    if (!slots.is<int>()) {
      sendError(num, "bad_value", "span needs slots as an integer");
      return;
    }
    DmxBus::setUsed(slots.as<int>());

  } else if (!strcmp(t, "master")) {
    JsonVariant level = doc["level"];
    if (!level.is<float>()) {
      sendError(num, "bad_value", "master needs level as a number");
      return;
    }
    g_master = level.as<float>();
    relayText(num, p, len);

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
  header(g_source, 1, SLOTS);

  g_ws.begin();
  g_ws.onEvent(onEvent);
  g_ws.enableHeartbeat(WS_PING_MS, WS_PONG_MS, WS_PING_TRIES);
  g_running = true;
  Serial.printf("ws: ws://%s.local%s\n", GLOW_HOSTNAME, GLOW_WS_PATH);
}

void tick() {
  if (!g_running) return;
  g_ws.loop();
  relayChanges();
}

int clients() { return g_running ? g_ws.connectedClients() : 0; }

void apply(int start, const uint8_t *source, const uint8_t *output, int length) {
  if (start < 1 || length < 1 || (uint32_t)start + length - 1 > SLOTS) return;
  int last = start + length - 1;

  portENTER_CRITICAL(&g_lock);
  memcpy(g_source + DMX_HEADER + (start - 1), source, length);
  g_haveSource = true;
  if (!g_changedTo || start < g_changedFrom) g_changedFrom = start;
  if (last > g_changedTo) g_changedTo = last;
  portEXIT_CRITICAL(&g_lock);

  DmxBus::writeRange(start, output, length);
}

void source(int start, uint8_t *out, int length) {
  if (start < 1 || length < 1 || (uint32_t)start + length - 1 > SLOTS) return;
  portENTER_CRITICAL(&g_lock);
  memcpy(out, g_source + DMX_HEADER + (start - 1), length);
  portEXIT_CRITICAL(&g_lock);
}

float master() { return g_master; }

bool blackout() { return g_blackout; }

void notify(const char *json, int except) {
  if (!g_running) return;
  size_t len = strlen(json);
  for (uint8_t i = 0; i < WEBSOCKETS_SERVER_CLIENT_MAX; i++) {
    if ((int)i != except) g_ws.sendTXT(i, json, len);
  }
}

bool adopt(NetworkClient &tcp, const char *url) {
  return g_running ? g_ws.adopt(tcp, url) : false;
}

}  // namespace Link
