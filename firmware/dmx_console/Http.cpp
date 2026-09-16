#include "Http.h"

#include "Link.h"
#include "Net.h"

#include <ArduinoJson.h>
#include <WiFi.h>

namespace Http {
namespace {

NetworkServer g_server(GLOW_PORT);
bool          g_running = false;

// REQUEST_LINE_MAX and not LINE_MAX, which is a POSIX macro from limits.h.
const uint32_t REQUEST_MS          = 3000;
const size_t   REQUEST_LINE_MAX    = 256;
const size_t   REQUEST_BODY_MAX    = 512;
const int      REQUEST_HEADERS_MAX = 40;

Net::Network g_nets[SCAN_MAX];

bool readLine(NetworkClient &c, char *buf, size_t size, uint32_t deadline) {
  size_t n = 0;
  while ((int32_t)(millis() - deadline) < 0) {
    if (!c.available()) {
      if (!c.connected()) return false;
      delay(1);
      continue;
    }
    int ch = c.read();
    if (ch < 0) continue;
    if (ch == '\r') continue;
    if (ch == '\n') {
      buf[n] = '\0';
      return true;
    }
    if (n + 1 < size) buf[n++] = (char)ch;
  }
  return false;
}

const char *reason(int status) {
  switch (status) {
    case 200: return "OK";
    case 400: return "Bad Request";
    case 404: return "Not Found";
    case 405: return "Method Not Allowed";
    case 503: return "Service Unavailable";
    default:  return "Error";
  }
}

void sendJson(NetworkClient &c, int status, const char *body, size_t len) {
  char head[160];
  int n = snprintf(head, sizeof(head),
                   "HTTP/1.1 %d %s\r\n"
                   "Content-Type: application/json\r\n"
                   "Content-Length: %u\r\n"
                   "Cache-Control: no-store\r\n"
                   "Connection: close\r\n"
                   "\r\n",
                   status, reason(status), (unsigned)len);
  c.write((const uint8_t *)head, (size_t)n);
  c.write((const uint8_t *)body, len);
}

void sendJson(NetworkClient &c, int status, const String &body) {
  sendJson(c, status, body.c_str(), body.length());
}

void sendResult(NetworkClient &c, int status, bool ok, const char *error) {
  JsonDocument doc;
  doc["ok"] = ok;
  if (error) doc["error"] = error;
  String out;
  serializeJson(doc, out);
  sendJson(c, status, out);
}

void info(NetworkClient &c) {
  JsonDocument doc;
  doc["fw"]   = GLOW_FW_VERSION;
  doc["id"]   = Net::id();
  doc["name"] = GLOW_NODE_NAME;
  doc["state"] = Net::provisioned() ? "provisioned" : "unprovisioned";
  String out;
  serializeJson(doc, out);
  sendJson(c, 200, out);
}

void scan(NetworkClient &c) {
  // Setup network only: a scan blocks this loop, which also pumps the WebSocket.
  if (!Net::fromSetupAp(c.remoteIP())) {
    sendResult(c, 404, false, "not_on_setup_ap");
    return;
  }

  int n = Net::scan(g_nets, SCAN_MAX);
  if (n < 0) {
    sendResult(c, 503, false, "scan_failed");
    return;
  }

  JsonDocument doc;
  JsonArray    list = doc["networks"].to<JsonArray>();
  for (int i = 0; i < n; i++) {
    JsonObject o = list.add<JsonObject>();
    o["ssid"]    = g_nets[i].ssid;
    o["rssi"]    = g_nets[i].rssi;
    o["secure"]  = g_nets[i].secure;
    o["channel"] = g_nets[i].channel;
  }
  String out;
  serializeJson(doc, out);
  sendJson(c, 200, out);
}

void provision(NetworkClient &c, const char *body, size_t len) {
  JsonDocument doc;
  if (deserializeJson(doc, body, len)) {
    sendResult(c, 400, false, "bad_json");
    return;
  }

  JsonVariant ssidVar = doc["ssid"];
  if (!ssidVar.is<const char *>()) {
    sendResult(c, 400, false, "bad_ssid");
    return;
  }
  const char *ssid = ssidVar.as<const char *>();
  if (!ssid[0] || strlen(ssid) > 32) {
    sendResult(c, 400, false, "bad_ssid");
    return;
  }

  const char *password = "";
  JsonVariant pwVar    = doc["password"];
  if (!pwVar.isNull()) {
    if (!pwVar.is<const char *>()) {
      sendResult(c, 400, false, "bad_password");
      return;
    }
    password = pwVar.as<const char *>();
    if (strlen(password) > 63) {
      sendResult(c, 400, false, "bad_password");
      return;
    }
  }

  // Reply and close before the radio moves: joining takes this network away.
  sendResult(c, 200, true, nullptr);
  c.stop();

  if (!Net::provision(ssid, password))
    Serial.println(F("provision: refused after being accepted"));
}

void forget(NetworkClient &c) {
  sendResult(c, 200, true, nullptr);
  c.stop();
  Net::forget();   // does not return
}

void route(NetworkClient &c, const char *method, const char *path,
           const char *body, size_t bodyLen) {
  bool get  = !strcmp(method, "GET");
  bool post = !strcmp(method, "POST");

  if (!strcmp(path, "/api/info")) {
    if (get) info(c);
    else sendResult(c, 405, false, "method");
  } else if (!strcmp(path, "/api/scan")) {
    if (get) scan(c);
    else sendResult(c, 405, false, "method");
  } else if (!strcmp(path, "/api/provision")) {
    if (post) provision(c, body, bodyLen);
    else sendResult(c, 405, false, "method");
  } else if (!strcmp(path, "/api/forget")) {
    if (post) forget(c);
    else sendResult(c, 405, false, "method");
  } else {
    sendResult(c, 404, false, "not_found");
  }
}

void handle(NetworkClient &client) {
  uint32_t deadline = millis() + REQUEST_MS;
  char     line[REQUEST_LINE_MAX];

  if (!readLine(client, line, sizeof(line), deadline)) {
    client.stop();
    return;
  }

  char *sp = strchr(line, ' ');
  if (!sp) {
    client.stop();
    return;
  }
  *sp = '\0';
  const char *method = line;
  char       *target = sp + 1;
  sp = strchr(target, ' ');
  if (sp) *sp = '\0';

  // Decided on the request line alone: Link::adopt() needs the headers unread.
  char  *query   = strchr(target, '?');
  size_t pathLen = query ? (size_t)(query - target) : strlen(target);
  if (pathLen == strlen(GLOW_WS_PATH) &&
      !strncmp(target, GLOW_WS_PATH, pathLen)) {
    if (strcmp(method, "GET") != 0) {
      sendResult(client, 405, false, "method");
    } else if (!Link::adopt(client, target)) {
      sendResult(client, 503, false, "no_slot");
    } else {
      return;
    }
    client.stop();
    return;
  }
  if (query) *query = '\0';

  size_t contentLength = 0;
  bool   headersEnded  = false;
  for (int i = 0; i < REQUEST_HEADERS_MAX; i++) {
    if (!readLine(client, line, sizeof(line), deadline)) {
      client.stop();
      return;
    }
    if (!line[0]) {
      headersEnded = true;
      break;
    }
    if (!strncasecmp(line, "Content-Length:", 15))
      contentLength = strtoul(line + 15, nullptr, 10);
  }
  if (!headersEnded) {
    client.stop();
    return;
  }

  if (contentLength > REQUEST_BODY_MAX) {
    sendResult(client, 400, false, "too_large");
    client.stop();
    return;
  }

  char   body[REQUEST_BODY_MAX + 1];
  size_t bodyLen = 0;
  while (bodyLen < contentLength && (int32_t)(millis() - deadline) < 0) {
    if (!client.available()) {
      if (!client.connected()) break;
      delay(1);
      continue;
    }
    int ch = client.read();
    if (ch < 0) continue;
    body[bodyLen++] = (char)ch;
  }
  body[bodyLen] = '\0';
  if (bodyLen < contentLength) {
    client.stop();
    return;
  }

  route(client, method, target, body, bodyLen);
  client.stop();
}

}  // namespace

void begin() {
  g_server.begin();
  g_server.setNoDelay(true);   // after begin(), which resets it
  g_running = true;
  Serial.printf("http: port %u - %s and /api\n", GLOW_PORT, GLOW_WS_PATH);
}

void tick() {
  if (!g_running) return;
  NetworkClient client = g_server.accept();
  if (!client) return;
  handle(client);
}

}  // namespace Http
