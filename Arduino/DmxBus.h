#pragma once
#include "Config.h"

namespace DmxBus {

bool begin();
bool writeRange(int start, const uint8_t *values, int length);
void setUsed(int slots);

void pause();
void resume();

}  // namespace DmxBus
