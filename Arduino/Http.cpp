#include "Http.h"

#include "Access.h"
#include "Link.h"
#include "Net.h"
#include "Outlet.h"
#include "Shows.h"
#include "Store.h"

#include <ArduinoJson.h>
#include <WiFi.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <lwip/sockets.h>

namespace Http {
namespace {

const uint32_t REQUEST_MS     = 1500;
const uint32_t DOCUMENT_MS    = 8000;
const uint32_t PATIENCE_MS    = 3000;
const size_t   REQUEST_LINE_MAX       = 256;
const size_t   REQUEST_BODY_MAX       = 512;
const size_t   DOCUMENT_MAX   = 65535;
const int      HEADERS_MAX    = 40;
const int      VISITS_WAITING = 4;
const int      SERVER_STACK   = 4096;
const size_t   PIECE          = 1436;

struct Visit {
  Outlet *client;
  char    method[8];
  char    target[REQUEST_LINE_MAX];
  char    session[Access::TOKEN_SIZE];
  size_t  length;
  char    body[REQUEST_BODY_MAX + 1];
};

QueueHandle_t     g_visits = nullptr;
SemaphoreHandle_t g_stored = nullptr;
uint8_t           g_piece[PIECE];

bool readLine(NetworkClient &c, char *buf, size_t size, uint32_t deadline) {
  size_t n = 0;
  while ((int32_t)(millis() - deadline) < 0) {
    if (!c.available()) {
      if (!c.connected()) return false;
      delay(1);
      continue;
    }
    int ch = c.read();
    if (ch < 0 || ch == '\r') continue;
    if (ch == '\n') {
      buf[n] = '\0';
      return true;
    }
    if (n + 1 < size) buf[n++] = (char)ch;
  }
  return false;
}

bool readBody(NetworkClient &c, uint8_t *into, size_t length, uint32_t deadline) {
  size_t got = 0;
  while (got < length && (int32_t)(millis() - deadline) < 0) {
    int n = c.read(into + got, length - got);
    if (n > 0) {
      got += (size_t)n;
      continue;
    }
    if (!c.connected()) return false;
    delay(1);
  }
  return got == length;
}

const char *reason(int status) {
  switch (status) {
    case 200: return "OK";
    case 400: return "Bad Request";
    case 403: return "Forbidden";
    case 404: return "Not Found";
    case 503: return "Service Unavailable";
    default:  return "Error";
  }
}

void head(NetworkClient &c, int status, const char *type, size_t length) {
  char text[200];
  int  n = snprintf(text, sizeof(text),
                    "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %u\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n",
                    status, reason(status), type, (unsigned)length);
  c.write((const uint8_t *)text, n);
}

void answer(NetworkClient &c, int status, const String &body = "{}") {
  head(c, status, "application/json", body.length());
  c.write((const uint8_t *)body.c_str(), body.length());
}

void pour(NetworkClient &c, const char *show, Store::Span &span, const char *type) {
  head(c, 200, type, span.to - span.from);
  while (span.from < span.to && c.connected()) {
    long n = Store::read(show, span, g_piece, sizeof(g_piece));
    if (n <= 0 || c.write(g_piece, n) != (size_t)n) break;
  }
  Store::finish();
}

void document(Outlet &c, const char *method, char *path, size_t length, int except, uint32_t deadline) {
  char *folder = strchr(path, '/');
  char *id     = folder ? strchr(folder + 1, '/') : nullptr;
  if (folder) *folder++ = '\0';
  if (id) *id++ = '\0';

  bool get = !strcmp(method, "GET");
  if (!Store::ready()) return answer(c, 503);
  if (!Shows::contains(path)) return answer(c, 404);

  Store::Span span;
  if (!folder) {
    if (!get || !Store::whole(path, span)) return answer(c, 404);
    return pour(c, path, span, "application/octet-stream");
  }

  if (!id || !Store::safe(folder) || !Store::safe(id)) return answer(c, 400);
  if (get) {
    if (!Store::locate(path, folder, id, span)) return answer(c, 404);
    return pour(c, path, span, "application/json");
  }
  if (strcmp(method, "PUT")) return answer(c, 404);

  size_t   showLength   = strlen(path);
  size_t   folderLength = strlen(folder);
  size_t   idLength     = strlen(id);
  size_t   front        = Store::DOC_HEADER + showLength + folderLength + idLength;
  uint8_t *frame        = (uint8_t *)malloc(front + length);
  if (!frame) return answer(c, 503);

  const uint8_t header[Store::DOC_HEADER] = {0x03, 0, (uint8_t)showLength, (uint8_t)folderLength, (uint8_t)idLength, (uint8_t)(length & 0xFF), (uint8_t)(length >> 8)};
  memcpy(frame, header, Store::DOC_HEADER);
  memcpy(frame + Store::DOC_HEADER, path, showLength);
  memcpy(frame + Store::DOC_HEADER + showLength, folder, folderLength);
  memcpy(frame + Store::DOC_HEADER + showLength + folderLength, id, idLength);

  bool       stored = false;
  Store::Job job    = {frame, front + length, except, false, g_stored, &stored};
  if (!readBody(c, frame + front, length, deadline) || !Store::submit(job, pdMS_TO_TICKS(5000))) {
    free(frame);
    return answer(c, 503);
  }
  xSemaphoreTake(g_stored, portMAX_DELAY);
  answer(c, stored ? 200 : 503);
}

bool hand(Outlet *client, const char *method, const char *target, const char *session, NetworkClient &c, size_t length, uint32_t deadline) {
  Visit *visit = (Visit *)malloc(sizeof(Visit));
  if (!visit) return false;
  visit->client = client;
  visit->length = length;
  snprintf(visit->method, sizeof(visit->method), "%s", method);
  snprintf(visit->target, sizeof(visit->target), "%s", target);
  snprintf(visit->session, sizeof(visit->session), "%s", session);
  visit->body[length] = '\0';

  if (readBody(c, (uint8_t *)visit->body, length, deadline) && xQueueSend(g_visits, &visit, 0) == pdTRUE) return true;
  free(visit);
  return false;
}

bool serve(Outlet *client) {
  Outlet  &c        = *client;
  uint32_t deadline = millis() + REQUEST_MS;
  char     line[REQUEST_LINE_MAX];
  if (!readLine(c, line, sizeof(line), deadline)) return false;

  char *target = strchr(line, ' ');
  if (!target) return false;
  *target++ = '\0';
  char *end = strchr(target, ' ');
  if (end) *end = '\0';

  size_t path = strcspn(target, "?");
  if (path == strlen(GLOW_WS_PATH) && !strncmp(target, GLOW_WS_PATH, path)) return hand(client, line, target, "", c, 0, deadline);

  bool isDocument = !strncmp(target, "/api/show/", 10);
  if (isDocument) deadline += DOCUMENT_MS - REQUEST_MS;

  char   header[REQUEST_LINE_MAX];
  size_t length                        = 0;
  int    except                        = -1;
  char   session[Access::TOKEN_SIZE] = "";
  for (int i = 0;; i++) {
    if (i == HEADERS_MAX || !readLine(c, header, sizeof(header), deadline)) return false;
    if (!header[0]) break;
    if (!strncasecmp(header, "Content-Length:", 15)) length = strtoul(header + 15, nullptr, 10);
    if (!strncasecmp(header, "X-Glow-Client:", 14)) except = (int)strtol(header + 14, nullptr, 10);
    if (!strncasecmp(header, "X-Glow-Session:", 15)) snprintf(session, sizeof(session), "%s", header + 15 + strspn(header + 15, " "));
  }

  if (isDocument) {
    if (length > DOCUMENT_MAX) answer(c, 400);
    else if (!Link::admits(session)) answer(c, 403);
    else document(c, line, target + 10, length, except, deadline);
    return false;
  }

  if (length > REQUEST_BODY_MAX) {
    answer(c, 400);
    return false;
  }

  return hand(client, line, target, session, c, length, deadline);
}

void server(void *) {
  int listener = socket(AF_INET6, SOCK_STREAM, 0);
  int on       = 1;
  setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));

