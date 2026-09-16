#pragma once
#include "Config.h"

namespace Creds {

bool begin();

bool        have();
const char *ssid();
const char *password();

bool save(const char *ssid, const char *password);
bool forget();

const char *sketchSsid();

uint8_t bumpBootCount();
void    clearBootCount();

}  // namespace Creds
