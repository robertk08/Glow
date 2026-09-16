#include "DmxBus.h"

namespace DmxBus {
namespace {
uint8_t g_frame[DMX_PACKET_SIZE];
}

bool begin() {
  memset(g_frame, 0, sizeof(g_frame));           // slot 0 = null start code

  dmx_config_t config = DMX_CONFIG_DEFAULT;
  dmx_personality_t personalities[] = {};
  if (!dmx_driver_install(DMX_PORT, &config, personalities, 0)) return false;
  return dmx_set_pin(DMX_PORT, DMX_TX_PIN, DMX_RX_PIN, DMX_ENABLE_PIN);
}

// A frame is 513 slots at 250kbaud 8N2, so this paces itself at about 44Hz.
// Re-sending continuously is not optional: many fixtures blackout after
// roughly a second of DMX silence.
void tick() {
  dmx_write(DMX_PORT, g_frame, DMX_PACKET_SIZE);
  dmx_send_num(DMX_PORT, DMX_PACKET_SIZE);
  dmx_wait_sent(DMX_PORT, DMX_TIMEOUT_TICK);
}

bool setSlot(int slot, uint8_t value) {
  if (slot < SLOT_MIN || slot > SLOT_MAX) return false;
  g_frame[slot] = value;
  return true;
}

int getSlot(int slot) {
  if (slot < SLOT_MIN || slot > SLOT_MAX) return -1;
  return g_frame[slot];
}

void clear() { memset(g_frame + SLOT_MIN, 0, SLOT_MAX); }

}  // namespace DmxBus
