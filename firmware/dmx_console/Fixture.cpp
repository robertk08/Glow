#include "Fixture.h"
#include "DmxBus.h"

namespace Fixture {
namespace {
const int g_start = FIXTURE_START_ADDRESS;

bool present(Function fn) {
  return fn < FN_COUNT && FIXTURE_PROFILE[fn].channel != 0;
}
}  // namespace

int startAddress() { return g_start; }

int slotFor(Function fn) {
  if (!present(fn)) return -1;
  int slot = g_start + FIXTURE_PROFILE[fn].channel - 1;
  return (slot >= DmxBus::SLOT_MIN && slot <= DmxBus::SLOT_MAX) ? slot : -1;
}

bool set(Function fn, uint8_t value) {
  int slot = slotFor(fn);
  return slot > 0 && DmxBus::setSlot(slot, value);
}

int get(Function fn) {
  int slot = slotFor(fn);
  return slot > 0 ? DmxBus::getSlot(slot) : -1;
}

void setColor(uint8_t r, uint8_t g, uint8_t b, uint8_t w) {
  set(FN_COLOR_MACRO, MACRO_RGBW);   // or colour comes from a macro instead
  set(FN_RED, r); set(FN_GREEN, g); set(FN_BLUE, b); set(FN_WHITE, w);
}

void lampOn() {
  set(FN_MODE,     MODE_MANUAL);     // or the fixture runs its own program
  set(FN_RESET,    0);               // must never idle in 150..200
  set(FN_XY_SPEED, 0);
  set(FN_PAN,  128);  set(FN_PAN_FINE,  0);
  set(FN_TILT, 128);  set(FN_TILT_FINE, 0);
  setColor(255, 255, 255, 255);
  set(FN_DIMMER, DIMMER_OPEN);
}

void blackout() { set(FN_DIMMER, DIMMER_OFF); }

void begin() { DmxBus::clear(); lampOn(); }

}  // namespace Fixture
