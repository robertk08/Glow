#pragma once
#include <Arduino.h>

namespace Shows {

enum Outcome { DONE, INVALID, LIMIT, STORAGE };

void begin();
Outcome apply(const char *op, const char *id, const char *name);
bool contains(const char *id);
const char *active();
bool activeNamed(const char *name);
String message();

}  // namespace Shows
