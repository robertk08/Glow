#include "Config.h"
#include "Creds.h"
#include "DmxBus.h"
#include "HomeKit.h"
#include "Http.h"
#include "Link.h"
#include "Net.h"
#include "Shows.h"
#include "Store.h"

static void report() {
  Serial.printf("glow %s  id %s  %s  %d phone(s)  dmx %d Hz\n", GLOW_FW_VERSION, Net::id(),
                Net::up() ? Net::ip().toString().c_str() : "offline", Link::clients(), DmxBus::refreshHz());
  Serial.printf("memory %u KB free of %u KB, loop stack %u bytes spare\n", (unsigned)(ESP.getFreeHeap() / 1024),
                (unsigned)(ESP.getHeapSize() / 1024), (unsigned)uxTaskGetStackHighWaterMark(nullptr));
  Serial.printf("store %u KB of %u KB used\n", (unsigned)(Store::used() / 1024), (unsigned)(Store::capacity() / 1024));
  Serial.print(Net::provisioned() ? F("wifi stored") : F("wifi none stored"));
  for (int slot = 0; slot < Creds::SLOTS; slot++) {
    if (Creds::ssid(slot)[0]) Serial.printf("%s \"%s\"", slot ? "," : "", Creds::ssid(slot));
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
  else Serial.println(F("commands: net | setup | forget | home | unpair"));
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
  Serial.printf("\nglow %s\n", GLOW_FW_VERSION);

  if (!DmxBus::begin()) {
    Serial.println(F("dmx: the driver would not start, halting"));
    while (true) delay(1000);
  }

  Serial.printf("dmx: GPIO%d at %d Hz\n", DMX_TX_PIN, DmxBus::refreshHz());

  Creds::begin();
  Store::begin();
  Shows::begin();
  Net::begin();
  Link::begin();
  Http::begin();
  HomeKit::begin();

  Serial.println(F("commands: net | setup | forget | home | unpair"));
}

void loop() {
  Net::tick();
  Http::tick();
  Link::tick();
  pollSerial();
}
