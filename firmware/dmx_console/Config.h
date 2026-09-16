#pragma once
//  ============================================================================
//  Config.h - the only file you need to edit for a different rig.
//  ============================================================================
#include <Arduino.h>
#include <esp_dmx.h>

// ---------------------------------------------------------------- hardware --
// Board: Arduino UNO R4 WiFi, onboard ESP32-S3 used standalone.
// RS485 module: TTL485-V2.0, auto-direction (no DE/RE pin to wire).
//
//   POWER header 3V3    ->  module VCC     (3.3V, not 5V)
//   POWER header GND    ->  module GND
//   ESP header ESP_IO42 ->  module RXD     (RXD, not TXD)
//   module TXD              left unconnected
//   module D+/A         ->  XLR pin 3      (Data+)
//   module D-/B         ->  XLR pin 2      (Data-)
//   module GND          ->  XLR pin 1      (shield)
//
// The module's pin names are from the MODULE's point of view: RXD is its DI
// input, TXD is its RO output. So the ESP32's transmit pin goes to RXD.
//
// GPIO42 and not GPIO43: GPIO43 is ESP_TXD0 and is wired to the RA4M1 through
// a level translator that holds it up. GPIO41/42 are free.
//
// The 2x3 ESP header has no 3V3 pin - module power comes from the main POWER
// header. Un-bridge ESP_DOWNLOAD<->GND after flashing or the chip stays in the
// bootloader instead of running this sketch.

static const int DMX_TX_PIN     = 42;
static const int DMX_RX_PIN     = -1;   // transmit-only
static const int DMX_ENABLE_PIN = -1;   // auto-direction module, no DE/RE pin

// Never DMX_NUM_2 - esp_dmx 4.1.0 drops the third UART's context entry and
// dmx_driver_install() dereferences NULL. Port 0 is the console UART.
static const dmx_port_t DMX_PORT = DMX_NUM_1;

// ----------------------------------------------------------------- fixture --
// Mini LED moving head, no-name, 14-channel mode, display shows "d001".
// Channel numbers are 1-based offsets from the start address. If the fixture
// turns out not to match its manual, correct this table - nothing else in the
// codebase hard-codes a channel number.

static const int FIXTURE_START_ADDRESS = 1;

enum Function : uint8_t {
  FN_PAN, FN_PAN_FINE, FN_TILT, FN_TILT_FINE, FN_XY_SPEED, FN_DIMMER,
  FN_RED, FN_GREEN, FN_BLUE, FN_WHITE, FN_COLOR_MACRO, FN_JUMP_SPEED,
  FN_MODE, FN_RESET,
  FN_COUNT
};

struct ChannelDef {
  uint8_t     channel;   // 1-based offset from start address, 0 = absent
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

// Four values that decide whether the fixture responds to DMX at all:
//   DIMMER 0-7 is off, 8-134 dims, 135-239 strobes, 240-255 is full open
//   MODE   must stay 0-7 or the fixture runs its own program and ignores DMX
//   MACRO  must stay 0-7 or colour comes from a macro instead of RGBW
//   RESET  150-200 triggers a reset, so it must never idle there
static const uint8_t DIMMER_OFF  = 0;
static const uint8_t DIMMER_OPEN = 255;
static const uint8_t MODE_MANUAL = 0;
static const uint8_t MACRO_RGBW  = 0;

// ----------------------------------------------------------------- network --
// Station mode only - the node joins the house WiFi, it never runs an AP.
//
// Credentials live in secrets.h, which is gitignored. Copy secrets.h.example
// over it and fill it in. Without it the node still boots and still drives
// DMX; it just says so at 115200 and never touches the radio. A missing
// password is not a reason for the light to go out.
//
// Port 80 is deliberate. HomeSpan's HAP server defaults to 1201, so stage 2
// moves in without a port fight.

#define GLOW_FW_VERSION "1.1.0"

// Macros and not statics: a string constant a translation unit happens not to
// use is a warning at -Wall, and most of these are used by exactly one file.
#define GLOW_NODE_NAME "Glow"    // TXT name=, and status.name
#define GLOW_HOSTNAME  "glow"    // -> glow.local
#define GLOW_SERVICE   "glow"    // -> _glow._tcp
#define GLOW_WS_PATH   "/ws"

static const uint16_t GLOW_WS_PORT = 80;

// 2.4GHz in a flat full of 2.4GHz drops out. Treat that as normal: retry
// forever, never block boot on it, never let it touch DMX timing.
static const uint32_t WIFI_RETRY_MS = 10000;

// ------------------------------------------------------------------ output --
// The universe is clocked by a task of its own (see DmxBus.cpp), so this rate
// is what the wire actually runs at no matter what the network is doing.
//
// 44Hz is the ceiling because a full 513-slot frame at 250kbaud 8N2 takes
// 22.7ms to send: ask for more and you are asking for frames the wire has no
// room for. PROTOCOL.md's 10..44 range is the same range for the same reason.
static const int DMX_REFRESH_HZ     = 40;
static const int DMX_REFRESH_HZ_MIN = 10;
static const int DMX_REFRESH_HZ_MAX = 44;

// Core 1 is where Arduino's loop() runs; the WiFi and lwIP tasks live on core
// 0 at priority 23 and would preempt a frame if this shared with them.
// Priority 5 is above loop()'s 1, so a socket read that blocks for seconds
// cannot delay a frame either.
static const int DMX_TASK_CORE     = 1;
static const int DMX_TASK_PRIORITY = 5;
static const int DMX_TASK_STACK    = 3072;

// There is no user LED on the ESP32-S3 side of an UNO R4 WiFi - the built-in
// LED and the matrix both hang off the RA4M1. So identify flashes the output
// instead: whatever is patched blinks, which answers "which box is that?" just
// as well. Wire an LED to a free GPIO and name it here and it blinks too.
static const int      IDENTIFY_LED_PIN  = -1;
static const uint32_t IDENTIFY_MS       = 1500;   // length of the whole pattern
static const uint32_t IDENTIFY_BLINK_MS = 150;    // half-period of the blink
