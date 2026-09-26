#pragma once
#include <Arduino.h>
#include <esp_dmx.h>

static const int DMX_TX_PIN     = 42;   // not 43: ESP_TXD0, held up by the RA4M1
static const int DMX_RX_PIN     = -1;
static const int DMX_ENABLE_PIN = -1;

static const dmx_port_t DMX_PORT = DMX_NUM_1;

#define GLOW_FW_VERSION "2.7.0"
#define GLOW_NODE_NAME  "Glow"
#define GLOW_HOSTNAME   "glow"
#define GLOW_WS_PATH    "/ws"

static const uint16_t GLOW_PORT = 80;

static const uint32_t WIFI_RETRY_MS = 10000;

#define GLOW_SETUP_SSID "Glow Setup"
#define GLOW_SETUP_IP   IPAddress(192, 168, 4, 1)
#define GLOW_SETUP_MASK IPAddress(255, 255, 255, 0)

static const uint32_t JOIN_TIMEOUT_MS = 20000;
static const uint32_t SETUP_AP_MS     = 5UL * 60 * 1000;
static const uint32_t SETUP_LOST_MS   = 60000;
static const uint32_t SETUP_RETRY_MS  = 60000;
static const uint32_t SETUP_DONE_MS   = 30000;
static const int      SCAN_MAX        = 20;
static const uint32_t SCAN_CHANNEL_MS = 120;
static const uint32_t CHOOSE_MS       = 4000;

static const uint8_t  RECOVERY_BOOTS   = 3;
static const uint32_t RECOVERY_BOOT_MS = 5000;

static const int DMX_REFRESH_HZ = 40;
static const int DMX_BURST_HZ   = 100;
static const int DMX_MIN_SLOTS  = 24;

static const int DMX_TASK_CORE     = 1;
static const int DMX_TASK_PRIORITY = 5;
static const int DMX_TASK_STACK    = 2048;

static const uint16_t HOMEKIT_PORT = 1201;

#define HOMEKIT_NAME          "Moving Head"
#define HOMEKIT_POSITION_NAME "Pan and Tilt"
#define HOMEKIT_MODEL         "Mini LED Moving Head"
#define HOMEKIT_SHOW          "Home"

static const int HEAD_ADDRESS = 1;

static const int HEAD_PAN           = 1;
static const int HEAD_TILT          = 3;
static const int HEAD_DIMMER        = 6;
static const int HEAD_RED           = 7;
static const int HEAD_GREEN         = 8;
static const int HEAD_BLUE          = 9;
static const int HEAD_WHITE         = 10;
static const int HEAD_CHANNELS      = 14;

static const uint8_t HEAD_DIM_FROM = 8;
static const uint8_t HEAD_DIM_TO   = 134;

static const bool HEAD_INVERTS_PAN  = true;
static const bool HEAD_INVERTS_TILT = false;
