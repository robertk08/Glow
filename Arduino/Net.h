#pragma once
#include "Config.h"
#include <IPAddress.h>

namespace Net {

void begin();
void tick();

bool        up();
bool        apUp();
bool        provisioned();
const char *joinState();
const char *id();
IPAddress   ip();

bool fromSetupAp(const IPAddress &peer);

struct Network {
  char    ssid[33];
  int32_t rssi;
  bool    secure;
  bool    enterprise;
};

static const int SCAN_RUNNING = -1;
static const int SCAN_FAILED  = -2;

int scan(Network *out, int max);

bool provision(const char *ssid, const char *user, const char *password);

void forget();       // erases, then reboots
void enterSetup();

}  // namespace Net
