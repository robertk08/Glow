#pragma once
#include "Config.h"

namespace DmxBus {

static const int SLOT_MIN = 1;
static const int SLOT_MAX = DMX_PACKET_SIZE - 1;

bool begin();

bool writeRange(int start, const uint8_t *values, int length);

int  refreshHz();

void pause();
void resume();

}  // namespace DmxBus
