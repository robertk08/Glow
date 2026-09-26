#pragma once
#include "Config.h"

class Outlet;

namespace Link {

void begin();
void tick();
int  clients();

void  apply(int start, const uint8_t *source, const uint8_t *output, int length);
void  source(int start, uint8_t *out, int length);
float master();
bool  blackout();

void adopt(Outlet *tcp, const char *url);
bool admits(const char *session);
void forgetPassword();

}  // namespace Link
