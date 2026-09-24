#include "HomeKit.h"

#include "Config.h"
#include "Guard.h"
#include "Link.h"
#include "Net.h"
#include "Store.h"

#include <ArduinoJson.h>
#include <HomeSpan.h>
#include <math.h>

namespace HomeKit {
namespace {

const int COLOUR_FIRST  = HEAD_ADDRESS + HEAD_DIMMER - 1;
const int COLOUR_LENGTH = HEAD_WHITE - HEAD_DIMMER + 1;

bool g_mine = false;

bool unchanged(int first, const uint8_t *values, int length) {
  uint8_t held[HEAD_CHANNELS];
  Link::source(first, held, length);
  return !memcmp(held, values, length);
}

uint8_t scaled(uint8_t level) {
  if (Link::blackout()) return 0;
  float master = Link::master();
  if (master >= 1) return level;
  if (master <= 0) return 0;
  if (level < HEAD_DIM_FROM) return level;
  return HEAD_DIM_FROM + (uint8_t)lround((level - HEAD_DIM_FROM) * master);
}

double component(double hue, double index) {
  double k = fmod(index + hue / 60.0, 6.0);
  double dip = fmin(fmin(k, 4.0 - k), 1.0);
  if (dip < 0) dip = 0;
  return 1.0 - dip;
}

double angle(uint8_t red, uint8_t green, uint8_t blue) {
  int peak = fmax(fmax(red, green), blue);
  int base = fmin(fmin(red, green), blue);
  int delta = peak - base;
  if (delta == 0) return 0;

  double hue = 0;
  if (peak == red) hue = fmod((green - blue) / (double)delta, 6.0) * 60;
  else if (peak == green) hue = ((blue - red) / (double)delta + 2) * 60;
  else hue = ((red - green) / (double)delta + 4) * 60;

  return hue < 0 ? hue + 360 : hue;
}

struct Head : Service::LightBulb {
  Characteristic::ConfiguredName label{HOMEKIT_NAME};
  Characteristic::On             power{false};
  Characteristic::Brightness     level{100};
  Characteristic::Hue            hue{0};
  Characteristic::Saturation     saturation{0};

  uint8_t known[COLOUR_LENGTH];

  Head() {
    memset(known, 0xFF, sizeof(known));
    level.setRange(1, 100, 1);
    setPrimary();
  }

  boolean update() override {
    if (!g_mine) return false;

    uint8_t values[COLOUR_LENGTH];
    double share = saturation.getNewVal<double>() / 100.0;
    double tone = hue.getNewVal<double>();

    values[HEAD_DIMMER - HEAD_DIMMER] = 0;
    if (power.getNewVal<bool>()) {
      double span = HEAD_DIM_TO - HEAD_DIM_FROM;
      values[HEAD_DIMMER - HEAD_DIMMER] =
          HEAD_DIM_FROM + (uint8_t)lround(span * level.getNewVal() / 100.0);
    }

    values[HEAD_RED - HEAD_DIMMER]   = (uint8_t)lround(255 * share * component(tone, 5));
    values[HEAD_GREEN - HEAD_DIMMER] = (uint8_t)lround(255 * share * component(tone, 3));
    values[HEAD_BLUE - HEAD_DIMMER]  = (uint8_t)lround(255 * share * component(tone, 1));
    values[HEAD_WHITE - HEAD_DIMMER] = (uint8_t)lround(255 * (1 - share));

    if (unchanged(COLOUR_FIRST, values, COLOUR_LENGTH)) return true;

    uint8_t wire[COLOUR_LENGTH];
    memcpy(wire, values, sizeof(values));
    wire[HEAD_DIMMER - HEAD_DIMMER] = scaled(values[HEAD_DIMMER - HEAD_DIMMER]);

    memcpy(known, values, sizeof(values));
    Link::apply(COLOUR_FIRST, values, wire, COLOUR_LENGTH);
    return true;
  }

