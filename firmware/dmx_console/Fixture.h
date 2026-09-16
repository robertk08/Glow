#pragma once
#include "Config.h"

namespace Fixture {

void begin();

bool set(Function fn, uint8_t value);
int  get(Function fn);

void setColor(uint8_t r, uint8_t g, uint8_t b, uint8_t w);
void lampOn();
void blackout();

int  startAddress();
int  slotFor(Function fn);

}  // namespace Fixture
