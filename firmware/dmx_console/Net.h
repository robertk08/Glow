#pragma once
//  ============================================================================
//  Net - WiFi station and mDNS. Nothing above this layer waits for either.
//
//  begin() never blocks on an association and tick() never blocks on anything,
//  because the one thing that must keep running is the wire, and the wire is
//  on its own task precisely so a network that is having a bad day cannot
//  reach it.
//  ============================================================================
#include "Config.h"
#include <IPAddress.h>

namespace Net {

bool begin();          // false if secrets.h is missing or still the example
void tick();           // state changes, reconnects, re-announce; call in loop()

bool        up();
const char *id();      // MAC as 12 lowercase hex digits: TXT id=, status.id
IPAddress   ip();

}  // namespace Net
