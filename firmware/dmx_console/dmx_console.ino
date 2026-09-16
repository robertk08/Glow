/*
 *  Moving head DMX controller
 *  ---------------------------------------------------------------------------
 *  Arduino UNO R4 WiFi, onboard ESP32-S3 used standalone.
 *
 *  Comes up lit and stays lit, joins the WiFi, and serves the iOS app at
 *  ws://glow.local/ws. Type red, green or blue in the Serial Monitor to change
 *  the colour, or net for where the node thinks it is.
 *
 *  The universe is clocked onto the wire by a task inside DmxBus, so the light
 *  does not care whether the network, the app or this loop is having a bad day.
 *
 *  Wiring, pin choice and the fixture's channel map live in Config.h - that is
 *  the only file you should normally need to edit. WiFi credentials live in
 *  secrets.h, which is gitignored: copy secrets.h.example over it.
 *
 *  Board settings (all four required):
 *    Board            ESP32S3 Dev Module
 *    USB CDC On Boot  Enabled      - or Serial never reaches the USB port
 *    Flash Size       8MB
 *    Partition Scheme Huge APP (3MB No OTA/1MB SPIFFS)
 *
 *  Serial Monitor: 115200, line ending "New Line".
 */

#include "Config.h"
#include "DmxBus.h"
#include "Fixture.h"
#include "Link.h"
#include "Net.h"

// The console drives the rig through Fixture, the app drives it through Link,
// and both land in the same 512 bytes - see the writers note in DmxBus.h.
// Typing a colour while the app is streaming lasts exactly one frame. That is
// expected here, and it is the same arbitration question HomeKit raises next.
static void setColour(const char *name, uint8_t r, uint8_t g, uint8_t b) {
  Fixture::setColor(r, g, b, 0);
  Fixture::set(FN_DIMMER, DIMMER_OPEN);   // stay lit whatever the colour
  Serial.println(name);
}

static void report() {
  Serial.printf("id %s  %s  %d client(s)  %dHz%s\n", Net::id(),
                Net::up() ? Net::ip().toString().c_str() : "offline",
                Link::clients(), DmxBus::refreshHz(),
                DmxBus::blackout() ? "  BLACKOUT" : "");
}

static void run(const char *line) {
  if      (!strcmp(line, "red"))   setColour("red",   255, 0,   0);
  else if (!strcmp(line, "green")) setColour("green", 0,   255, 0);
  else if (!strcmp(line, "blue"))  setColour("blue",  0,   0,   255);
  else if (!strcmp(line, "net"))   report();
  else Serial.println(F("type: red | green | blue | net"));
}

static void pollSerial() {
  static char   line[16];
  static size_t len = 0;

  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\r') continue;
    if (c != '\n') {
      if (len < sizeof(line) - 1) line[len++] = c;
      continue;
    }
    line[len] = '\0';
    len = 0;
    if (line[0]) run(line);
  }
}

void setup() {
  Serial.begin(115200);
  unsigned long t0 = millis();
  while (!Serial && millis() - t0 < 3000) delay(10);

  if (!DmxBus::begin()) {
    Serial.println(F("FATAL: could not start the DMX driver."));
    while (true) delay(1000);
  }

  Fixture::begin();          // centred, white, shutter open - lit from boot

  Serial.printf("\nDMX on GPIO%d at %dHz, start address %d\n", DMX_TX_PIN,
                DmxBus::refreshHz(), Fixture::startAddress());

  // Networking is optional on purpose. No credentials, or an access point that
  // never comes back, must not be a reason for the rig to stop working: the
  // DMX task is already running by here and keeps running either way.
  if (Net::begin()) Link::begin();

  Serial.println(F("type: red | green | blue | net"));
}

void loop() {
  Net::tick();
  Link::tick();
  pollSerial();
}
