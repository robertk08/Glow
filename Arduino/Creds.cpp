#include "Creds.h"
#include "Guard.h"

#include <Preferences.h>

namespace Creds {
namespace {

const char *NS        = "glow";
const char *KEY_SSID  = "ssid";
const char *KEY_USER  = "user";
const char *KEY_PASS  = "pass";
const char *KEY_BOOTS = "boots";

Preferences g_nvs;
bool        g_open = false;

char g_ssid[33] = "";   // 32 + NUL, the 802.11 maximum
char g_user[65] = "";   // 64 + NUL, the EAP maximum
char g_pass[65] = "";   // 64 + NUL, the EAP maximum, one above WPA2-PSK's

void copyInto(char *dst, size_t size, const char *src) {
  if (!src) src = "";
  snprintf(dst, size, "%s", src);
}

}  // namespace

bool begin() {
  g_open = g_nvs.begin(NS, false);
  if (!g_open) {
    Serial.println(F("NVS: unavailable - credentials cannot be stored"));
    return false;
  }

  g_nvs.getString(KEY_SSID, g_ssid, sizeof(g_ssid));
  g_nvs.getString(KEY_USER, g_user, sizeof(g_user));
  g_nvs.getString(KEY_PASS, g_pass, sizeof(g_pass));

  if (g_ssid[0]) {
    Serial.printf("creds: \"%s\" from NVS\n", g_ssid);
  } else {
    Serial.println(F("creds: none"));
  }
  return true;
}

bool        have()       { return g_ssid[0] != '\0'; }
const char *ssid()       { return g_ssid; }
const char *user()       { return g_user; }
const char *password()   { return g_pass; }

bool save(const char *ssid, const char *user, const char *password) {
  if (!g_open || !ssid || !ssid[0]) return false;

  copyInto(g_ssid, sizeof(g_ssid), ssid);
  copyInto(g_user, sizeof(g_user), user);
  copyInto(g_pass, sizeof(g_pass), password);

  return Flash::guarded([] {
    bool ssidOk = g_nvs.putString(KEY_SSID, g_ssid) > 0;
    g_nvs.putString(KEY_USER, g_user);
    g_nvs.putString(KEY_PASS, g_pass);
    bool userOk = g_user[0] ? g_nvs.isKey(KEY_USER) : true;
    bool passOk = g_pass[0] ? g_nvs.isKey(KEY_PASS) : true;
    return ssidOk && userOk && passOk;
  });
}

bool forget() {
  g_ssid[0] = '\0';
  g_user[0] = '\0';
  g_pass[0] = '\0';
  if (!g_open) return false;
  return Flash::guarded([] {
    g_nvs.remove(KEY_SSID);
    g_nvs.remove(KEY_USER);
    g_nvs.remove(KEY_PASS);
    return true;
  });
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
