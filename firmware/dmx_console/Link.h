#pragma once
//  ============================================================================
//  Link - the node's end of docs/PROTOCOL.md: one WebSocket server at /ws.
//
//  Binary frames are DMX and go into the universe through DmxBus, so its
//  bounds checking still applies to anything arriving off the network.
//  Text frames are JSON control messages.
//
//  Nothing in here knows what a fixture is. That is the protocol's whole
//  point - the app owns the patch and the profiles, the node owns 512 bytes -
//  and it is why Fixture is not involved on this path at all.
//  ============================================================================
#include "Config.h"

namespace Link {

void begin();
void tick();     // pumps the server; call every loop()
int  clients();

}  // namespace Link
