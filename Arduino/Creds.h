#pragma once
#include "Config.h"

namespace Creds {

static const int SLOTS = 2;

bool begin();

bool        have();
const char *ssid(int slot);
const char *user(int slot);
const char *password(int slot);

bool save(const char *ssid, const char *user, const char *password);
bool forget();

bool own();
bool keepOwn(bool on);

uint8_t bumpBootCount();
void    clearBootCount();

}  // namespace Creds
