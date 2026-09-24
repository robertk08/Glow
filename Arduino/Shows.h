#pragma once
#include <Arduino.h>

namespace Shows {

void begin();
bool apply(const char *op, const char *id, const char *name);
bool contains(const char *id);
const char *active();
bool activeNamed(const char *name);
String message();

}  // namespace Shows
