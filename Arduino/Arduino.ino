#include "Config.h"
#include "Creds.h"
#include "DmxBus.h"
#include "HomeKit.h"
#include "Http.h"
#include "Link.h"
#include "Net.h"
#include "Store.h"

static void report() {
  Serial.printf("id %s  %s  %d client(s)  %dHz\n", Net::id(),
                Net::up() ? Net::ip().toString().c_str() : "offline",
                Link::clients(), DmxBus::refreshHz());
  Serial.printf("   store %u of %u bytes\n", (unsigned)Store::used(), (unsigned)Store::capacity());
  Serial.printf("   %s", Net::provisioned() ? "provisioned" : "unprovisioned");
  for (int slot = 0; slot < Creds::SLOTS; slot++) {
    if (Creds::ssid(slot)[0]) Serial.printf(", \"%s\"", Creds::ssid(slot));
  }
  if (Net::apUp()) Serial.printf(", \"%s\" is up", GLOW_SETUP_SSID);
  Serial.println();
}

static void run(const char *line) {
  if      (!strcmp(line, "net"))    report();
  else if (!strcmp(line, "setup"))  Net::enterSetup();
  else if (!strcmp(line, "forget")) Net::forget();
  else if (!strcmp(line, "home"))   HomeKit::report();
  else if (!strcmp(line, "unpair")) HomeKit::unpair();
  else Serial.println(F("type: net | setup | forget | home | unpair"));
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

  Serial.printf("\nDMX on GPIO%d at %dHz\n", DMX_TX_PIN, DmxBus::refreshHz());

  Creds::begin();
  Store::begin();
  Net::begin();
  Link::begin();
  Http::begin();
  HomeKit::begin();

  Serial.println(F("type: net | setup | forget | home | unpair"));
}

void loop() {
  Net::tick();
  Http::tick();
  Link::tick();
  pollSerial();
}
