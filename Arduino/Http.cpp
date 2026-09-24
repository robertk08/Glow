#include "Http.h"

#include "HomeKit.h"
#include "Link.h"
#include "Net.h"
#include "Store.h"

#include <ArduinoJson.h>
#include <WiFi.h>

namespace Http {
namespace {

NetworkServer g_server(GLOW_PORT);

const uint32_t REQUEST_MS          = 3000;
const uint32_t DOCUMENT_MS         = 8000;
const size_t   REQUEST_LINE_MAX    = 256;
const size_t   REQUEST_BODY_MAX    = 512;
const size_t   DOCUMENT_BODY_MAX   = 65535;
const int      REQUEST_HEADERS_MAX = 40;
const size_t   PACKET              = 1400;
const size_t   CHUNK_HEAD          = 6;

uint8_t      g_packet[CHUNK_HEAD + PACKET + 2];

bool readLine(NetworkClient &c, char *buf, size_t size, uint32_t deadline) {
  size_t n = 0;
  while ((int32_t)(millis() - deadline) < 0) {
    if (!c.available()) {
      if (!c.connected()) return false;
      Link::tick();
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

size_t head(int status, size_t len, bool chunked) {
  char length[40];
  if (chunked) snprintf(length, sizeof(length), "Transfer-Encoding: chunked\r\n");
  else snprintf(length, sizeof(length), "Content-Length: %u\r\n", (unsigned)len);

  return snprintf((char *)g_packet, sizeof(g_packet),
                  "HTTP/1.1 %d %s\r\n"
                  "Content-Type: application/json\r\n"
                  "%s"
                  "Cache-Control: no-store\r\n"
                  "Connection: close\r\n"
                  "\r\n",
                  status, reason(status), length);
}

void sendJson(NetworkClient &c, int status, const char *body, size_t len) {
  size_t n = head(status, len, false);
  if (n + len <= sizeof(g_packet)) {
    memcpy(g_packet + n, body, len);
    c.write(g_packet, n + len);
    return;
  }
  c.write(g_packet, n);
  c.write((const uint8_t *)body, len);
}

void sendJson(NetworkClient &c, int status, const String &body) {
  sendJson(c, status, body.c_str(), body.length());
}

void sendStatus(NetworkClient &c, int status) {
  sendJson(c, status, "{}", 2);
}

struct Chunks {
  NetworkClient *client;
  size_t         held;

  void flush() {
    if (!held) return;
    char size[CHUNK_HEAD + 1];
    snprintf(size, sizeof(size), "%04x\r\n", (unsigned)held);
    memcpy(g_packet, size, CHUNK_HEAD);
    g_packet[CHUNK_HEAD + held]     = '\r';
    g_packet[CHUNK_HEAD + held + 1] = '\n';
    client->write(g_packet, CHUNK_HEAD + held + 2);
    held = 0;
  }

  void put(const char *text) {
    size_t len = strlen(text);
    while (len) {
      size_t n = PACKET - held;
      if (n > len) n = len;
      memcpy(g_packet + CHUNK_HEAD + held, text, n);
      held += n;
      text += n;
      len -= n;
      if (held == PACKET) flush();
    }
  }

  void append(File &file) {
    while (true) {
      int n = file.read(g_packet + CHUNK_HEAD + held, PACKET - held);
      if (n <= 0) return;
      held += (size_t)n;
      if (held == PACKET) flush();
    }
  }

  void finish() {
    flush();
    client->write((const uint8_t *)"0\r\n\r\n", 5);
  }
};

void sendShow(NetworkClient &c, const char *showID) {
  char names[Store::FOLDER_LIMIT][Store::NAME_LIMIT];
  int  count = Store::folderNames(showID, names, Store::FOLDER_LIMIT);

  c.write(g_packet, head(200, 0, true));

  Chunks out = {&c, 0};
  out.put("{");

  for (int i = 0; i < count; i++) {
    if (i) out.put(",");
    out.put("\"");
    out.put(names[i]);
    out.put("\":[");

    char dir[Store::PATH_LIMIT];
    if (Store::folderPath(dir, sizeof(dir), showID, names[i])) {
      File folder = Store::open(dir);
      bool first = true;
      File entry = folder ? folder.openNextFile() : File();

      while (entry) {
        if (!entry.isDirectory()) {
          if (!first) out.put(",");
          first = false;
          out.append(entry);
        }
        entry.close();
        Link::tick();
        entry = folder.openNextFile();
      }
      if (folder) folder.close();
    }

    out.put("]");
  }

  out.put("}");
  out.finish();
}

void sendStored(NetworkClient &c, const char *path) {
  File f = Store::open(path);
  if (!f || f.isDirectory()) {
    sendStatus(c, 404);
    return;
  }

  size_t held = head(200, f.size(), false);
  while (true) {
    int n = f.read(g_packet + held, sizeof(g_packet) - held);
    if (n > 0) held += (size_t)n;
    if (held && (n <= 0 || held == sizeof(g_packet))) {
      c.write(g_packet, held);
      held = 0;
    }
    if (n <= 0) break;
  }
  f.close();
}

void info(NetworkClient &c) {
  JsonDocument doc;
  doc["id"]   = Net::id();
  doc["state"] = Net::provisioned() ? "provisioned" : "unprovisioned";
  doc["join"]  = Net::joinState();
  doc["ip"]    = Net::ip().toString();
  doc["ssid"]  = WiFi.SSID();
  String out;
  serializeJson(doc, out);
  sendJson(c, 200, out);

  if (Net::up() && Net::fromSetupAp(c.remoteIP())) Net::confirm();
}

void scan(NetworkClient &c) {
  if (!Net::fromSetupAp(c.remoteIP())) {
    sendStatus(c, 404);
    return;
  }

  Net::Network nets[SCAN_MAX];
  int n = Net::scan(nets, SCAN_MAX);
  if (n == Net::SCAN_FAILED) {
    sendStatus(c, 503);
    return;
  }

  JsonDocument doc;
  JsonArray    list = doc["networks"].to<JsonArray>();
  for (int i = 0; i < n; i++) {
    JsonObject o = list.add<JsonObject>();
    o["ssid"]       = nets[i].ssid;
    o["rssi"]       = nets[i].rssi;
    o["secure"]     = nets[i].secure;
    o["enterprise"] = nets[i].enterprise;
  }
  String out;
  serializeJson(doc, out);
  sendJson(c, 200, out);
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
  if (deserializeJson(doc, body, len)) return sendStatus(c, 400);
  if (!text(doc, "ssid", 32, true, ssid)) return sendStatus(c, 400);
  if (!text(doc, "user", 64, false, user)) return sendStatus(c, 400);
  if (!text(doc, "password", user[0] ? 64 : 63, false, password)) return sendStatus(c, 400);

  sendStatus(c, 200);
  c.stop();
  Net::provision(ssid, user, password);
}

void document(NetworkClient &c, const char *path, bool get, bool put, bool del,
              const char *body, size_t bodyLen, int except) {
  if (!Store::ready()) return sendStatus(c, 503);

  if (!strcmp(path, "/api/shows")) {
    if (get) return sendStored(c, Store::showsPath());
    if (!put) return sendStatus(c, 404);
    if (!Store::write(Store::showsPath(), (const uint8_t *)body, bodyLen)) return sendStatus(c, 503);
    sendStatus(c, 200);
    HomeKit::showChanged();
    return Link::notify("{\"t\":\"shows\"}", except);
  }

  char rest[Store::PATH_LIMIT];
  if (strncmp(path, "/api/show/", 10) || snprintf(rest, sizeof(rest), "%s", path + 10) >= (int)sizeof(rest)) return sendStatus(c, 404);

  char *folder = strchr(rest, '/');
  char *objID  = folder ? strchr(folder + 1, '/') : nullptr;
  if (folder) *folder++ = '\0';
  if (objID) *objID++ = '\0';
  char file[Store::PATH_LIMIT];

  if (!folder) {
    if (!Store::showPath(file, sizeof(file), rest)) return sendStatus(c, 400);
    if (get) return sendShow(c, rest);
    if (!del) return sendStatus(c, 404);
    if (!Store::removeShow(rest)) return sendStatus(c, 503);
    return sendStatus(c, 200);
  }

  if (!objID || !Store::objectPath(file, sizeof(file), rest, folder, objID)) return sendStatus(c, 400);
  if (get) return sendStored(c, file);
  if (!put && !del) return sendStatus(c, 404);
  if (!(put ? Store::write(file, (const uint8_t *)body, bodyLen) : Store::remove(file))) return sendStatus(c, 503);
  sendStatus(c, 200);

  char notice[224];
  snprintf(notice, sizeof(notice), "{\"t\":\"doc\",\"show\":\"%s\",\"folder\":\"%s\",\"id\":\"%s\",\"op\":\"%s\"}",
           rest, folder, objID, put ? "put" : "delete");
  Link::notify(notice, except);
}

void route(NetworkClient &c, const char *method, const char *path,
           const char *body, size_t bodyLen, int except) {
  bool get  = !strcmp(method, "GET");
  bool post = !strcmp(method, "POST");
  bool put  = !strcmp(method, "PUT");
  bool del  = !strcmp(method, "DELETE");

  if (!strncmp(path, "/api/show", 9)) {
    document(c, path, get, put, del, body, bodyLen, except);
    return;
  }

  if (!strcmp(path, "/api/info") && get) {
    info(c);
  } else if (!strcmp(path, "/api/scan") && get) {
    scan(c);
  } else if (!strcmp(path, "/api/provision") && post) {
    provision(c, body, bodyLen);
  } else if (!strcmp(path, "/api/setup") && post) {
    sendStatus(c, 200);
    c.stop();
    Net::enterSetup();
  } else if (!strcmp(path, "/api/forget") && post) {
    sendStatus(c, 200);
    c.stop();
    Net::forget();
  } else {
    sendStatus(c, 404);
  }
}

bool handle(NetworkClient &client) {
  uint32_t deadline = millis() + REQUEST_MS;
  char     line[REQUEST_LINE_MAX];
  if (!readLine(client, line, sizeof(line), deadline)) return false;

  char *target = strchr(line, ' ');
  if (!target) return false;
  *target++ = '\0';
  const char *method = line;
  char       *end    = strchr(target, ' ');
  if (end) *end = '\0';

  char  *query   = strchr(target, '?');
  size_t pathLen = query ? (size_t)(query - target) : strlen(target);
  if (pathLen == strlen(GLOW_WS_PATH) && !strncmp(target, GLOW_WS_PATH, pathLen)) {
    if (!strcmp(method, "GET") && Link::adopt(client, target)) return true;
    sendStatus(client, 503);
    return false;
  }
  if (query) *query = '\0';

  bool isDocument = !strncmp(target, "/api/show", 9);
  if (isDocument) deadline += DOCUMENT_MS - REQUEST_MS;

  char   header[REQUEST_LINE_MAX];
  size_t contentLength = 0;
  int    except        = -1;
  for (int i = 0;; i++) {
    if (i == REQUEST_HEADERS_MAX || !readLine(client, header, sizeof(header), deadline)) return false;
    if (!header[0]) break;
    if (!strncasecmp(header, "Content-Length:", 15)) contentLength = strtoul(header + 15, nullptr, 10);
    if (!strncasecmp(header, "X-Glow-Client:", 14)) except = (int)strtol(header + 14, nullptr, 10);
  }

  if (contentLength > (isDocument ? DOCUMENT_BODY_MAX : REQUEST_BODY_MAX)) {
    sendStatus(client, 400);
    return false;
  }

  char  stackBody[REQUEST_BODY_MAX + 1];
  char *body = contentLength > REQUEST_BODY_MAX ? (char *)malloc(contentLength + 1) : stackBody;
  if (!body) {
    sendStatus(client, 503);
    return false;
  }

  size_t bodyLen = 0;
  while (bodyLen < contentLength && (int32_t)(millis() - deadline) < 0) {
    int n = client.read((uint8_t *)body + bodyLen, contentLength - bodyLen);
    if (n > 0) {
      bodyLen += (size_t)n;
      continue;
    }
    if (!client.connected()) break;
    Link::tick();
    delay(1);
  }
  body[bodyLen] = '\0';

  if (bodyLen == contentLength) route(client, method, target, body, bodyLen, except);
  if (body != stackBody) free(body);
  return false;
}

}  // namespace

void begin() {
  g_server.begin();
  g_server.setNoDelay(true);   // after begin(), which resets it
  Serial.printf("http: port %u - %s and /api\n", GLOW_PORT, GLOW_WS_PATH);
}

void tick() {
  NetworkClient client = g_server.accept();
  if (client && !handle(client)) client.stop();
}

}  // namespace Http
