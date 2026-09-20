#include "Http.h"

#include "Link.h"
#include "Net.h"
#include "Store.h"

#include <ArduinoJson.h>
#include <WiFi.h>

namespace Http {
namespace {

NetworkServer g_server(GLOW_PORT);
bool          g_running = false;

const uint32_t REQUEST_MS          = 3000;
const uint32_t DOCUMENT_MS         = 15000;
const size_t   REQUEST_LINE_MAX    = 256;
const size_t   REQUEST_BODY_MAX    = 512;
const size_t   DOCUMENT_BODY_MAX   = 32768;
const int      REQUEST_HEADERS_MAX = 40;
const size_t   CHUNK               = 512;

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

void sendHead(NetworkClient &c, int status, size_t len) {
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
}

void sendJson(NetworkClient &c, int status, const char *body, size_t len) {
  sendHead(c, status, len);
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

struct Emitter {
  NetworkClient *client;
  size_t         length;

  void put(const char *text, size_t len) {
    length += len;
    if (client) client->write((const uint8_t *)text, len);
  }

  void put(const char *text) { put(text, strlen(text)); }

  void append(File &file) {
    length += file.size();
    if (!client) return;

    uint8_t chunk[CHUNK];
    while (true) {
      int n = file.read(chunk, sizeof(chunk));
      if (n <= 0) break;
      client->write(chunk, (size_t)n);
      Link::tick();
    }
  }
};

void emitShow(Emitter &out, const char *showID, char names[][Store::NAME_LIMIT], int count) {
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
        entry = folder.openNextFile();
      }
      if (folder) folder.close();
    }

    out.put("]");
  }

  out.put("}");
}

void sendAssembled(NetworkClient &c, const char *showID) {
  char names[Store::FOLDER_LIMIT][Store::NAME_LIMIT];
  int  count = Store::folderNames(showID, names, Store::FOLDER_LIMIT);

  Emitter counter = {nullptr, 0};
  emitShow(counter, showID, names, count);

  sendHead(c, 200, counter.length);

  Emitter writer = {&c, 0};
  emitShow(writer, showID, names, count);
}

void sendStored(NetworkClient &c, const char *path) {
  File f = Store::open(path);
  if (!f || f.isDirectory()) {
    sendResult(c, 404, false, "not_found");
    return;
  }

  sendHead(c, 200, f.size());

  uint8_t chunk[CHUNK];
  while (true) {
    int n = f.read(chunk, sizeof(chunk));
    if (n <= 0) break;
    c.write(chunk, (size_t)n);
    Link::tick();
  }
  f.close();
}

void info(NetworkClient &c) {
  JsonDocument doc;
  doc["fw"]   = GLOW_FW_VERSION;
  doc["id"]   = Net::id();
  doc["name"] = GLOW_NODE_NAME;
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
    sendResult(c, 404, false, "not_on_setup_ap");
    return;
  }

  int n = Net::scan(g_nets, SCAN_MAX);
  if (n == Net::SCAN_FAILED) {
    sendResult(c, 503, false, "scan_failed");
    return;
  }

  JsonDocument doc;
  JsonArray    list = doc["networks"].to<JsonArray>();
  for (int i = 0; i < n; i++) {
    JsonObject o = list.add<JsonObject>();
    o["ssid"]       = g_nets[i].ssid;
    o["rssi"]       = g_nets[i].rssi;
    o["secure"]     = g_nets[i].secure;
    o["enterprise"] = g_nets[i].enterprise;
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

  const char *user    = "";
  JsonVariant userVar = doc["user"];
  if (!userVar.isNull()) {
    if (!userVar.is<const char *>()) {
      sendResult(c, 400, false, "bad_user");
      return;
    }
    user = userVar.as<const char *>();
    if (strlen(user) > 64) {
      sendResult(c, 400, false, "bad_user");
      return;
    }
  }

  const char *password = "";
  JsonVariant pwVar    = doc["password"];
  if (!pwVar.isNull()) {
    if (!pwVar.is<const char *>()) {
      sendResult(c, 400, false, "bad_password");
      return;
    }
    password = pwVar.as<const char *>();
    if (strlen(password) > (user[0] ? 64u : 63u)) {
      sendResult(c, 400, false, "bad_password");
      return;
    }
  }

  sendResult(c, 200, true, nullptr);
  c.stop();

  if (!Net::provision(ssid, user, password))
    Serial.println(F("provision: refused after being accepted"));
}

void forget(NetworkClient &c) {
  sendResult(c, 200, true, nullptr);
  c.stop();
  Net::forget();   // does not return
}

