#pragma once
#include "Config.h"

class NetworkClient;

namespace Link {

void begin();
void tick();
int  clients();

void  apply(int start, const uint8_t *source, const uint8_t *output, int length);
void  source(int start, uint8_t *out, int length);
float master();
bool  blackout();

void notify(const char *json, int except);

bool adopt(NetworkClient &tcp, const char *url);
bool admits(const char *session);
void forgetPassword();

}  // namespace Link
