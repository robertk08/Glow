#pragma once
//  ============================================================================
//  DmxBus - owns the 513-byte universe and the esp_dmx driver.
//  Knows nothing about fixtures. Every slot write is bounds-checked here.
//  ============================================================================
#include "Config.h"

namespace DmxBus {

// Slot 0 is the start code; usable slots are 1..512.
static const int SLOT_MIN = 1;
static const int SLOT_MAX = DMX_PACKET_SIZE - 1;   // 512

bool begin();                            // install driver, route the pin
void tick();                             // send one frame; call every loop()

bool setSlot(int slot, uint8_t value);   // false if out of range
int  getSlot(int slot);                  // -1 if out of range
void clear();

}  // namespace DmxBus
