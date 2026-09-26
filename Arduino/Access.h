#pragma once
#include "Config.h"

namespace Access {

static const size_t TOKEN_SIZE = 33;

void begin();

bool     guarded();
uint32_t waiting();
void     fresh(char *token);

bool verify(const char *label, const char *nonce, const char *proof);
bool replace(const char *nonce, const char *key);
void forget();

}  // namespace Access