  void loop() override {
    if (!g_mine) return;

    uint8_t held[COLOUR_LENGTH];
    Link::source(COLOUR_FIRST, held, COLOUR_LENGTH);
    if (!memcmp(held, known, sizeof(held))) return;
    memcpy(known, held, sizeof(held));

    uint8_t dim = held[HEAD_DIMMER - HEAD_DIMMER];
    uint8_t red = held[HEAD_RED - HEAD_DIMMER];
    uint8_t green = held[HEAD_GREEN - HEAD_DIMMER];
    uint8_t blue = held[HEAD_BLUE - HEAD_DIMMER];
    uint8_t white = held[HEAD_WHITE - HEAD_DIMMER];

    bool lit = dim >= HEAD_DIM_FROM;
    if (power.getVal<bool>() != lit) power.setVal(lit);

    if (lit) {
      int reading = 100;
      if (dim <= HEAD_DIM_TO) {
        double span = HEAD_DIM_TO - HEAD_DIM_FROM;
        reading = (int)lround((dim - HEAD_DIM_FROM) * 100 / span);
      }
      if (reading < 1) reading = 1;
      if (level.getVal() != reading) level.setVal(reading);
    }

    int peak = fmax(fmax(red, green), blue);
    double share = peak + white > 0 ? 100.0 * peak / (peak + white) : 0;
    if (fabs(saturation.getVal<double>() - share) >= 1) saturation.setVal(share);

    double tone = angle(red, green, blue);
    if (peak > 0 && fabs(hue.getVal<double>() - tone) >= 1) hue.setVal(tone);
  }
};

struct Axis : Service::WindowCovering {
  Characteristic::ConfiguredName  label;
  Characteristic::CurrentPosition current{50};
  Characteristic::TargetPosition  target{50};

  const int coarse;
  const bool inverts;
  uint8_t known[2];

  Axis(const char *name, int coarse, bool inverts)
      : label(name), coarse(coarse), inverts(inverts) {
    memset(known, 0xFF, sizeof(known));
  }

  boolean update() override {
    if (!g_mine) return false;

    double fraction = target.getNewVal() / 100.0;
    if (inverts) fraction = 1 - fraction;
    uint16_t step = (uint16_t)lround(fraction * 65535);

    uint8_t values[2] = {(uint8_t)(step >> 8), (uint8_t)(step & 0xFF)};
    current.setVal(target.getNewVal());

    if (unchanged(coarse, values, sizeof(values))) return true;

    memcpy(known, values, sizeof(values));
    Link::apply(coarse, values, values, sizeof(values));
    return true;
  }

  void loop() override {
    if (!g_mine) return;

    uint8_t held[2];
    Link::source(coarse, held, sizeof(held));
    if (!memcmp(held, known, sizeof(held))) return;
    memcpy(known, held, sizeof(held));

    double fraction = (((uint16_t)held[0] << 8) | held[1]) / 65535.0;
    if (inverts) fraction = 1 - fraction;
    int reading = (int)lround(fraction * 100);

    if (target.getVal() == reading) return;
    target.setVal(reading);
    current.setVal(reading);
  }
};

}  // namespace

void begin() {
  homeSpan.setPortNum(HOMEKIT_PORT);
  homeSpan.setHostNameSuffix("");
  homeSpan.setSerialInputDisable(true);
  homeSpan.begin(Category::Lighting, HOMEKIT_NAME, GLOW_HOSTNAME, HOMEKIT_MODEL);

  Flash::guarded([] {
    homeSpan.setPairingCode(HOMEKIT_PAIRING_CODE);
    return true;
  });

  new SpanAccessory();
  new Service::AccessoryInformation();
  new Characteristic::Identify();
  new Characteristic::Name(HOMEKIT_NAME);
  new Characteristic::Manufacturer(GLOW_NODE_NAME);
  new Characteristic::Model(HOMEKIT_MODEL);
  new Characteristic::SerialNumber(Net::id());
  new Characteristic::FirmwareRevision(GLOW_FW_VERSION);

  new Head();
  new Axis("Pan", HEAD_ADDRESS + HEAD_PAN - 1, HEAD_INVERTS_PAN);
  new Axis("Tilt", HEAD_ADDRESS + HEAD_TILT - 1, HEAD_INVERTS_TILT);

  showChanged();
  homeSpan.autoPoll(8192, 1, 0);
}

void showChanged() {
  g_mine = false;

  File file = Store::open(Store::showsPath());
  if (!file) return;

  JsonDocument doc;
  DeserializationError err = deserializeJson(doc, file);
  file.close();
  if (err) return;

  const char *active = doc["active"];
  if (!active) return;

  for (JsonObject show : doc["shows"].as<JsonArray>()) {
    const char *name = show["name"];
    const char *id = show["id"];
    if (name && id && !strcmp(name, HOMEKIT_SHOW) && !strcmp(id, active)) {
      g_mine = true;
      return;
    }
  }
}

void report() {
  homeSpan.processSerialCommand("i");
}

void unpair() {
  homeSpan.processSerialCommand("H");
}

}  // namespace HomeKit
