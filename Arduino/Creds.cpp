#include "Creds.h"
#include "Guard.h"

#include <Preferences.h>

namespace Creds {
namespace {

const char *NS         = "glow";
const char *KEY_SSID[] = {"ssid", "ssid1"};
const char *KEY_USER[] = {"user", "user1"};
const char *KEY_PASS[] = {"pass", "pass1"};
const char *KEY_BOOTS  = "boots";

Preferences g_nvs;
bool        g_open = false;

struct Network {
  char ssid[33];   // 32 + NUL, the 802.11 maximum
  char user[65];   // 64 + NUL, the EAP maximum
  char pass[65];   // 64 + NUL, the EAP maximum, one above WPA2-PSK's
};

Network g_net[SLOTS] = {};

void copyInto(char *dst, size_t size, const char *src) {
  if (!src) src = "";
  snprintf(dst, size, "%s", src);
}

bool store(int slot) {
  const Network &net = g_net[slot];

  if (!net.ssid[0]) {
    g_nvs.remove(KEY_SSID[slot]);
    g_nvs.remove(KEY_USER[slot]);
    g_nvs.remove(KEY_PASS[slot]);
    return true;
  }

  bool ssidOk = g_nvs.putString(KEY_SSID[slot], net.ssid) > 0;
  g_nvs.putString(KEY_USER[slot], net.user);
  g_nvs.putString(KEY_PASS[slot], net.pass);
  bool userOk = net.user[0] ? g_nvs.isKey(KEY_USER[slot]) : true;
  bool passOk = net.pass[0] ? g_nvs.isKey(KEY_PASS[slot]) : true;
  return ssidOk && userOk && passOk;
}

}  // namespace

bool begin() {
  g_open = g_nvs.begin(NS, false);
  if (!g_open) {
    Serial.println(F("wifi: NVS unavailable, networks cannot be stored"));
    return false;
  }

  for (int slot = 0; slot < SLOTS; slot++) {
    g_nvs.getString(KEY_SSID[slot], g_net[slot].ssid, sizeof(g_net[slot].ssid));
    g_nvs.getString(KEY_USER[slot], g_net[slot].user, sizeof(g_net[slot].user));
    g_nvs.getString(KEY_PASS[slot], g_net[slot].pass, sizeof(g_net[slot].pass));
  }

  Serial.print(have() ? F("wifi: stored") : F("wifi: no network stored"));
  for (int slot = 0; slot < SLOTS; slot++) {
    if (g_net[slot].ssid[0]) Serial.printf("%s \"%s\"", slot ? "," : "", g_net[slot].ssid);
  }
  Serial.println();
  return true;
}

bool        have()               { return g_net[0].ssid[0] != '\0'; }
const char *ssid(int slot)       { return g_net[slot].ssid; }
const char *user(int slot)       { return g_net[slot].user; }
const char *password(int slot)   { return g_net[slot].pass; }

bool save(const char *ssid, const char *user, const char *password) {
  if (!g_open || !ssid || !ssid[0]) return false;

  if (strcmp(ssid, g_net[0].ssid)) g_net[1] = g_net[0];

  copyInto(g_net[0].ssid, sizeof(g_net[0].ssid), ssid);
  copyInto(g_net[0].user, sizeof(g_net[0].user), user);
  copyInto(g_net[0].pass, sizeof(g_net[0].pass), password);

  return Flash::guarded([] { return store(0) && store(1); });
}

bool forget() {
  for (int slot = 0; slot < SLOTS; slot++) g_net[slot] = Network{};
  if (!g_open) return false;
  return Flash::guarded([] { return store(0) && store(1); });
}

uint8_t bumpBootCount() {
  if (!g_open) return 0;
  uint8_t next = g_nvs.getUChar(KEY_BOOTS, 0);
  if (next < 255) next++;
  Flash::guarded([next] { return g_nvs.putUChar(KEY_BOOTS, next) > 0; });
  return next;
}

void clearBootCount() {
  if (!g_open) return;
  if (g_nvs.getUChar(KEY_BOOTS, 0) == 0) return;
  Flash::guarded([] { return g_nvs.putUChar(KEY_BOOTS, 0) > 0; });
}

}  // namespace Creds
