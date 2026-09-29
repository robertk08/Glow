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
#include <esp_attr.h>
#include <esp_system.h>
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

  bool serve(uint8_t num, bool reading) {
    WSclient_t *client = &_clients[num];
    if (!clientIsConnected(client)) return false;

    bool heard = false;
    if (reading && client->tcp->available() > 0) heard = client->status == WSC_HEADER ? handshake(client) : take(client);
    handleHBPing(client);
    handleHBTimeout(client);
    return heard;
  }

  void drop(uint8_t num) {
    free(_bodies[num]);
    _bodies[num] = nullptr;
    _lines[num]  = String();
  }

  void keep() { _kept = true; }

 private:
  static const size_t LINE_LIMIT = 1024;

  uint8_t *_bodies[WEBSOCKETS_SERVER_CLIENT_MAX] = {};
  size_t   _got[WEBSOCKETS_SERVER_CLIENT_MAX]    = {};
  String   _lines[WEBSOCKETS_SERVER_CLIENT_MAX];
  bool     _kept = false;

  static size_t span(const WSclient_t *client) {
    const uint8_t *head = client->cWsHeader;
    if (client->cWsRXsize < 2) return 2;

    size_t size = head[1] & 0x80 ? 6 : 2;
    if ((head[1] & 0x7F) == 126) size += 2;
    if ((head[1] & 0x7F) == 127) size += 8;
    return size;
  }

  bool handshake(WSclient_t *client) {
    String &line = _lines[client->num];
    for (int c; client->status == WSC_HEADER && (c = client->tcp->read()) >= 0;) {
      if (c == '\n') {
        handleHeader(client, &line);
        line = String();
      } else if (line.length() < LINE_LIMIT) {
        line += (char)c;
      } else {
        clientDisconnect(client);
      }
    }
    return true;
  }

  bool take(WSclient_t *client) {
    uint8_t            num    = client->num;
    uint8_t           *head   = client->cWsHeader;
    WSMessageHeader_t *header = &client->cWsHeaderDecode;
    bool               heard  = false;

    if (!_bodies[num]) {
      for (size_t need = span(client); client->cWsRXsize < need; need = span(client)) {
        int n = client->tcp->read(head + client->cWsRXsize, need - client->cWsRXsize);
        if (n <= 0) return heard;
        client->cWsRXsize += n;
        heard = true;
      }

      size_t length = head[1] & 0x7F;
      if (length == 126) length = (size_t)head[2] << 8 | head[3];
      if (length == 127) length = head[2] | head[3] | head[4] | head[5] ? SIZE_MAX : (size_t)head[6] << 24 | (size_t)head[7] << 16 | (size_t)head[8] << 8 | head[9];
      header->fin        = head[0] >> 7;
      header->opCode     = (WSopcode_t)(head[0] & 0x0F);
      header->mask       = head[1] >> 7;
      header->payloadLen = length;
      header->maskKey    = header->mask ? head + client->cWsRXsize - 4 : nullptr;

      if (length > WEBSOCKETS_MAX_DATA_SIZE) {
        WebSockets::clientDisconnect(client, 1009);
        return true;
      }
      if (!length) {
        handleWebsocketPayloadCb(client, true, nullptr);
        return true;
      }
      _bodies[num] = (uint8_t *)malloc(length + 1);
      _got[num]    = 0;
      if (!_bodies[num]) return heard;
    }

    int n = client->tcp->read(_bodies[num] + _got[num], header->payloadLen - _got[num]);
    if (n > 0) _got[num] += n;
    if (_got[num] < header->payloadLen) return n > 0;

    uint8_t *payload = _bodies[num];
    _bodies[num]     = nullptr;
    if (!header->fin || (header->opCode != WSop_text && header->opCode != WSop_binary)) {
      handleWebsocketPayloadCb(client, true, payload);
      return true;
    }

    for (size_t i = 0; header->mask && i < header->payloadLen; i++) payload[i] ^= header->maskKey[i % 4];
    payload[header->payloadLen] = 0;
    client->cWsRXsize           = 0;
    _kept                       = false;
    runCbEvent(num, header->opCode == WSop_text ? WStype_TEXT : WStype_BIN, payload, header->payloadLen);
    if (!_kept) free(payload);
    return true;
  }
};

Sockets g_ws;

const uint8_t OP_DOCUMENT = 0x03;
const uint8_t NO_CLIENT   = 0xFF;
const uint8_t EMPTY_MAP[] = {STAGE_MAP};
const size_t  HEADROOM    = WEBSOCKETS_MAX_HEADER_SIZE;

const uint32_t WS_PING_MS     = 4000;
const uint32_t WS_PONG_MS     = 2000;
const uint32_t WS_SILENCE_MS  = 8000;
const uint32_t WS_PATIENCE_MS = 1000;
const uint32_t STORE_WAIT_MS  = 5000;
const uint32_t STARVED_MS     = 5000;
const size_t   HEAP_FLOOR     = 24576;
const uint32_t KEPT           = 0x676C6F77;

