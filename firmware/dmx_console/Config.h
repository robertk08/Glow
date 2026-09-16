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
