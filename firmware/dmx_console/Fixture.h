#pragma once
//  ============================================================================
//  Fixture - channel map to meaning. Knows nothing about how bytes reach the
//  wire, so HomeKit or an app can drive the same fixture later without either
//  of them knowing that DMX exists.
//  ============================================================================
#include "Config.h"

namespace Fixture {

void begin();                             // lit: centred, white, shutter open

bool set(Function fn, uint8_t value);
int  get(Function fn);                    // -1 if the fixture lacks it

void setColor(uint8_t r, uint8_t g, uint8_t b, uint8_t w);
void lampOn();
void blackout();

int  startAddress();
int  slotFor(Function fn);                // absolute DMX slot, -1 if absent

}  // namespace Fixture
