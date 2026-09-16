#include "Net.h"

#include <ESPmDNS.h>
#include <WiFi.h>
#include <esp_mac.h>

// Compiling without credentials has to work, or a fresh clone does not build
// and the first thing this project says to a new machine is an #error. So the
// file is optional here and the complaint happens at boot, where it can be
// read, at the same 115200 as everything else.
#if __has_include("secrets.h")
#include "secrets.h"
#else
#define GLOW_SECRETS_MISSING 1
#define WIFI_SSID ""
#define WIFI_PASSWORD ""
#endif

// Must match secrets.h.example. Copying the example and forgetting to edit it
// looks exactly like a network that will not join, and costs an hour.
#define EXAMPLE_SSID "your-network"

namespace Net {
namespace {

const uint32_t COMPLAIN_MS = 30000;

bool        g_running    = false;   // credentials present, radio started
bool        g_up         = false;
const char *g_why        = nullptr; // why there is no radio, null once there is
bool        g_mdns       = false;
uint32_t    g_lastTry    = 0;
uint32_t    g_complained = 0;
char        g_id[13]     = "000000000000";

const char *unconfigured() {
#ifdef GLOW_SECRETS_MISSING
  return "secrets.h is missing";
#else
  if (!WIFI_SSID[0]) return "WIFI_SSID in secrets.h is empty";
  if (!strcmp(WIFI_SSID, EXAMPLE_SSID)) return "secrets.h is still the example";
  return nullptr;
#endif
}

void complain() {
  g_complained = millis();
  Serial.println();
  Serial.println(F("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"));
  Serial.printf("  NO WIFI: %s\n", g_why ? g_why : "no credentials");
  Serial.println(F("  Copy secrets.h.example to secrets.h, fill in"));
  Serial.println(F("  WIFI_SSID and WIFI_PASSWORD, and reflash."));
  Serial.println(F("  DMX and the console below keep working meanwhile."));
  Serial.println(F("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"));
  Serial.println();
}

// esp_read_mac() reads the fused base MAC, so it answers before WiFi.begin()
// and keeps answering with the radio off. WiFi.macAddress() does not, and the
// id has to exist even on a node that has no credentials to start a radio with.
void readIdentity() {
  uint8_t mac[6] = {0};
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  snprintf(g_id, sizeof(g_id), "%02x%02x%02x%02x%02x%02x", mac[0], mac[1],
           mac[2], mac[3], mac[4], mac[5]);
}

// Restarted on every (re)connect. The responder survives most drops but not an
// AP that vanished and came back, and a node nothing can resolve is
// indistinguishable from a node that is down.
//
// addService() prepends the underscore itself, so "glow" becomes _glow._tcp.
void announce() {
  // Only tear down a responder that was actually started. mdns_free() does not
  // say in its header what it does when nothing was ever initialised, and this
  // runs on a box that cannot be attached to a debugger.
  if (g_mdns) MDNS.end();
  g_mdns = false;

  if (!MDNS.begin(GLOW_HOSTNAME)) {
    Serial.println(F("mDNS: failed"));
    return;
  }
  g_mdns = true;

  MDNS.setInstanceName(GLOW_NODE_NAME);
  MDNS.addService(GLOW_SERVICE, "tcp", GLOW_WS_PORT);
  MDNS.addServiceTxt(GLOW_SERVICE, "tcp", "v", "1");
  // id() rather than g_id: ESPmDNS overloads on char* and const char*, and a
  // char[13] matches both.
  MDNS.addServiceTxt(GLOW_SERVICE, "tcp", "id", id());
  MDNS.addServiceTxt(GLOW_SERVICE, "tcp", "name", GLOW_NODE_NAME);
  Serial.printf("mDNS: %s.local, _%s._tcp on %u\n", GLOW_HOSTNAME, GLOW_SERVICE,
                GLOW_WS_PORT);
}

}  // namespace

bool begin() {
  readIdentity();

  g_why = unconfigured();
  if (g_why) {
    complain();
    return false;
  }

  // Credentials in NVS buy nothing here - they are compiled in - and NVS
  // writes disable the flash cache, which is the same hazard PROJECT.md flags
  // for HomeSpan pairing. The DMX ISR lives in flash. Don't write NVS.
  WiFi.persistent(false);

  // Before mode() and not after: mode() is where the station netif is created
  // and the hostname is pushed into it, so a setHostname() that comes second
  // does nothing until the next mode change and the router lists this box as
  // esp32s3-xxxxxx. glow.local still resolves either way - that is mDNS, not
  // DHCP - which is what makes the mistake so easy to keep.
  WiFi.setHostname(GLOW_HOSTNAME);
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);

  // Modem sleep parks the radio between beacons and adds up to a beacon
  // interval - often 100ms - to every inbound packet. On a fader that is
  // visible lag, and the node is mains powered, so buy the latency back.
  WiFi.setSleep(false);

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  g_lastTry = millis();
  g_running = true;
  Serial.printf("WiFi: joining \"%s\"\n", WIFI_SSID);
  return true;
}

void tick() {
  if (!g_running) {
    // Say it again periodically. This is a headless box and one line at boot
    // is easy to miss if the serial monitor was opened afterwards.
    if (millis() - g_complained >= COMPLAIN_MS) complain();
    return;
  }

  bool now = WiFi.status() == WL_CONNECTED;
  if (now != g_up) {
    g_up = now;
    if (now) {
      Serial.printf("WiFi: %s\n", WiFi.localIP().toString().c_str());
      announce();
    } else {
      Serial.println(F("WiFi: dropped"));
      g_lastTry = millis();
    }
  }

  // setAutoReconnect() handles the ordinary drop. This handles the one where
  // the AP went away entirely, came back on another channel, and the supplicant
  // is still patiently retrying the old one.
  if (!now && millis() - g_lastTry >= WIFI_RETRY_MS) {
    WiFi.disconnect();
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    g_lastTry = millis();
  }
}

bool        up() { return g_up; }
const char *id() { return g_id; }
IPAddress   ip() { return WiFi.localIP(); }

}  // namespace Net
