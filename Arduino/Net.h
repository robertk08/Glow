#pragma once
#include "Config.h"
#include <IPAddress.h>

namespace Net {

void begin();
void tick();

bool        up();
bool        apUp();
bool        provisioned();
const char *id();
IPAddress   ip();

bool fromSetupAp(const IPAddress &peer);

struct Network {
  char    ssid[33];
  int32_t rssi;
  int32_t channel;
  bool    secure;
  bool    enterprise;
};

int scan(Network *out, int max);

bool provision(const char *ssid, const char *user, const char *password);

void forget();       // erases, then reboots
void enterSetup();

}  // namespace Net
