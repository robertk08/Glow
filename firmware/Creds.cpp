#include "Creds.h"
#include "DmxBus.h"

#include <Preferences.h>

#if __has_include("secrets.h")
#include "secrets.h"
#else
#define WIFI_SSID ""
#define WIFI_PASSWORD ""
#endif

#define EXAMPLE_SSID "your-network"

namespace Creds {
namespace {

const char *NS        = "glow";
const char *KEY_SSID  = "ssid";
const char *KEY_PASS  = "pass";
const char *KEY_BOOTS = "boots";

Preferences g_nvs;
bool        g_open = false;

char g_ssid[33] = "";   // 32 + NUL, the 802.11 maximum
char g_pass[64] = "";   // 63 + NUL, the WPA2-PSK maximum

const char *sketch() {
  if (!WIFI_SSID[0]) return nullptr;
  if (!strcmp(WIFI_SSID, EXAMPLE_SSID)) return nullptr;
  return WIFI_SSID;
}

template <typename Fn>
bool guarded(Fn write) {
  DmxBus::pause();
  bool ok = write();
  DmxBus::resume();
  return ok;
}

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
  g_nvs.getString(KEY_PASS, g_pass, sizeof(g_pass));

  if (g_ssid[0]) {
    Serial.printf("creds: \"%s\" from NVS\n", g_ssid);
  } else if (sketch()) {
    copyInto(g_ssid, sizeof(g_ssid), sketch());
    copyInto(g_pass, sizeof(g_pass), WIFI_PASSWORD);
    Serial.printf("creds: \"%s\" from secrets.h\n", g_ssid);
  } else {
    Serial.println(F("creds: none"));
  }
  return true;
}

bool        have()       { return g_ssid[0] != '\0'; }
const char *ssid()       { return g_ssid; }
const char *password()   { return g_pass; }
const char *sketchSsid() { return sketch(); }

bool save(const char *ssid, const char *password) {
  if (!g_open || !ssid || !ssid[0]) return false;

  copyInto(g_ssid, sizeof(g_ssid), ssid);
  copyInto(g_pass, sizeof(g_pass), password);

  return guarded([] {
    bool ssidOk = g_nvs.putString(KEY_SSID, g_ssid) > 0;
    g_nvs.putString(KEY_PASS, g_pass);
    bool passOk = g_pass[0] ? g_nvs.isKey(KEY_PASS) : true;
    return ssidOk ? passOk : false;
  });
}

bool forget() {
  g_ssid[0] = '\0';
  g_pass[0] = '\0';
  if (!g_open) return false;
  return guarded([] {
    g_nvs.remove(KEY_SSID);
    g_nvs.remove(KEY_PASS);
    return true;
  });
}

uint8_t bumpBootCount() {
  if (!g_open) return 0;
  uint8_t next = g_nvs.getUChar(KEY_BOOTS, 0);
  if (next < 255) next++;
  guarded([next] { return g_nvs.putUChar(KEY_BOOTS, next) > 0; });
  return next;
}

void clearBootCount() {
  if (!g_open) return;
  if (g_nvs.getUChar(KEY_BOOTS, 0) == 0) return;
  guarded([] { return g_nvs.putUChar(KEY_BOOTS, 0) > 0; });
}

}  // namespace Creds