  sockaddr_in6 at = {};
  at.sin6_family  = AF_INET6;
  at.sin6_port    = htons(GLOW_PORT);
  if (bind(listener, (sockaddr *)&at, sizeof(at)) || listen(listener, 4)) {
    Serial.println(F("http: port 80 would not open"));
    vTaskDelete(nullptr);
  }

  for (;;) {
    int fd = accept(listener, nullptr, nullptr);
    if (fd < 0) {
      delay(100);
      continue;
    }
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &on, sizeof(on));
    setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &on, sizeof(on));

    Outlet *client = new Outlet(fd, PATIENCE_MS);
    if (serve(client)) continue;
    client->stop();
    delete client;
  }
}

void info(NetworkClient &c) {
  JsonDocument doc;
  doc["id"]    = Net::id();
  doc["state"] = Net::provisioned() ? "provisioned" : "unprovisioned";
  doc["join"]  = Net::joinState();
  doc["ip"]    = Net::ip().toString();
  doc["ssid"]  = WiFi.SSID();
  String out;
  serializeJson(doc, out);
  answer(c, 200, out);

  if (Net::up() && Net::fromSetupAp(c.remoteIP())) Net::confirm();
}

void scan(NetworkClient &c) {
  if (!Net::fromSetupAp(c.remoteIP())) return answer(c, 404);

  Net::Network nets[SCAN_MAX];
  int n = Net::scan(nets, SCAN_MAX);
  if (n == Net::SCAN_FAILED) return answer(c, 503);

  JsonDocument doc;
  JsonArray    list = doc["networks"].to<JsonArray>();
  for (int i = 0; i < n; i++) {
    JsonObject o    = list.add<JsonObject>();
    o["ssid"]       = nets[i].ssid;
    o["rssi"]       = nets[i].rssi;
    o["secure"]     = nets[i].secure;
    o["enterprise"] = nets[i].enterprise;
  }
  String out;
  serializeJson(doc, out);
  answer(c, 200, out);
}

