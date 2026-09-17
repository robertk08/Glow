#include "Net.h"

#include "Creds.h"

#include <ESPmDNS.h>
#include <WiFi.h>
#include <esp_eap_client.h>
#include <esp_mac.h>

namespace Net {
namespace {

const uint32_t COMPLAIN_MS = 30000;

bool     g_sta        = false;
bool     g_up         = false;
bool     g_ap         = false;
uint32_t g_apUntil    = 0;   // 0 = no expiry
bool     g_mdns       = false;
uint32_t g_lastTry    = 0;
uint32_t g_complained = 0;
char     g_id[13]     = "000000000000";

bool     g_trying    = false;
uint32_t g_joinStart = 0;
bool     g_tryLetGo  = false;
char     g_trySsid[33] = "";
char     g_tryUser[65] = "";
char     g_tryPass[65] = "";

bool g_bootCleared = false;
bool g_scanning    = false;

bool     g_apLost    = false;
uint32_t g_downSince = 0;
bool     g_joinFailed = false;

void readIdentity() {
  uint8_t mac[6] = {0};
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  snprintf(g_id, sizeof(g_id), "%02x%02x%02x%02x%02x%02x", mac[0], mac[1],
           mac[2], mac[3], mac[4], mac[5]);
}

void complain() {
  g_complained = millis();
  Serial.printf("no wifi: join \"%s\" and use the app\n", GLOW_SETUP_SSID);
}

void announce() {
  if (g_mdns) MDNS.end();
  g_mdns = false;

  if (!MDNS.begin(GLOW_HOSTNAME)) {
    Serial.println(F("mDNS: failed"));
    return;
  }
  g_mdns = true;

  MDNS.setInstanceName(GLOW_NODE_NAME);
  MDNS.addService(GLOW_SERVICE, "tcp", GLOW_PORT);
  MDNS.addServiceTxt(GLOW_SERVICE, "tcp", "v", "1");
  MDNS.addServiceTxt(GLOW_SERVICE, "tcp", "id", id());
  MDNS.addServiceTxt(GLOW_SERVICE, "tcp", "name", GLOW_NODE_NAME);
  Serial.printf("mDNS: %s.local, _%s._tcp on %u\n", GLOW_HOSTNAME, GLOW_SERVICE,
                GLOW_PORT);
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

void startStation(const char *ssid, const char *user, const char *password) {
  WiFi.mode(g_ap ? WIFI_AP_STA : WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.setSleep(false);

  if (user && user[0]) {
    WiFi.begin(ssid, WPA2_AUTH_PEAP, user, user, password);
  } else {
    esp_wifi_sta_enterprise_disable();
    WiFi.begin(ssid, password);
  }

  g_lastTry = millis();
  g_sta     = true;
  Serial.printf("WiFi: joining \"%s\"%s\n", ssid,
                user && user[0] ? " as an enterprise network" : "");
}

void raiseAp(uint32_t ms) {
  if (!(g_ap && g_apUntil == 0)) g_apUntil = ms ? millis() + ms : 0;
  if (g_ap) return;

  WiFi.mode(WIFI_AP_STA);
  WiFi.softAPConfig(GLOW_SETUP_IP, GLOW_SETUP_IP, GLOW_SETUP_MASK);
  if (!WiFi.softAP(GLOW_SETUP_SSID)) {
    Serial.println(F("setup: the access point would not start"));
    return;
  }
  g_ap = true;
  Serial.printf("setup: \"%s\" is up on %s\n", GLOW_SETUP_SSID,
                WiFi.softAPIP().toString().c_str());
}

void lowerAp() {
  if (!g_ap) return;
  WiFi.softAPdisconnect(true);
  g_ap      = false;
  g_apUntil = 0;
  WiFi.mode(WIFI_STA);
  Serial.printf("setup: \"%s\" is down\n", GLOW_SETUP_SSID);
}

void pollSetupPin() {
  if (SETUP_PIN < 0) return;

  static bool     seenHigh  = false;
  static uint32_t downSince = 0;

  if (digitalRead(SETUP_PIN) != LOW) {
    seenHigh  = true;
    downSince = 0;
    return;
  }
  if (!seenHigh) return;
  if (!downSince) {
    downSince = millis();
    return;
  }
  if (millis() - downSince < SETUP_HOLD_MS) return;

  downSince = 0;
  seenHigh  = false;
  Serial.println(F("setup: held low"));
  enterSetup();
}

}  // namespace

void begin() {
  readIdentity();

  WiFi.persistent(false);

  WiFi.setHostname(GLOW_HOSTNAME);

  if (SETUP_PIN >= 0) pinMode(SETUP_PIN, INPUT_PULLUP);

  uint8_t boots = Creds::bumpBootCount();
  bool    asked = boots >= RECOVERY_BOOTS;
  if (asked) {
    Creds::clearBootCount();
    g_bootCleared = true;
    Serial.printf("setup: %u short boots\n", boots);
  }

  if (Creds::have()) {
    startStation(Creds::ssid(), Creds::user(), Creds::password());
    g_downSince = millis();
    if (asked) raiseAp(SETUP_AP_MS);
  } else {
    raiseAp(0);
    complain();
  }
}

void tick() {
  pollSetupPin();

  if (!g_bootCleared && millis() >= RECOVERY_BOOT_MS) {
    g_bootCleared = true;
    Creds::clearBootCount();
  }

  bool now = g_sta && WiFi.status() == WL_CONNECTED;
  if (now != g_up) {
    g_up = now;
    if (now) {
      Serial.printf("WiFi: %s\n", WiFi.localIP().toString().c_str());
      announce();
      if (g_apLost) {
        g_apLost = false;
        lowerAp();
      }
    } else {
      Serial.println(F("WiFi: dropped"));
      g_lastTry   = millis();
      g_downSince = millis();
    }
  }

  if (g_trying) {
    if (!now) g_tryLetGo = true;

    if (now && g_tryLetGo) {
      g_trying = false;
      if (!Creds::save(g_trySsid, g_tryUser, g_tryPass))
        Serial.println(F("creds: NVS write failed"));
      else
        Serial.printf("creds: \"%s\" stored\n", g_trySsid);
      lowerAp();

    } else if (millis() - g_joinStart >= JOIN_TIMEOUT_MS) {
      g_trying     = false;
      g_joinFailed = true;
      Serial.printf("WiFi: could not join \"%s\"\n", g_trySsid);
      if (Creds::have()) {
        startStation(Creds::ssid(), Creds::user(), Creds::password());
        raiseAp(SETUP_AP_MS);
      } else {
        WiFi.disconnect();
        g_sta = false;
        raiseAp(0);
      }
    }
    return;
  }

  if (g_ap && g_apUntil && (int32_t)(millis() - g_apUntil) >= 0) lowerAp();

  if (!g_sta) {
    if (millis() - g_complained >= COMPLAIN_MS) complain();
    return;
  }

  if (!now && !g_ap && millis() - g_downSince >= SETUP_LOST_MS) {
    Serial.printf("setup: \"%s\" is out of reach\n", Creds::ssid());
    g_apLost = true;
    raiseAp(0);
  }

  if (!now && millis() - g_lastTry >= WIFI_RETRY_MS) {
    WiFi.disconnect();
    startStation(Creds::ssid(), Creds::user(), Creds::password());
  }
}

const char *joinState() {
  if (g_trying) return "trying";
  return g_joinFailed ? "failed" : "idle";
}

bool        up()          { return g_up; }
bool        apUp()        { return g_ap; }
bool        provisioned() { return Creds::have(); }
const char *id()          { return g_id; }
IPAddress   ip()          { return g_up ? WiFi.localIP() : WiFi.softAPIP(); }

bool fromSetupAp(const IPAddress &peer) {
  if (!g_ap) return false;
  IPAddress ap = WiFi.softAPIP();
  return peer[0] == ap[0] && peer[1] == ap[1] && peer[2] == ap[2];
}

int scan(Network *out, int max) {
  if (!out || max <= 0) return SCAN_FAILED;

  int found = WiFi.scanComplete();
  if (found == WIFI_SCAN_RUNNING) return SCAN_RUNNING;

  if (found == WIFI_SCAN_FAILED) {
    if (g_scanning) {
      g_scanning = false;
      Serial.println(F("scan: failed"));
      return SCAN_FAILED;
    }
    if (WiFi.scanNetworks(true, false, false, SCAN_CHANNEL_MS) == WIFI_SCAN_FAILED) {
      Serial.println(F("scan: would not start"));
      return SCAN_FAILED;
    }
    g_scanning = true;
    return SCAN_RUNNING;
  }

  g_scanning = false;

  int n = 0;
  for (int i = 0; i < found; i++) {
    String ssid = WiFi.SSID(i);
    if (!ssid.length()) continue;

    int32_t rssi = WiFi.RSSI(i);

    int dup = -1;
    for (int j = 0; j < n; j++) {
      if (!strcmp(out[j].ssid, ssid.c_str())) {
        dup = j;
        break;
      }
    }
    if (dup >= 0) {
      if (rssi > out[dup].rssi) {
        out[dup].rssi       = rssi;
        out[dup].secure     = WiFi.encryptionType(i) != WIFI_AUTH_OPEN;
        out[dup].enterprise = isEnterprise(WiFi.encryptionType(i));
      }
      continue;
    }

    Network entry;
    snprintf(entry.ssid, sizeof(entry.ssid), "%s", ssid.c_str());
    entry.rssi       = rssi;
    entry.secure     = WiFi.encryptionType(i) != WIFI_AUTH_OPEN;
    entry.enterprise = isEnterprise(WiFi.encryptionType(i));

    if (n < max) {
      out[n++] = entry;
      continue;
    }
    int weakest = 0;
    for (int j = 1; j < n; j++)
      if (out[j].rssi < out[weakest].rssi) weakest = j;
    if (entry.rssi > out[weakest].rssi) out[weakest] = entry;
  }

  for (int i = 1; i < n; i++) {
    Network key = out[i];
    int     j   = i - 1;
    while (j >= 0 && out[j].rssi < key.rssi) {
      out[j + 1] = out[j];
      j--;
    }
    out[j + 1] = key;
  }

  WiFi.scanDelete();
  return n;
}

bool provision(const char *ssid, const char *user, const char *password) {
  if (!ssid || !ssid[0]) return false;
  if (strlen(ssid) > 32) return false;
  if (user && strlen(user) > 64) return false;

  size_t passMax = user && user[0] ? 64 : 63;
  if (password && strlen(password) > passMax) return false;

  snprintf(g_trySsid, sizeof(g_trySsid), "%s", ssid);
  snprintf(g_tryUser, sizeof(g_tryUser), "%s", user ? user : "");
  snprintf(g_tryPass, sizeof(g_tryPass), "%s", password ? password : "");

  if (!g_ap) raiseAp(SETUP_AP_MS);

  g_trying     = true;
  g_tryLetGo   = false;
  g_joinFailed = false;
  g_joinStart  = millis();
  WiFi.disconnect();
  startStation(g_trySsid, g_tryUser, g_tryPass);
  return true;
}

void enterSetup() {
  raiseAp(SETUP_AP_MS);
}

void forget() {
  Creds::forget();
  Serial.println(F("creds: erased"));
  if (Creds::sketchSsid())
    Serial.printf("creds: secrets.h will rejoin \"%s\" after the reboot\n",
                  Creds::sketchSsid());
  Serial.flush();
  delay(200);   // let the reply's FIN leave before the radio stops
  ESP.restart();
}

}  // namespace Net
