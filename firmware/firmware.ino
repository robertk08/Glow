#include "Config.h"
#include "Creds.h"
#include "DmxBus.h"
#include "Fixture.h"
#include "Http.h"
#include "Link.h"
#include "Net.h"

static void setColour(const char *name, uint8_t r, uint8_t g, uint8_t b) {
  Fixture::setColor(r, g, b, 0);
  Fixture::set(FN_DIMMER, DIMMER_OPEN);
  Serial.println(name);
}

static void report() {
  Serial.printf("id %s  %s  %d client(s)  %dHz%s\n", Net::id(),
                Net::up() ? Net::ip().toString().c_str() : "offline",
                Link::clients(), DmxBus::refreshHz(),
                DmxBus::blackout() ? "  BLACKOUT" : "");
  Serial.printf("   %s", Net::provisioned() ? "provisioned" : "unprovisioned");
  if (Net::apUp()) Serial.printf(", \"%s\" is up", GLOW_SETUP_SSID);
  Serial.println();
}

static void run(const char *line) {
  if      (!strcmp(line, "red"))    setColour("red",   255, 0,   0);
  else if (!strcmp(line, "green"))  setColour("green", 0,   255, 0);
  else if (!strcmp(line, "blue"))   setColour("blue",  0,   0,   255);
  else if (!strcmp(line, "net"))    report();
  else if (!strcmp(line, "setup"))  Net::enterSetup();
  else if (!strcmp(line, "forget")) Net::forget();
  else Serial.println(F("type: red | green | blue | net | setup | forget"));
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

  Fixture::begin();

  Serial.printf("\nDMX on GPIO%d at %dHz, start address %d\n", DMX_TX_PIN,
                DmxBus::refreshHz(), Fixture::startAddress());

  Creds::begin();
  Net::begin();
  Link::begin();
  Http::begin();

  Serial.println(F("type: red | green | blue | net | setup | forget"));
}

void loop() {
  Net::tick();
  Http::tick();
  Link::tick();
  pollSerial();
}
