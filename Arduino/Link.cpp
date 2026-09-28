#include "Link.h"

#include "Access.h"
#include "DmxBus.h"
#include "HomeKit.h"
#include "Net.h"
#include "Outlet.h"
#include "Shows.h"
#include "Stage.h"
#include "Store.h"

#include <ArduinoJson.h>
#include <WebSocketsServer.h>
#include <string.h>

namespace Link {
namespace {

class Sockets : public WebSocketsServerCore {
 public:
  int adopt(Outlet *tcp, const char *url) {
    WSclient_t *client = handleNewClient(tcp);
    if (!client) return -1;

    String requestLine = "GET ";
    requestLine += url;
    handleHeader(client, &requestLine);
    return client->num;
  }
};

Sockets g_ws;

const uint8_t  OP_DOCUMENT = 0x03;
const size_t   FRAME_MAX   = 2 + 4 + STAGE_SLOTS + 4 * STAGE_SLOTS / 2;
const uint8_t  NO_CLIENT   = 0xFF;
const uint8_t  EMPTY_MAP[]     = {STAGE_MAP};

const uint32_t WS_PING_MS     = 4000;
const uint32_t WS_PONG_MS     = 2000;
const uint32_t WS_SILENCE_MS  = 8000;
const uint32_t WS_PATIENCE_MS = 1000;
const uint32_t STORE_WAIT_MS  = 5000;
const uint32_t STEP_MS        = 5;
const uint32_t RELAY_MS       = 20;

Stage            *g_stage      = nullptr;
SemaphoreHandle_t g_lock       = nullptr;
uint8_t           g_frame[FRAME_MAX];
bool              g_haveSource = false;
uint32_t          g_stepped    = 0;
uint32_t          g_relayed    = 0;
portMUX_TYPE      g_sessions   = portMUX_INITIALIZER_UNLOCKED;
float             g_master     = 1;
bool              g_blackout   = false;
char              g_out[512];
bool         g_admitted[WEBSOCKETS_SERVER_CLIENT_MAX] = {};
bool         g_greeted[WEBSOCKETS_SERVER_CLIENT_MAX]  = {};
char         g_nonce[WEBSOCKETS_SERVER_CLIENT_MAX][Access::TOKEN_SIZE];
char         g_session[WEBSOCKETS_SERVER_CLIENT_MAX][Access::TOKEN_SIZE];
uint16_t     g_arrival[WEBSOCKETS_SERVER_CLIENT_MAX] = {};
uint32_t     g_heard[WEBSOCKETS_SERVER_CLIENT_MAX]   = {};

struct Hold {
  Hold() { xSemaphoreTake(g_lock, portMAX_DELAY); }
  ~Hold() { xSemaphoreGive(g_lock); }
};

bool admitted(uint8_t num) {
  return !Access::guarded() || g_admitted[num];
}

void relay(uint8_t from, bool binary, const uint8_t *p, size_t len) {
  for (uint8_t i = 0; i < WEBSOCKETS_SERVER_CLIENT_MAX; i++) {
    if (i == from || !admitted(i) || !g_greeted[i]) continue;
    if (binary) g_ws.sendBIN(i, const_cast<uint8_t *>(p), len);
    else g_ws.sendTXT(i, const_cast<uint8_t *>(p), len);
  }
}

void reply(uint8_t num, JsonDocument &doc) {
  size_t n = serializeJson(doc, g_out, sizeof(g_out));
  g_ws.sendTXT(num, g_out, n);
}

void light() {
  int            from, to;
  const uint8_t *output = stage_output(g_stage, &from, &to);
  if (to) DmxBus::writeRange(from, output + from, to - from + 1);
}

void announce(uint8_t to) {
  uint8_t *state;
  size_t   n;
  {
    Hold hold;
    size_t room = stage_state(g_stage, millis(), nullptr, 0);
    state       = (uint8_t *)malloc(room);
    n           = state ? stage_state(g_stage, millis(), state, room) : 0;
  }
  if (n && to == NO_CLIENT) relay(NO_CLIENT, true, state, n);
  else if (n) g_ws.sendBIN(to, state, n);
  free(state);
}

void step(bool urgent) {
  uint32_t now = millis();
  if (!urgent && now - g_stepped < STEP_MS) return;
  g_stepped = now;

  bool   restated;
  size_t n = 0;
  {
    Hold hold;
    restated = stage_tick(g_stage, now);
    light();
    if (urgent || now - g_relayed >= RELAY_MS) n = stage_frame(g_stage, g_frame, sizeof(g_frame));
  }
  if (n) g_relayed = now;
  if (n) relay(NO_CLIENT, true, g_frame, n);
  if (restated) announce(NO_CLIENT);
}

void greetFrame(uint8_t num) {
  g_frame[0] = STAGE_FRAME;
  g_frame[1] = 0;
  g_frame[2] = 1;
  g_frame[3] = 0;
  g_frame[4] = STAGE_SLOTS & 0xFF;
  g_frame[5] = STAGE_SLOTS >> 8;
  {
    Hold hold;
    memcpy(g_frame + 6, stage_source(g_stage) + 1, STAGE_SLOTS);
  }
  g_ws.sendBIN(num, g_frame, 6 + STAGE_SLOTS);
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

  int n = snprintf(g_out, sizeof(g_out), "{\"t\":\"%s\",\"show\":\"%s\",\"folder\":\"%s\",\"id\":\"%s\"}", stored ? "wrote" : "unwritten", show, folder, id);
  g_ws.sendTXT(num, g_out, n);
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

  for (uint32_t since = millis(); frame && millis() - since < STORE_WAIT_MS; delay(1)) {
    if (Store::submit(job)) return;
    settle();
    step(false);
  }
  free(frame);
  answer(num, p, false);
}

void onBinary(uint8_t num, uint8_t *p, size_t len) {
  if (!admitted(num) || !len) return;
  if (p[0] == OP_DOCUMENT) return onDocument(num, p, len);

  if (p[0] == STAGE_COMMAND) {
    {
      Hold hold;
      stage_command(g_stage, num, p, len, millis());
    }
    step(true);
    return announce(NO_CLIENT);
  }

  if (p[0] == STAGE_MAP) {
    Hold hold;
    stage_map(g_stage, p, len);
    return light();
  }

  bool written;
  {
    Hold hold;
    written = stage_write(g_stage, p, len, true);
    light();
  }
  if (!written) return;
  g_haveSource = true;
  relay(num, true, p, len);
}

void greet(uint8_t num) {
  g_greeted[num] = true;
  JsonDocument out;
  out["t"] = "status";
  out["fw"] = GLOW_FW_VERSION;
  out["src"] = g_haveSource;
  out["client"] = num;
  out["ip"] = Net::up() ? Net::ip().toString() : String();
  out["master"] = g_master;
  out["blackout"] = g_blackout;
  out["id"] = Net::id();
  out["password"] = Access::guarded();
  out["nonce"] = g_nonce[num];
  out["session"] = g_session[num];
  reply(num, out);
  String list = Shows::message();
  g_ws.sendTXT(num, list);
  if (g_haveSource) greetFrame(num);
  announce(num);
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

  } else if ((!strcmp(t, "blackout") && doc["on"].is<bool>()) || (!strcmp(t, "master") && doc["level"].is<float>())) {
    g_blackout = doc["on"] | g_blackout;
    g_master   = doc["level"] | g_master;
    {
      Hold hold;
      stage_levels(g_stage, g_master, g_blackout);
      light();
    }
    relay(num, false, p, len);

  } else if (!strcmp(t, "span") && doc["slots"].is<int>()) {
    DmxBus::setUsed(doc["slots"]);

  } else if (!strncmp(t, "show.", 5)) {
    char was[Store::NAME_LIMIT];
    snprintf(was, sizeof(was), "%s", Shows::active());
    Shows::Outcome outcome = Shows::apply(t + 5, doc["id"] | "", doc["name"] | "");
    if (outcome == Shows::DONE) HomeKit::showChanged();
    if (strcmp(was, Shows::active())) {
      {
        Hold hold;
        stage_clear(g_stage);
        stage_map(g_stage, EMPTY_MAP, sizeof(EMPTY_MAP));
        light();
      }
      announce(NO_CLIENT);
    }

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
  g_greeted[num]  = false;
  memcpy(g_session[num], session, sizeof(session));
  portEXIT_CRITICAL(&g_sessions);
  Serial.printf("link: phone %u joined from %s\n", num, g_ws.remoteIP(num).toString().c_str());
}

void leave(uint8_t num) {
  portENTER_CRITICAL(&g_sessions);
  g_admitted[num] = false;
  g_greeted[num]  = false;
  g_session[num][0] = '\0';
  portEXIT_CRITICAL(&g_sessions);
  Serial.printf("link: phone %u left\n", num);
}

void onEvent(uint8_t num, WStype_t type, uint8_t *payload, size_t length) {
  g_heard[num] = millis();
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
  g_lock  = xSemaphoreCreateMutex();
  g_stage = stage_new();
  g_ws.begin();
  g_ws.onEvent(onEvent);
  g_ws.enableHeartbeat(WS_PING_MS, WS_PONG_MS, 0);
}

void tick() {
  g_ws.loop();
  step(false);
  settle();

  for (uint8_t i = 0; i < WEBSOCKETS_SERVER_CLIENT_MAX; i++) {
    if (g_ws.clientIsConnected(i) && millis() - g_heard[i] > WS_SILENCE_MS) g_ws.disconnect(i);
  }
}

int clients() { return g_ws.connectedClients(); }

void apply(int start, const uint8_t *values, int length) {
  uint8_t frame[6 + STAGE_SLOTS];
  if (start < 1 || length < 1 || start + length - 1 > STAGE_SLOTS) return;
  frame[0] = STAGE_FRAME;
  frame[1] = 0;
  frame[2] = (uint8_t)(start & 0xFF);
  frame[3] = (uint8_t)(start >> 8);
  frame[4] = (uint8_t)(length & 0xFF);
  frame[5] = (uint8_t)(length >> 8);
  memcpy(frame + 6, values, length);

  Hold hold;
  stage_write(g_stage, frame, 6 + length, false);
  g_haveSource = true;
  light();
}

void source(int start, uint8_t *out, int length) {
  if (start < 1 || length < 1 || start + length - 1 > STAGE_SLOTS) return;
  Hold hold;
  memcpy(out, stage_source(g_stage) + start, length);
}

void adopt(Outlet *tcp, const char *url) {
  tcp->patience = WS_PATIENCE_MS;
  int num = g_ws.adopt(tcp, url);
  if (num >= 0) g_heard[num] = millis();
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
