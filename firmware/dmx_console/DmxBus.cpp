#include "DmxBus.h"

#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <freertos/task.h>

namespace DmxBus {
namespace {

uint8_t g_frame[DMX_PACKET_SIZE];
uint8_t g_wire[DMX_PACKET_SIZE];

SemaphoreHandle_t g_lock     = nullptr;
SemaphoreHandle_t g_wireLock = nullptr;

volatile int      g_hz            = DMX_REFRESH_HZ;
volatile bool     g_blackout      = false;
volatile uint32_t g_identifyUntil = 0;
volatile bool     g_resync        = false;

struct Hold {
  Hold() { if (g_lock) xSemaphoreTake(g_lock, portMAX_DELAY); }
  ~Hold() { if (g_lock) xSemaphoreGive(g_lock); }
};

TickType_t periodTicks(int hz) {
  if (hz < DMX_REFRESH_HZ_MIN) hz = DMX_REFRESH_HZ_MIN;
  if (hz > DMX_REFRESH_HZ_MAX) hz = DMX_REFRESH_HZ_MAX;
  // Rounded up: 1000/44 truncates below the 22.7ms a frame takes.
  TickType_t ticks = pdMS_TO_TICKS((1000u + hz - 1) / hz);
  return ticks ? ticks : 1;
}

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

    if (xSemaphoreTake(g_wireLock, portMAX_DELAY) == pdTRUE) {
      dmx_write(DMX_PORT, g_wire, DMX_PACKET_SIZE);
      dmx_send_num(DMX_PORT, DMX_PACKET_SIZE);
      dmx_wait_sent(DMX_PORT, DMX_TIMEOUT_TICK);
      xSemaphoreGive(g_wireLock);
    }

    // A pause leaves xTaskDelayUntil owing frames it would send back to back.
    if (g_resync) {
      g_resync = false;
      wake = xTaskGetTickCount();
    }

    xTaskDelayUntil(&wake, periodTicks(g_hz));
  }
}

}  // namespace

bool begin() {
  memset(g_frame, 0, sizeof(g_frame));
  memset(g_wire, 0, sizeof(g_wire));

  g_lock = xSemaphoreCreateMutex();
  if (!g_lock) return false;
  g_wireLock = xSemaphoreCreateMutex();
  if (!g_wireLock) return false;

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

void pause() {
  if (!g_wireLock) return;
  xSemaphoreTake(g_wireLock, portMAX_DELAY);
  dmx_driver_disable(DMX_PORT);
}

void resume() {
  if (!g_wireLock) return;
  dmx_driver_enable(DMX_PORT);
  g_resync = true;
  xSemaphoreGive(g_wireLock);
}

}  // namespace DmxBus
