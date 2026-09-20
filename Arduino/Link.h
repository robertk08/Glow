#pragma once
#include "Config.h"

class NetworkClient;

namespace Link {

void begin();
void tick();
int  clients();

void notify(const char *json, int except);

bool adopt(NetworkClient &tcp, const char *url);

}  // namespace Link
