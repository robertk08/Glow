#include "Net.h"

#include "Access.h"
#include "Creds.h"

#include <WiFi.h>
#include <esp_eap_client.h>
#include <esp_mac.h>

namespace Net {
namespace {

struct SetupNetwork {
  bool     up;
  uint32_t until;
  bool     lost;
  bool     confirming;
};

struct Station {
  bool     started;
  bool     up;
  bool     held;
  bool     choosing;
  int      slot;
  uint32_t lastTry;
  uint32_t downSince;
};

struct Join {
  bool     active;
  bool     letGo;
  bool     failed;
  uint32_t since;
  char     ssid[33];
  char     user[65];
  char     pass[65];
};

SetupNetwork g_ap   = {};
Station      g_sta  = {};
Join         g_join = {};
bool         g_bootCleared = false;
bool         g_scanning    = false;
char         g_id[13]      = "000000000000";

bool due(uint32_t since, uint32_t ms) { return millis() - since >= ms; }

void startStation(const char *ssid, const char *user, const char *password) {
  WiFi.mode(g_ap.up ? WIFI_AP_STA : WIFI_STA);
  WiFi.setAutoReconnect(false);
  WiFi.setSleep(false);

  if (user[0]) {
    WiFi.begin(ssid, WPA2_AUTH_PEAP, user, user, password);
  } else {
    esp_wifi_sta_enterprise_disable();
    WiFi.begin(ssid, password);
  }

  g_sta.lastTry = millis();
  g_sta.started = true;
  Serial.printf("wifi: joining \"%s\"\n", ssid);
}

void startSlot(int slot) {
  g_sta.slot = slot;
  startStation(Creds::ssid(slot), Creds::user(slot), Creds::password(slot));
}

void choose() {
  WiFi.mode(g_ap.up ? WIFI_AP_STA : WIFI_STA);
  WiFi.disconnect();
  WiFi.scanDelete();
  g_scanning = false;
  g_sta.started = true;
  g_sta.lastTry = millis();
  g_sta.choosing = WiFi.scanNetworks(true, false, false, SCAN_CHANNEL_MS) != WIFI_SCAN_FAILED;
  if (!g_sta.choosing) startSlot(g_sta.slot);
}

void chosen() {
  int     found = WiFi.scanComplete();
  int     best  = -1;
  int32_t rssi  = -1000;

  for (int i = 0; i < found; i++) {
    for (int slot = 0; slot < Creds::SLOTS; slot++) {
      if (!Creds::ssid(slot)[0] || WiFi.SSID(i) != Creds::ssid(slot) || WiFi.RSSI(i) <= rssi) continue;
      best = slot;
      rssi = WiFi.RSSI(i);
    }
  }

  WiFi.scanDelete();
  g_sta.choosing = false;
  if (best >= 0) return startSlot(best);

  int next = g_sta.slot;
  for (int step = 1; step <= Creds::SLOTS; step++) {
    int slot = (g_sta.slot + step) % Creds::SLOTS;
    if (!Creds::ssid(slot)[0]) continue;
    next = slot;
    break;
  }
  Serial.println(F("wifi: no stored network in sight, trying the next one blind"));
  startSlot(next);
}

void raiseAp(uint32_t ms) {
  if (!(g_ap.up && g_ap.until == 0)) g_ap.until = ms ? millis() + ms : 0;
  if (g_ap.up) return;

  WiFi.mode(WIFI_AP_STA);
  WiFi.softAPConfig(GLOW_SETUP_IP, GLOW_SETUP_IP, GLOW_SETUP_MASK);
  if (!WiFi.softAP(GLOW_SETUP_SSID)) {
    Serial.println(F("setup: the access point would not start"));
    return;
  }
  g_ap.up = true;
  Serial.printf("setup: \"%s\" is up\n", GLOW_SETUP_SSID);
}

void lowerAp() {
  if (!g_ap.up) return;
  WiFi.softAPdisconnect(true);
  g_ap = {};
  WiFi.mode(WIFI_STA);
  Serial.printf("setup: \"%s\" is down\n", GLOW_SETUP_SSID);
}

void joined() {
  Serial.printf("wifi: %s on \"%s\" at %d dBm, %s.local\n", WiFi.localIP().toString().c_str(), WiFi.SSID().c_str(), (int)WiFi.RSSI(), GLOW_HOSTNAME);
  if (g_ap.lost && !g_join.active) lowerAp();
}

void tickJoin(bool connected) {
  if (!connected) g_join.letGo = true;

  if (connected && g_join.letGo) {
    g_join.active = false;
    g_sta.slot    = 0;
    if (Creds::save(g_join.ssid, g_join.user, g_join.pass)) Serial.printf("wifi: \"%s\" stored\n", g_join.ssid);
    else Serial.println(F("wifi: the network could not be stored"));
    g_ap.lost       = false;
    g_ap.confirming = true;
    g_ap.until      = millis() + SETUP_DONE_MS;
    return;
  }

  if (!due(g_join.since, JOIN_TIMEOUT_MS)) return;
  g_join.active = false;
  g_join.failed = true;
  Serial.printf("wifi: could not join \"%s\"\n", g_join.ssid);

  if (Creds::have()) {
    choose();
    raiseAp(SETUP_AP_MS);
  } else {
    WiFi.disconnect();
    g_sta.started = false;
    raiseAp(0);
  }
}

void tickStation(bool connected) {
  if (!g_sta.started) return;
  if (connected) {
    g_sta.held = false;
    return;
  }

  if (g_sta.choosing) {
    if (WiFi.scanComplete() == WIFI_SCAN_RUNNING && !due(g_sta.lastTry, CHOOSE_MS)) return;
    return chosen();
  }

  if (!g_ap.up && due(g_sta.downSince, SETUP_LOST_MS)) {
    Serial.println(F("setup: no stored network is in reach"));
    g_ap.lost     = true;
    g_sta.lastTry = millis();
    WiFi.disconnect();
    raiseAp(0);
  }

  if (g_ap.up && WiFi.softAPgetStationNum()) {
    if (!g_sta.held) WiFi.disconnect();
    g_sta.held = true;
    return;
  }
  g_sta.held = false;

  if (!due(g_sta.lastTry, g_ap.up ? SETUP_RETRY_MS : WIFI_RETRY_MS)) return;
  choose();
}

bool isEnterprise(wifi_auth_mode_t mode) {
  switch (mode) {
    case WIFI_AUTH_ENTERPRISE:
    case WIFI_AUTH_WPA_ENTERPRISE:
    case WIFI_AUTH_WPA3_ENTERPRISE:
    case WIFI_AUTH_WPA2_WPA3_ENTERPRISE:
    case WIFI_AUTH_WPA3_ENT_192: return true;
    default:                     return false;
  }
}

}  // namespace

void begin() {
  uint8_t mac[6] = {0};
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  snprintf(g_id, sizeof(g_id), "%02x%02x%02x%02x%02x%02x", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

  WiFi.persistent(false);
  WiFi.setHostname(GLOW_HOSTNAME);

  uint8_t boots = Creds::bumpBootCount();
  bool    asked = boots >= RECOVERY_BOOTS;
  if (asked) {
    Creds::clearBootCount();
    g_bootCleared = true;
    Serial.printf("setup: %u short boots\n", boots);
    Access::forget();
  }

  if (!Creds::have()) {
    raiseAp(0);
    return;
  }

  choose();
  g_sta.downSince = millis();
  if (asked) raiseAp(SETUP_AP_MS);
}

void tick() {
  if (!g_bootCleared && millis() >= RECOVERY_BOOT_MS) {
    g_bootCleared = true;
    Creds::clearBootCount();
  }

  bool connected = g_sta.started && WiFi.status() == WL_CONNECTED;
  if (connected != g_sta.up) {
    g_sta.up = connected;
    if (connected) {
      joined();
    } else {
      Serial.println(F("wifi: dropped, rejoining"));
      g_sta.downSince = millis();
      if (!g_join.active) startSlot(g_sta.slot);
    }
  }

  if (g_join.active) return tickJoin(connected);
  if (g_ap.up && g_ap.until && (int32_t)(millis() - g_ap.until) >= 0) lowerAp();
  tickStation(connected);
}

void confirm() {
  if (g_ap.confirming) g_ap.until = millis();
}

const char *joinState() {
  if (g_join.active) return "trying";
  return g_join.failed ? "failed" : "idle";
}

bool        up()          { return g_sta.up; }
bool        apUp()        { return g_ap.up; }
bool        provisioned() { return Creds::have(); }
const char *id()          { return g_id; }
IPAddress   ip()          { return g_sta.up ? WiFi.localIP() : WiFi.softAPIP(); }

bool fromSetupAp(const IPAddress &peer) {
  if (!g_ap.up) return false;
  IPAddress ap = WiFi.softAPIP();
  return peer[0] == ap[0] && peer[1] == ap[1] && peer[2] == ap[2];
}

int scan(Network *out, int max) {
  if (g_sta.choosing) return SCAN_RUNNING;
  int found = WiFi.scanComplete();
  if (found == WIFI_SCAN_RUNNING) return SCAN_RUNNING;

  if (found == WIFI_SCAN_FAILED) {
    bool failed = g_scanning || WiFi.scanNetworks(true, false, false, SCAN_CHANNEL_MS) == WIFI_SCAN_FAILED;
    g_scanning = !failed;
    return failed ? SCAN_FAILED : SCAN_RUNNING;
  }

  g_scanning = false;
  int n = 0;

  for (int i = 0; i < found; i++) {
    Network entry = {};
    snprintf(entry.ssid, sizeof(entry.ssid), "%s", WiFi.SSID(i).c_str());
    if (!entry.ssid[0]) continue;
    entry.rssi       = WiFi.RSSI(i);
    entry.secure     = WiFi.encryptionType(i) != WIFI_AUTH_OPEN;
    entry.enterprise = isEnterprise(WiFi.encryptionType(i));

    int same = -1;
    for (int j = 0; j < n && same < 0; j++) {
      if (!strcmp(out[j].ssid, entry.ssid)) same = j;
    }

    if (same >= 0) {
      if (entry.rssi > out[same].rssi) out[same] = entry;
    } else if (n < max) {
      out[n++] = entry;
    } else {
      int weakest = 0;
      for (int j = 1; j < n; j++) {
        if (out[j].rssi < out[weakest].rssi) weakest = j;
      }
      if (entry.rssi > out[weakest].rssi) out[weakest] = entry;
    }
  }

  WiFi.scanDelete();
  return n;
}

void provision(const char *ssid, const char *user, const char *password) {
  snprintf(g_join.ssid, sizeof(g_join.ssid), "%s", ssid);
  snprintf(g_join.user, sizeof(g_join.user), "%s", user);
  snprintf(g_join.pass, sizeof(g_join.pass), "%s", password);

  if (!g_ap.up) raiseAp(SETUP_AP_MS);

  g_join.active = true;
  g_join.letGo  = false;
  g_join.failed = false;
  g_join.since  = millis();
  WiFi.disconnect();
  startStation(g_join.ssid, g_join.user, g_join.pass);
}

void enterSetup() {
  raiseAp(SETUP_AP_MS);
}

void forget() {
  Creds::forget();
  Serial.println(F("wifi: stored networks erased, restarting"));
  Serial.flush();
  delay(200);   // let the reply's FIN leave before the radio stops
  ESP.restart();
}

}  // namespace Net
