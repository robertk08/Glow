#include "DmxBus.h"

#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <freertos/task.h>

namespace DmxBus {
namespace {

// The look we hold. Slot 0 is the null start code and stays zero.
uint8_t g_frame[DMX_PACKET_SIZE];

// What actually goes out this frame. Blackout and identify live here rather
// than in g_frame, so "zero the output" never destroys the look - PROTOCOL.md
// asks for exactly that distinction, and it is what lets a blackout end
// without the app having to re-send anything.
uint8_t g_wire[DMX_PACKET_SIZE];

SemaphoreHandle_t g_lock = nullptr;

volatile int      g_hz            = DMX_REFRESH_HZ;
volatile bool     g_blackout      = false;
volatile uint32_t g_identifyUntil = 0;   // millis() deadline, 0 = idle

// Held across a memcpy and nothing else, never across a send: a writer that
// had to wait 23ms for the wire would defeat the point of the task below.
struct Hold {
  Hold() { if (g_lock) xSemaphoreTake(g_lock, portMAX_DELAY); }
  ~Hold() { if (g_lock) xSemaphoreGive(g_lock); }
};

// Rounded up, not down. 1000/44 truncates to 22ms, which is less than the
// 22.7ms a 513-slot frame takes, so the task would queue frames the wire has
// no room for and the rate would end up decided by the UART instead of by us.
TickType_t periodTicks(int hz) {
  if (hz < DMX_REFRESH_HZ_MIN) hz = DMX_REFRESH_HZ_MIN;
  if (hz > DMX_REFRESH_HZ_MAX) hz = DMX_REFRESH_HZ_MAX;
  TickType_t ticks = pdMS_TO_TICKS((1000u + hz - 1) / hz);
  return ticks ? ticks : 1;
}

// True while an identify is running; *dark says whether this frame is one of
// the blanked ones. Signed subtraction so a millis() wrap is just a number.
bool identifying(uint32_t now, bool *dark) {
  *dark = false;
  uint32_t until = g_identifyUntil;
  if (!until) return false;
  if ((int32_t)(now - until) >= 0) {
    g_identifyUntil = 0;
    return false;
  }
  *dark = ((until - now) / IDENTIFY_BLINK_MS) & 1;
  return true;
}

// Re-sending is not optional: many fixtures black out after roughly a second
// of DMX silence. This is the only place that talks to the driver, and it does
// nothing that can block on the network, so the wire keeps its rate whatever
// the radio is doing - including when there is no radio at all.
void refreshTask(void *) {
  TickType_t wake = xTaskGetTickCount();

  for (;;) {
    {
      Hold hold;
      memcpy(g_wire, g_frame, DMX_PACKET_SIZE);
    }

    bool dark = false;
    bool flashing = identifying(millis(), &dark);
    bool blank = g_blackout || (flashing && dark);
    if (IDENTIFY_LED_PIN >= 0) digitalWrite(IDENTIFY_LED_PIN, dark);
    if (blank) memset(g_wire + SLOT_MIN, 0, SLOT_MAX);

    dmx_write(DMX_PORT, g_wire, DMX_PACKET_SIZE);
    dmx_send_num(DMX_PORT, DMX_PACKET_SIZE);
    dmx_wait_sent(DMX_PORT, DMX_TIMEOUT_TICK);

    xTaskDelayUntil(&wake, periodTicks(g_hz));
  }
}

}  // namespace

bool begin() {
  memset(g_frame, 0, sizeof(g_frame));           // slot 0 = null start code
  memset(g_wire, 0, sizeof(g_wire));

  g_lock = xSemaphoreCreateMutex();
  if (!g_lock) return false;

  if (IDENTIFY_LED_PIN >= 0) {
    pinMode(IDENTIFY_LED_PIN, OUTPUT);
    digitalWrite(IDENTIFY_LED_PIN, LOW);
  }

  dmx_config_t config = DMX_CONFIG_DEFAULT;
  dmx_personality_t personalities[] = {};
  if (!dmx_driver_install(DMX_PORT, &config, personalities, 0)) return false;
  if (!dmx_set_pin(DMX_PORT, DMX_TX_PIN, DMX_RX_PIN, DMX_ENABLE_PIN))
    return false;

  return xTaskCreatePinnedToCore(refreshTask, "dmx", DMX_TASK_STACK, nullptr,
                                 DMX_TASK_PRIORITY, nullptr,
                                 DMX_TASK_CORE) == pdPASS;
}

bool setSlot(int slot, uint8_t value) {
  if (slot < SLOT_MIN || slot > SLOT_MAX) return false;
  Hold hold;
  g_frame[slot] = value;
  return true;
}

int getSlot(int slot) {
  if (slot < SLOT_MIN || slot > SLOT_MAX) return -1;
  Hold hold;
  return g_frame[slot];
}

// Rejected whole rather than clamped and partly applied: half an update is a
// look nobody asked for, and the app would have no way to know it happened.
bool writeRange(int start, const uint8_t *values, int length) {
  if (!values) return false;
  if (length < 1 || length > SLOT_MAX) return false;
  if (start < SLOT_MIN || start > SLOT_MAX) return false;
  if (length > SLOT_MAX - start + 1) return false;
  Hold hold;
  memcpy(g_frame + start, values, length);
  return true;
}

void clear() {
  Hold hold;
  memset(g_frame + SLOT_MIN, 0, SLOT_MAX);
}

bool setRefreshHz(int hz) {
  if (hz < DMX_REFRESH_HZ_MIN || hz > DMX_REFRESH_HZ_MAX) return false;
  g_hz = hz;
  return true;
}

int refreshHz() { return g_hz; }

void setBlackout(bool on) { g_blackout = on; }
bool blackout() { return g_blackout; }

void identify() { g_identifyUntil = millis() + IDENTIFY_MS; }

}  // namespace DmxBus