bool text(JsonDocument &doc, const char *key, size_t max, bool required, const char *&out) {
  JsonVariant value = doc[key];
  out = "";
  if (value.isNull()) return !required;
  if (!value.is<const char *>()) return false;
  out = value.as<const char *>();
  return (out[0] || !required) && strlen(out) <= max;
}

void provision(NetworkClient &c, const char *body, size_t len) {
  JsonDocument doc;
  const char  *ssid;
  const char  *user;
  const char  *password;
  if (deserializeJson(doc, body, len)) return answer(c, 400);
  if (!text(doc, "ssid", 32, true, ssid)) return answer(c, 400);
  if (!text(doc, "user", 64, false, user)) return answer(c, 400);
  if (!text(doc, "password", user[0] ? 64 : 63, false, password)) return answer(c, 400);

  answer(c, 200);
  c.stop();
  Net::provision(ssid, user, password);
}

void route(Visit &v) {
  NetworkClient &c = *v.client;

  if (!strncmp(v.target, GLOW_WS_PATH, strlen(GLOW_WS_PATH)) && strcmp(v.method, "GET")) return answer(c, 404);
  if (!strncmp(v.target, GLOW_WS_PATH, strlen(GLOW_WS_PATH))) {
    Link::adopt(v.client, v.target);
    v.client = nullptr;
    return;
  }
  v.target[strcspn(v.target, "?")] = '\0';

  bool post = !strcmp(v.method, "POST");
  bool open = !strcmp(v.target, "/api/info") || !strcmp(v.target, "/api/scan") || (!strcmp(v.target, "/api/provision") && Net::fromSetupAp(c.remoteIP()));
  if (!open && !Link::admits(v.session)) return answer(c, 403);

  if (!strcmp(v.target, "/api/info") && !strcmp(v.method, "GET")) {
    info(c);
  } else if (!strcmp(v.target, "/api/scan") && !strcmp(v.method, "GET")) {
    scan(c);
  } else if (!strcmp(v.target, "/api/provision") && post) {
    provision(c, v.body, v.length);
  } else if (!strcmp(v.target, "/api/setup") && post) {
    answer(c, 200);
    c.stop();
    Net::enterSetup();
  } else if (!strcmp(v.target, "/api/forget") && post) {
    answer(c, 200);
    c.stop();
    Net::forget();
  } else {
    answer(c, 404);
  }
}

}  // namespace

void begin() {
  g_visits = xQueueCreate(VISITS_WAITING, sizeof(Visit *));
  g_stored = xSemaphoreCreateBinary();
  xTaskCreatePinnedToCore(server, "http", SERVER_STACK, nullptr, 1, nullptr, 0);
}

void tick() {
  Visit *visit;
  while (xQueueReceive(g_visits, &visit, 0) == pdTRUE) {
    route(*visit);
    if (visit->client) {
      visit->client->stop();
      delete visit->client;
    }
    free(visit);
  }
}

}  // namespace Http