void document(NetworkClient &c, const char *path, bool get, bool put, bool del,
              const char *body, size_t bodyLen, int except) {
  if (!Store::ready()) {
    sendResult(c, 503, false, "no_store");
    return;
  }

  char notice[224];

  if (!strcmp(path, "/api/shows")) {
    if (get) {
      sendStored(c, Store::showsPath());
    } else if (put) {
      if (!Store::write(Store::showsPath(), (const uint8_t *)body, bodyLen)) {
        sendResult(c, 503, false, "write_failed");
        return;
      }
      sendResult(c, 200, true, nullptr);
      Link::notify("{\"t\":\"shows\"}", except);
    } else {
      sendResult(c, 405, false, "method");
    }
    return;
  }

  if (strncmp(path, "/api/show/", 10)) {
    sendResult(c, 404, false, "not_found");
    return;
  }

  char rest[Store::PATH_LIMIT];
  if (snprintf(rest, sizeof(rest), "%s", path + 10) >= (int)sizeof(rest)) {
    sendResult(c, 400, false, "too_long");
    return;
  }

  char       *slash  = strchr(rest, '/');
  const char *showID = rest;
  if (slash) *slash = '\0';

  char show[Store::PATH_LIMIT];
  if (!Store::showPath(show, sizeof(show), showID)) {
    sendResult(c, 400, false, "bad_show");
    return;
  }

  if (!slash) {
    if (get) {
      sendAssembled(c, showID);
    } else if (del) {
      if (!Store::removeShow(showID)) {
        sendResult(c, 503, false, "write_failed");
        return;
      }
      sendResult(c, 200, true, nullptr);
      snprintf(notice, sizeof(notice), "{\"t\":\"show\",\"id\":\"%s\",\"op\":\"delete\"}", showID);
      Link::notify(notice, except);
    } else {
      sendResult(c, 405, false, "method");
    }
    return;
  }

  char *folder   = slash + 1;
  char *objStart = strchr(folder, '/');
  if (!objStart) {
    sendResult(c, 404, false, "not_found");
    return;
  }
  *objStart = '\0';
  const char *objID = objStart + 1;

  char file[Store::PATH_LIMIT];
  if (!Store::objectPath(file, sizeof(file), showID, folder, objID)) {
    sendResult(c, 400, false, "bad_object");
    return;
  }

  if (get) {
    sendStored(c, file);
    return;
  }

  if (!put && !del) {
    sendResult(c, 405, false, "method");
    return;
  }

  bool ok = put ? Store::write(file, (const uint8_t *)body, bodyLen) : Store::remove(file);
  if (!ok) {
    sendResult(c, 503, false, "write_failed");
    return;
  }

  sendResult(c, 200, true, nullptr);
  snprintf(notice, sizeof(notice), "{\"t\":\"doc\",\"show\":\"%s\",\"folder\":\"%s\",\"id\":\"%s\",\"op\":\"%s\"}",
           showID, folder, objID, put ? "put" : "delete");
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

  if (!strcmp(path, "/api/info")) {
    if (get) info(c);
    else sendResult(c, 405, false, "method");
  } else if (!strcmp(path, "/api/scan")) {
    if (get) scan(c);
    else sendResult(c, 405, false, "method");
  } else if (!strcmp(path, "/api/provision")) {
    if (post) provision(c, body, bodyLen);
    else sendResult(c, 405, false, "method");
  } else if (!strcmp(path, "/api/setup")) {
    if (post) {
      sendResult(c, 200, true, nullptr);
      c.stop();
      Net::enterSetup();
    } else sendResult(c, 405, false, "method");
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

  bool isDocument = !strncmp(target, "/api/show", 9);
  if (isDocument) deadline += DOCUMENT_MS - REQUEST_MS;

  char   header[REQUEST_LINE_MAX];
  size_t contentLength = 0;
  int    except        = -1;
  bool   headersEnded  = false;
  for (int i = 0; i < REQUEST_HEADERS_MAX; i++) {
    if (!readLine(client, header, sizeof(header), deadline)) {
      client.stop();
      return;
    }
    if (!header[0]) {
      headersEnded = true;
      break;
    }
    if (!strncasecmp(header, "Content-Length:", 15))
      contentLength = strtoul(header + 15, nullptr, 10);
    if (!strncasecmp(header, "X-Glow-Client:", 14))
      except = (int)strtol(header + 14, nullptr, 10);
  }
  if (!headersEnded) {
    client.stop();
    return;
  }

  if (contentLength > (isDocument ? DOCUMENT_BODY_MAX : REQUEST_BODY_MAX)) {
    sendResult(client, 400, false, "too_large");
    client.stop();
    return;
  }

  char  inline_[REQUEST_BODY_MAX + 1];
  char *body = inline_;
  if (contentLength > REQUEST_BODY_MAX) {
    body = (char *)malloc(contentLength + 1);
    if (!body) {
      sendResult(client, 503, false, "no_memory");
      client.stop();
      return;
    }
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

  if (body != inline_) free(body);
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
