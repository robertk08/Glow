#pragma once
#include <Arduino.h>
#include <esp_dmx.h>

static const int DMX_TX_PIN     = 42;   // not 43: ESP_TXD0, held up by the RA4M1
static const int DMX_RX_PIN     = -1;
static const int DMX_ENABLE_PIN = -1;

static const dmx_port_t DMX_PORT = DMX_NUM_1;

static const int FIXTURE_START_ADDRESS = 1;

enum Function : uint8_t {
  FN_PAN, FN_PAN_FINE, FN_TILT, FN_TILT_FINE, FN_XY_SPEED, FN_DIMMER,
  FN_RED, FN_GREEN, FN_BLUE, FN_WHITE, FN_COLOR_MACRO, FN_JUMP_SPEED,
  FN_MODE, FN_RESET,
  FN_COUNT
};

struct ChannelDef {
  uint8_t     channel;
  const char *name;
};

static const ChannelDef FIXTURE_PROFILE[FN_COUNT] = {
  {  1, "Pan"           },
  {  2, "Pan fine"      },
  {  3, "Tilt"          },
  {  4, "Tilt fine"     },
  {  5, "XY speed"      },
  {  6, "Dimmer/strobe" },
  {  7, "Red"           },
  {  8, "Green"         },
  {  9, "Blue"          },
  { 10, "White"         },
  { 11, "Colour macro"  },
  { 12, "Jump speed"    },
  { 13, "Mode"          },
  { 14, "Reset"         },
};

static const uint8_t DIMMER_OFF  = 0;
static const uint8_t DIMMER_OPEN = 255;
static const uint8_t MODE_MANUAL = 0;
static const uint8_t MACRO_RGBW  = 0;

#define GLOW_FW_VERSION "1.3.0"
#define GLOW_NODE_NAME  "Glow"
#define GLOW_HOSTNAME   "glow"
#define GLOW_SERVICE    "glow"
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
static const uint32_t SETUP_DONE_MS   = 60000;
static const int      SCAN_MAX        = 20;
static const uint32_t SCAN_CHANNEL_MS = 120;

static const int      SETUP_PIN        = 0;
static const uint32_t SETUP_HOLD_MS    = 3000;
static const uint8_t  RECOVERY_BOOTS   = 3;
static const uint32_t RECOVERY_BOOT_MS = 5000;

static const int DMX_REFRESH_HZ     = 40;
static const int DMX_REFRESH_HZ_MIN = 10;
static const int DMX_REFRESH_HZ_MAX = 44;

static const int DMX_TASK_CORE     = 1;
static const int DMX_TASK_PRIORITY = 5;
static const int DMX_TASK_STACK    = 3072;