struct Kept {
  uint32_t mark;
  float    master;
  bool     blackout;
  uint8_t  source[STAGE_SLOTS];
};

RTC_NOINIT_ATTR Kept g_kept;
const uint32_t STEP_MS        = 5;
const uint32_t RELAY_MS       = 40;
const int      PLAY_STACK     = 2048;
const int      PLAY_PRIORITY  = 4;
const int      PLAY_CORE      = 1;

static_assert(WEBSOCKETS_SERVER_CLIENT_MAX <= STAGE_CLIENTS, "every phone needs its own bit in the stage");

Stage            *g_stage      = nullptr;
SemaphoreHandle_t g_lock       = nullptr;
uint8_t           g_frame[HEADROOM + STAGE_FRAME_MAX];
uint8_t          *g_state      = nullptr;
size_t            g_stateRoom  = 0;
bool              g_haveSource = false;
volatile bool     g_restated   = false;
uint32_t          g_stated     = 0;
uint32_t          g_stepped    = 0;
uint32_t          g_relayed    = 0;
uint32_t          g_fed        = 0;
portMUX_TYPE      g_sessions   = portMUX_INITIALIZER_UNLOCKED;
float             g_master     = 1;
bool              g_blackout   = false;
char              g_out[512];
bool         g_admitted[WEBSOCKETS_SERVER_CLIENT_MAX] = {};
bool         g_greeted[WEBSOCKETS_SERVER_CLIENT_MAX]  = {};
uint16_t     g_seq[WEBSOCKETS_SERVER_CLIENT_MAX]      = {};
uint16_t     g_framed[WEBSOCKETS_SERVER_CLIENT_MAX]   = {};
char         g_nonce[WEBSOCKETS_SERVER_CLIENT_MAX][Access::TOKEN_SIZE];
char         g_session[WEBSOCKETS_SERVER_CLIENT_MAX][Access::TOKEN_SIZE];
uint16_t     g_arrival[WEBSOCKETS_SERVER_CLIENT_MAX] = {};
uint32_t     g_heard[WEBSOCKETS_SERVER_CLIENT_MAX]   = {};
Store::Job   g_parked[WEBSOCKETS_SERVER_CLIENT_MAX]  = {};

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

void stamp(uint8_t *at, uint16_t seq) {
  at[0] = (uint8_t)(seq & 0xFF);
  at[1] = (uint8_t)(seq >> 8);
}

void announce(uint8_t to) {
  size_t n;
  {
    Hold   hold;
    size_t need = HEADROOM + stage_state(g_stage, millis(), nullptr, 0);
    if (need > g_stateRoom) {
      free(g_state);
      g_state     = (uint8_t *)malloc(need);
      g_stateRoom = g_state ? need : 0;
    }
    n = g_state ? stage_state(g_stage, millis(), g_state + HEADROOM, g_stateRoom - HEADROOM) : 0;
  }
  for (uint8_t i = 0; n && i < WEBSOCKETS_SERVER_CLIENT_MAX; i++) {
    if ((to != NO_CLIENT && i != to) || !admitted(i) || !g_greeted[i]) continue;
    g_state[HEADROOM + 1] = i;
    stamp(g_state + HEADROOM + 2, g_seq[i]);
    g_ws.sendBIN(i, g_state, n, true);
  }
}

bool refresh(uint8_t num, bool whole) {
  size_t n;
  {
    Hold hold;
    n = stage_frame(g_stage, num, whole, g_frame + HEADROOM, STAGE_FRAME_MAX);
  }
  if (!n) return false;
  stamp(g_frame + HEADROOM + 1, g_framed[num]);
  return g_ws.sendBIN(num, g_frame, n, true);
}

void play(void *) {
  TickType_t woke = xTaskGetTickCount();
  for (;;) {
    {
      Hold hold;
      if (stage_tick(g_stage, millis())) g_restated = true;
      light();
    }
    xTaskDelayUntil(&woke, pdMS_TO_TICKS(STEP_MS));
  }
}

