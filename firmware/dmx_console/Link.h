#pragma once
#include "Config.h"

class NetworkClient;

namespace Link {

void begin();
void tick();
int  clients();

bool adopt(NetworkClient &tcp, const char *url);

}  // namespace Link
