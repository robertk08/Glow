#pragma once
#include "Config.h"

namespace DmxBus {

static const int SLOT_MIN = 1;
static const int SLOT_MAX = DMX_PACKET_SIZE - 1;

bool begin();

bool setSlot(int slot, uint8_t value);
int  getSlot(int slot);
bool writeRange(int start, const uint8_t *values, int length);
void clear();

bool setRefreshHz(int hz);
int  refreshHz();

void setBlackout(bool on);
bool blackout();

void identify();

// Bracket every flash write: an erase disables the flash cache and the esp_dmx
// ISR lives in flash. pause() can take a frame time to return; do not nest.
void pause();
void resume();

}  // namespace DmxBus