void step(bool forced = false) {
  uint32_t at = millis();
  if (!forced && at - g_stepped < STEP_MS) return;
  g_stepped = at;

  bool due = at - g_relayed >= RELAY_MS;
  for (uint8_t i = 0; due && i < WEBSOCKETS_SERVER_CLIENT_MAX; i++) {
    if (admitted(i) && g_greeted[i] && refresh(i, false)) g_relayed = at;
  }
  if (!g_restated || at - g_stated < RELAY_MS) return;
  g_restated = false;
  g_stated   = at;
  announce(NO_CLIENT);
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

void onDocument(uint8_t num, uint8_t *p, size_t len) {
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
  if (!Store::ready() || !Store::safe(show) || !Store::safe(folder) || !Store::safe(id)) return answer(num, p, false);

  g_ws.keep();
  Store::Job job = {p, len, num | (g_arrival[num] << 8), false, nullptr, nullptr};
  if (!Store::submit(job)) g_parked[num] = job;
}

void onBinary(uint8_t num, uint8_t *p, size_t len) {
  if (!admitted(num) || !len) return;
  if (p[0] == OP_DOCUMENT) return onDocument(num, p, len);

  if (p[0] == STAGE_COMMAND) {
    {
      Hold hold;
      stage_command(g_stage, p, len, num, millis());
      stage_tick(g_stage, millis());
      light();
    }
    if (len >= 3) g_seq[num] = p[1] | p[2] << 8;
    g_restated = true;
    return step(true);
  }

  if (p[0] == STAGE_MAP) {
    Hold hold;
    stage_map(g_stage, p, len);
    return light();
  }

  bool written;
  {
    Hold hold;
    written = stage_write(g_stage, p, len, num);
    light();
  }
  if (!written) return;
  g_framed[num] = p[1] | p[2] << 8;
  g_haveSource  = true;
  step();
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
  if (g_haveSource) refresh(num, true);
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

void write(int start, const uint8_t *values, int length) {
  uint8_t frame[7 + STAGE_SLOTS] = {STAGE_FRAME, 0, 0, (uint8_t)(start & 0xFF), (uint8_t)(start >> 8), (uint8_t)(length & 0xFF), (uint8_t)(length >> 8)};
  memcpy(frame + 7, values, length);
  stage_write(g_stage, frame, 7 + length, NO_CLIENT);
  g_haveSource = true;
}

void restart(const char *why) {
  for (uint32_t since = millis(); !Store::idle() && millis() - since < STORE_WAIT_MS; delay(1)) settle();
  Serial.printf("link: restarting, %s\n", why);
  {
    Hold hold;
    memcpy(g_kept.source, stage_source(g_stage) + 1, STAGE_SLOTS);
    g_kept.master   = g_master;
    g_kept.blackout = g_blackout;
    g_kept.mark     = KEPT;
    DmxBus::keep();
  }
  delay(200);
  ESP.restart();
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
    Shows::Outcome outcome  = Shows::apply(t + 5, doc["id"] | "", doc["name"] | "");
    bool           homeless = outcome == Shows::DONE && HomeKit::showChanged();
    if (strcmp(was, Shows::active())) {
      {
        Hold hold;
        stage_clear(g_stage);
        stage_map(g_stage, EMPTY_MAP, sizeof(EMPTY_MAP));
        light();
      }
      g_restated = true;
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
    if (homeless) restart("the Home show closed");
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
  g_seq[num]      = 0;
  g_framed[num]   = 0;
  memcpy(g_session[num], session, sizeof(session));
  portEXIT_CRITICAL(&g_sessions);
  Serial.printf("link: phone %u joined from %s\n", num, g_ws.remoteIP(num).toString().c_str());
}

void leave(uint8_t num) {
  free(g_parked[num].frame);
  g_parked[num].frame = nullptr;
  g_ws.drop(num);
  {
    Hold hold;
    if (stage_forget(g_stage, num)) g_restated = true;
  }
  portENTER_CRITICAL(&g_sessions);
  g_admitted[num] = false;
  g_greeted[num]  = false;
  g_session[num][0] = '\0';
  portEXIT_CRITICAL(&g_sessions);
  Serial.printf("link: phone %u left\n", num);
}

void listen() {
  for (uint8_t i = 0; i < WEBSOCKETS_SERVER_CLIENT_MAX; i++) {
    if (g_parked[i].frame && Store::submit(g_parked[i])) g_parked[i].frame = nullptr;
    if (g_ws.serve(i, !g_parked[i].frame) || g_parked[i].frame) g_heard[i] = millis();
  }
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
  if (g_kept.mark == KEPT && esp_reset_reason() == ESP_RST_SW) {
    int from, to;
    g_master   = g_kept.master;
    g_blackout = g_kept.blackout;
    stage_levels(g_stage, g_master, g_blackout);
    write(1, g_kept.source, STAGE_SLOTS);
    stage_output(g_stage, &from, &to);
  }
  g_kept.mark = 0;
  g_ws.begin();
  g_ws.onEvent(onEvent);
  g_ws.enableHeartbeat(WS_PING_MS, WS_PONG_MS, 0);
  xTaskCreatePinnedToCore(play, "play", PLAY_STACK, nullptr, PLAY_PRIORITY, nullptr, PLAY_CORE);
}

void tick() {
  listen();
  step();
  settle();
  if (ESP.getFreeHeap() >= HEAP_FLOOR) g_fed = millis();
  if (millis() - g_fed > STARVED_MS) restart("the memory ran out");

  for (uint8_t i = 0; i < WEBSOCKETS_SERVER_CLIENT_MAX; i++) {
    if (g_ws.clientIsConnected(i) && millis() - g_heard[i] > WS_SILENCE_MS) g_ws.disconnect(i);
  }
}

int clients() { return g_ws.connectedClients(); }

void apply(int start, const uint8_t *values, int length) {
  if (start < 1 || length < 1 || start + length - 1 > STAGE_SLOTS) return;
  Hold hold;
  write(start, values, length);
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
