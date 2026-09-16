#pragma once
#include "Config.h"

class NetworkClient;

namespace Link {

void begin();
void tick();
int  clients();

// Takes over a socket whose request line has been read and nothing after it:
// the library parses the remaining headers itself. The caller must not close
// the socket afterwards. False when all client slots are taken.
bool adopt(NetworkClient &tcp, const char *url);

}  // namespace Link
