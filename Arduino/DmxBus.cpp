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

volatile int g_used = DMX_MIN_SLOTS;

TaskHandle_t g_task = nullptr;

struct Hold {
  Hold() { if (g_lock) xSemaphoreTake(g_lock, portMAX_DELAY); }
  ~Hold() { if (g_lock) xSemaphoreGive(g_lock); }
};

TickType_t periodTicks(int hz) {
  TickType_t ticks = pdMS_TO_TICKS((1000u + hz - 1) / hz);
  return ticks ? ticks : 1;
}

void refreshTask(void *) {
  const TickType_t burst = periodTicks(DMX_BURST_HZ);
  const TickType_t idle  = periodTicks(DMX_REFRESH_HZ) - burst;

  for (;;) {
    int used = g_used;
    if (used < DMX_MIN_SLOTS) used = DMX_MIN_SLOTS;
    if (used > SLOT_MAX) used = SLOT_MAX;
    size_t length = (size_t)used + 1;

    {
      Hold hold;
      memcpy(g_wire, g_frame, length);
    }

    TickType_t sent = xTaskGetTickCount();

    if (xSemaphoreTake(g_wireLock, portMAX_DELAY) == pdTRUE) {
      dmx_write(DMX_PORT, g_wire, length);
      dmx_send_num(DMX_PORT, length);
      dmx_wait_sent(DMX_PORT, DMX_TIMEOUT_TICK);
      xSemaphoreGive(g_wireLock);
    }

    xTaskDelayUntil(&sent, burst);
    ulTaskNotifyTake(pdTRUE, idle);
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

  dmx_config_t config = DMX_CONFIG_DEFAULT;
  dmx_personality_t personalities[] = {};
  if (!dmx_driver_install(DMX_PORT, &config, personalities, 0)) return false;
  if (!dmx_set_pin(DMX_PORT, DMX_TX_PIN, DMX_RX_PIN, DMX_ENABLE_PIN))
    return false;

  return xTaskCreatePinnedToCore(refreshTask, "dmx", DMX_TASK_STACK, nullptr,
                                 DMX_TASK_PRIORITY, &g_task,
                                 DMX_TASK_CORE) == pdPASS;
}

bool writeRange(int start, const uint8_t *values, int length) {
  if (!values) return false;
  if (length < 1 || length > SLOT_MAX) return false;
  if (start < SLOT_MIN || start > SLOT_MAX) return false;
  if (length > SLOT_MAX - start + 1) return false;

  {
    Hold hold;
    memcpy(g_frame + start, values, length);
  }

  int top = start + length - 1;
  if (top > g_used) g_used = top;
  if (g_task) xTaskNotifyGive(g_task);
  return true;
}

int refreshHz() { return DMX_REFRESH_HZ; }

void setUsed(int slots) {
  if (slots < DMX_MIN_SLOTS) slots = DMX_MIN_SLOTS;
  if (slots > SLOT_MAX) slots = SLOT_MAX;
  g_used = slots;
}

int used() { return g_used; }

void pause() {
  if (!g_wireLock) return;
  xSemaphoreTake(g_wireLock, portMAX_DELAY);
  dmx_driver_disable(DMX_PORT);
}

void resume() {
  if (!g_wireLock) return;
  dmx_driver_enable(DMX_PORT);
  xSemaphoreGive(g_wireLock);
}

}  // namespace DmxBus
