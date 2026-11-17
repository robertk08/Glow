#pragma once
#include <Arduino.h>

namespace Shows {

enum Outcome { DONE, INVALID, LIMIT, STORAGE };

void begin();
Outcome apply(const char *op, const char *id, const char *name, bool sendsAllChannels);
bool contains(const char *id);
const char *active();
bool activeNamed(const char *name);
bool activeSendsAllChannels();
String message();

}  // namespace Shows
