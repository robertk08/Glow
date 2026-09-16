/*
 *  Moving head DMX controller
 *  ---------------------------------------------------------------------------
 *  Arduino UNO R4 WiFi, onboard ESP32-S3 used standalone.
 *
 *  Comes up lit and stays lit. Type red, green or blue in the Serial Monitor
 *  to change the colour.
 *
 *  Wiring, pin choice and the fixture's channel map live in Config.h - that is
 *  the only file you should normally need to edit.
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

static void setColour(const char *name, uint8_t r, uint8_t g, uint8_t b) {
  Fixture::setColor(r, g, b, 0);
  Fixture::set(FN_DIMMER, DIMMER_OPEN);   // stay lit whatever the colour
  Serial.println(name);
}

static void run(const char *line) {
  if      (!strcmp(line, "red"))   setColour("red",   255, 0,   0);
  else if (!strcmp(line, "green")) setColour("green", 0,   255, 0);
  else if (!strcmp(line, "blue"))  setColour("blue",  0,   0,   255);
  else Serial.println(F("type: red | green | blue"));
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

  Serial.printf("\nDMX on GPIO%d, start address %d\n",
                DMX_TX_PIN, Fixture::startAddress());
  Serial.println(F("type: red | green | blue"));
}

void loop() {
  DmxBus::tick();
  pollSerial();
}
