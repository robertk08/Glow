#include "Link.h"

#include "Access.h"
#include "DmxBus.h"
#include "HomeKit.h"
#include "Net.h"
#include "Outlet.h"
#include "Shows.h"
#include "Store.h"

#include <ArduinoJson.h>
#include <WebSocketsServer.h>
#include <string.h>

namespace Link {
namespace {

class Sockets : public WebSocketsServerCore {
 public:
  void adopt(Outlet *tcp, const char *url) {
    WSclient_t *client = handleNewClient(tcp);
    if (!client) return;

    String requestLine = "GET ";
    requestLine += url;
    handleHeader(client, &requestLine);
  }
};

Sockets g_ws;

const uint8_t  OP_OUTPUT   = 0x01;
const uint8_t  OP_SOURCE   = 0x02;
const uint8_t  OP_DOCUMENT = 0x03;
const uint8_t  OP_BOTH     = 0x04;
const size_t   DMX_HEADER  = 6;
const uint16_t SLOTS       = 512;
const uint8_t  NO_CLIENT   = 0xFF;

const uint32_t WS_PING_MS     = 4000;
const uint32_t WS_PONG_MS     = 2000;
const uint8_t  WS_PING_TRIES  = 2;
const uint32_t WS_PATIENCE_MS = 1000;

uint8_t      g_source[DMX_HEADER + SLOTS];
uint8_t      g_frame[DMX_HEADER + SLOTS];
bool         g_haveSource  = false;
int          g_changedFrom = 0;
int          g_changedTo   = 0;
portMUX_TYPE g_lock        = portMUX_INITIALIZER_UNLOCKED;
portMUX_TYPE g_sessions    = portMUX_INITIALIZER_UNLOCKED;
char         g_scene[Store::NAME_LIMIT] = "";
float        g_master   = 1;
bool         g_blackout = false;
char         g_out[512];
bool         g_admitted[WEBSOCKETS_SERVER_CLIENT_MAX] = {};
char         g_nonce[WEBSOCKETS_SERVER_CLIENT_MAX][Access::TOKEN_SIZE];
char         g_session[WEBSOCKETS_SERVER_CLIENT_MAX][Access::TOKEN_SIZE];
uint16_t     g_arrival[WEBSOCKETS_SERVER_CLIENT_MAX] = {};

bool admitted(uint8_t num) {
  return !Access::guarded() || g_admitted[num];
}

bool inUniverse(int start, int length) {
  return start >= 1 && length >= 1 && start + length - 1 <= SLOTS;
}

void relay(uint8_t from, bool binary, const uint8_t *p, size_t len) {
  for (uint8_t i = 0; i < WEBSOCKETS_SERVER_CLIENT_MAX; i++) {
    if (i == from || !admitted(i)) continue;
    if (binary) g_ws.sendBIN(i, const_cast<uint8_t *>(p), len);
    else g_ws.sendTXT(i, const_cast<uint8_t *>(p), len);
  }
}

void reply(uint8_t num, JsonDocument &doc) {
  size_t n = serializeJson(doc, g_out, sizeof(g_out));
  g_ws.sendTXT(num, g_out, n);
}

void sendFrame(uint8_t to, int start, int length) {
  portENTER_CRITICAL(&g_lock);
  memcpy(g_frame + DMX_HEADER, g_source + DMX_HEADER + (start - 1), length);
  portEXIT_CRITICAL(&g_lock);

  g_frame[0] = OP_SOURCE;
  g_frame[1] = 0;
  g_frame[2] = (uint8_t)(start & 0xFF);
  g_frame[3] = (uint8_t)(start >> 8);
  g_frame[4] = (uint8_t)(length & 0xFF);
  g_frame[5] = (uint8_t)(length >> 8);

  if (to == NO_CLIENT) relay(NO_CLIENT, true, g_frame, DMX_HEADER + length);
  else g_ws.sendBIN(to, g_frame, DMX_HEADER + length);
}

void relayChanges() {
  if (!g_changedTo) return;

  portENTER_CRITICAL(&g_lock);
  int start  = g_changedFrom;
  int length = g_changedTo - g_changedFrom + 1;
  g_changedFrom = 0;
  g_changedTo   = 0;
  portEXIT_CRITICAL(&g_lock);

  sendFrame(NO_CLIENT, start, length);
}

const uint8_t *name(const uint8_t *cursor, size_t len, char *out) {
  memcpy(out, cursor, len);
  out[len] = '\0';
  return cursor + len;
}

void names(const uint8_t *p, char *show, char *folder, char *id) {
  name(name(name(p + Store::DOC_HEADER, p[2], show), p[3], folder), p[4], id);
}

void answer(uint8_t num, const uint8_t *p, bool stored) {
  char show[Store::NAME_LIMIT];
  char folder[Store::NAME_LIMIT];
  char id[Store::NAME_LIMIT];
  names(p, show, folder, id);

  JsonDocument doc;
  doc["t"]      = stored ? "wrote" : "unwritten";
  doc["show"]   = show;
  doc["folder"] = folder;
  doc["id"]     = id;
  reply(num, doc);
}

void onDocument(uint8_t num, const uint8_t *p, size_t len) {
  if (len < Store::DOC_HEADER || p[1] > 1) return;

  size_t showLen   = p[2];
  size_t folderLen = p[3];
  size_t idLen     = p[4];
  size_t bodyLen   = (size_t)p[5] | ((size_t)p[6] << 8);

  if (len != Store::DOC_HEADER + showLen + folderLen + idLen + bodyLen) return;

  char show[Store::NAME_LIMIT];
  char folder[Store::NAME_LIMIT];
  char id[Store::NAME_LIMIT];
  if (showLen >= Store::NAME_LIMIT || folderLen >= Store::NAME_LIMIT || idLen >= Store::NAME_LIMIT) return;
  names(p, show, folder, id);
  if (!Store::safe(show) || !Store::safe(folder) || !Store::safe(id)) return answer(num, p, false);

  uint8_t   *frame = (uint8_t *)malloc(len);
  Store::Job job   = {frame, len, num | (g_arrival[num] << 8), false, nullptr, nullptr};
  if (frame) memcpy(frame, p, len);
  if (frame && Store::submit(job)) return;
  free(frame);
  answer(num, p, false);
}

void settle() {
  Store::Job job;
  while (Store::settled(job)) {
    if (job.done && job.stored) {
      char show[Store::NAME_LIMIT];
      char folder[Store::NAME_LIMIT];
      char id[Store::NAME_LIMIT];
      names(job.frame, show, folder, id);
      snprintf(g_out, sizeof(g_out), "{\"t\":\"doc\",\"show\":\"%s\",\"folder\":\"%s\",\"id\":\"%s\"}", show, folder, id);
      relay(job.client < 0 ? NO_CLIENT : (uint8_t)job.client, false, (const uint8_t *)g_out, strlen(g_out));
    } else if (!job.done) {
      uint8_t num     = job.client & 0xFF;
      bool    present = (job.client >> 8) == g_arrival[num];
      if (job.stored) relay(present ? num : NO_CLIENT, true, job.frame, job.length);
      if (present) answer(num, job.frame, job.stored);
    }
    free(job.frame);
  }
}

void onBinary(uint8_t num, uint8_t *p, size_t len) {
  if (!admitted(num)) return;
  if (len >= 1 && p[0] == OP_DOCUMENT) return onDocument(num, p, len);
  if (len < DMX_HEADER || p[1] != 0 || (p[0] != OP_OUTPUT && p[0] != OP_SOURCE && p[0] != OP_BOTH)) return;

  int start  = p[2] | (p[3] << 8);
  int length = p[4] | (p[5] << 8);
  if (len - DMX_HEADER != (size_t)length || !inUniverse(start, length)) return;

  if (p[0] != OP_SOURCE) DmxBus::writeRange(start, p + DMX_HEADER, length);
  if (p[0] == OP_OUTPUT) return;

  p[0] = OP_SOURCE;
  portENTER_CRITICAL(&g_lock);
  memcpy(g_source + DMX_HEADER + (start - 1), p + DMX_HEADER, length);
  g_haveSource = true;
  portEXIT_CRITICAL(&g_lock);
  relay(num, true, p, len);
}

void greet(uint8_t num) {
  JsonDocument out;
  out["t"] = "status";
  out["fw"] = GLOW_FW_VERSION;
  out["src"] = g_haveSource;
  out["client"] = num;
  out["ip"] = Net::up() ? Net::ip().toString() : String();
  out["scene"] = g_scene;
  out["master"] = g_master;
  out["blackout"] = g_blackout;
  out["id"] = Net::id();
  out["password"] = Access::guarded();
  out["nonce"] = g_nonce[num];
  out["session"] = g_session[num];
  reply(num, out);
  String list = Shows::message();
  g_ws.sendTXT(num, list);
  if (g_haveSource) sendFrame(num, 1, SLOTS);
}

void release() {
  for (uint8_t i = 0; i < WEBSOCKETS_SERVER_CLIENT_MAX; i++) {
    if (g_ws.clientIsConnected(i) && !g_admitted[i]) greet(i);
  }
}

void challenge(uint8_t num, bool wrong) {
  JsonDocument out;
  out["t"] = "locked";
  out["id"] = Net::id();
  out["nonce"] = g_nonce[num];
  out["wrong"] = wrong;
  out["wait"] = Access::waiting();
  reply(num, out);
}

void unlock(uint8_t num, const char *proof) {
  if (!Access::verify("unlock", g_nonce[num], proof)) {
    Access::fresh(g_nonce[num]);
    return challenge(num, true);
  }

  portENTER_CRITICAL(&g_sessions);
  g_admitted[num] = true;
  portEXIT_CRITICAL(&g_sessions);
  Serial.printf("link: phone %u unlocked\n", num);
  greet(num);
}

void protect(uint8_t num, const char *proof, const char *key) {
  JsonDocument out;
  out["t"] = "password";

  if (!Access::verify("change", g_nonce[num], proof)) {
    out["refused"] = "wrong";
    out["wait"] = Access::waiting();
    return reply(num, out);
  }

  if (!Access::replace(g_nonce[num], key)) {
    out["refused"] = "storage";
    return reply(num, out);
  }

  portENTER_CRITICAL(&g_sessions);
  for (uint8_t i = 0; i < WEBSOCKETS_SERVER_CLIENT_MAX; i++) g_admitted[i] = i == num || (g_admitted[i] && !Access::guarded());
  portEXIT_CRITICAL(&g_sessions);
  Serial.printf("link: phone %u %s the password\n", num, Access::guarded() ? "set" : "removed");

  for (uint8_t i = 0; i < WEBSOCKETS_SERVER_CLIENT_MAX; i++) {
    if (i != num && Access::guarded()) g_ws.disconnect(i);
  }
  if (!Access::guarded()) release();

  out["set"] = Access::guarded();
  size_t n = serializeJson(out, g_out, sizeof(g_out));
  relay(NO_CLIENT, false, (const uint8_t *)g_out, n);
}

void onText(uint8_t num, const uint8_t *p, size_t len) {
  JsonDocument doc;
  if (deserializeJson(doc, p, len)) return;
  const char *t = doc["t"] | "";

  if (!admitted(num)) {
    if (!strcmp(t, "hello")) challenge(num, false);
    if (!strcmp(t, "unlock")) unlock(num, doc["proof"] | "");
    return;
  }

  if (!strcmp(t, "hello")) {
    greet(num);

  } else if (!strcmp(t, "password")) {
    protect(num, doc["proof"] | "", doc["key"] | "");

  } else if (!strcmp(t, "ping")) {
    JsonDocument out;
    out["t"]          = "pong";
    out["seq"]        = doc["seq"];
    out["ram"]        = ESP.getHeapSize() - ESP.getFreeHeap();
    out["ramTotal"]   = ESP.getHeapSize();
    out["store"]      = Store::used();
    out["storeTotal"] = Store::capacity();
    reply(num, out);

  } else if (!strcmp(t, "blackout") && doc["on"].is<bool>()) {
    g_blackout = doc["on"];
    relay(num, false, p, len);

  } else if (!strcmp(t, "master") && doc["level"].is<float>()) {
    g_master = doc["level"];
    relay(num, false, p, len);

  } else if (!strcmp(t, "scene") && doc["id"].is<const char *>() && strlen(doc["id"].as<const char *>()) < Store::NAME_LIMIT) {
    snprintf(g_scene, sizeof(g_scene), "%s", doc["id"].as<const char *>());
    relay(num, false, p, len);

  } else if (!strcmp(t, "span") && doc["slots"].is<int>()) {
    DmxBus::setUsed(doc["slots"]);

  } else if (!strncmp(t, "show.", 5)) {
    char was[Store::NAME_LIMIT];
    snprintf(was, sizeof(was), "%s", Shows::active());
    Shows::Outcome outcome = Shows::apply(t + 5, doc["id"] | "", doc["name"] | "");
    if (strcmp(was, Shows::active())) g_scene[0] = '\0';
    if (outcome == Shows::DONE) HomeKit::showChanged();

    if (outcome == Shows::LIMIT || outcome == Shows::STORAGE) {
      JsonDocument out;
      out["t"]      = "refused";
      out["reason"] = outcome == Shows::LIMIT ? "limit" : "storage";
      reply(num, out);
    }

    String list = Shows::message();
    if (outcome == Shows::DONE) relay(NO_CLIENT, false, (const uint8_t *)list.c_str(), list.length());
    else g_ws.sendTXT(num, list);
  }
}

void arrive(uint8_t num) {
  char session[Access::TOKEN_SIZE];
  Access::fresh(g_nonce[num]);
  Access::fresh(session);
  g_arrival[num]++;
  portENTER_CRITICAL(&g_sessions);
  g_admitted[num] = false;
  memcpy(g_session[num], session, sizeof(session));
  portEXIT_CRITICAL(&g_sessions);
  Serial.printf("link: phone %u joined from %s\n", num, g_ws.remoteIP(num).toString().c_str());
}

void leave(uint8_t num) {
  portENTER_CRITICAL(&g_sessions);
  g_admitted[num] = false;
  g_session[num][0] = '\0';
  portEXIT_CRITICAL(&g_sessions);
  Serial.printf("link: phone %u left\n", num);
}

void onEvent(uint8_t num, WStype_t type, uint8_t *payload, size_t length) {
  switch (type) {
    case WStype_CONNECTED:    arrive(num); break;
    case WStype_DISCONNECTED: leave(num); break;
    case WStype_TEXT:         onText(num, payload, length); break;
    case WStype_BIN:          onBinary(num, payload, length); break;
    default:                  break;
  }
}

}  // namespace

void begin() {
  g_ws.begin();
  g_ws.onEvent(onEvent);
  g_ws.enableHeartbeat(WS_PING_MS, WS_PONG_MS, WS_PING_TRIES);
}

void tick() {
  g_ws.loop();
  relayChanges();
  settle();
}

int clients() { return g_ws.connectedClients(); }

void apply(int start, const uint8_t *source, const uint8_t *output, int length) {
  if (!inUniverse(start, length)) return;
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
  if (!inUniverse(start, length)) return;
  portENTER_CRITICAL(&g_lock);
  memcpy(out, g_source + DMX_HEADER + (start - 1), length);
  portEXIT_CRITICAL(&g_lock);
}

float master() { return g_master; }

bool blackout() { return g_blackout; }

void adopt(Outlet *tcp, const char *url) {
  tcp->patience = WS_PATIENCE_MS;
  g_ws.adopt(tcp, url);
}

void forgetPassword() {
  Access::forget();
  release();
  const char *cleared = "{\"t\":\"password\",\"set\":false}";
  relay(NO_CLIENT, false, (const uint8_t *)cleared, strlen(cleared));
}

bool admits(const char *session) {
  if (!Access::guarded()) return true;
  bool found = false;
  portENTER_CRITICAL(&g_sessions);
  for (uint8_t i = 0; i < WEBSOCKETS_SERVER_CLIENT_MAX && !found; i++) {
    found = g_admitted[i] && session[0] && !strcmp(g_session[i], session);
  }
  portEXIT_CRITICAL(&g_sessions);
  return found;
}

}  // namespace Link
