#include "Shows.h"

#include "Store.h"

#include <ArduinoJson.h>
#include <esp_random.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>

namespace Shows {
namespace {

const size_t TITLE_MAX = 64;
const size_t COUNT_MAX = 64;

JsonDocument      g_list;
SemaphoreHandle_t g_lock = nullptr;

struct Hold {
  Hold() { xSemaphoreTake(g_lock, portMAX_DELAY); }
  ~Hold() { xSemaphoreGive(g_lock); }
};

int find(JsonDocument &list, const char *id) {
  int index = 0;
  for (JsonObject show : list["shows"].as<JsonArray>()) {
    if (!strcmp(show["id"] | "", id)) return index;
    index++;
  }
  return -1;
}

bool named(const char *name) { return name[0] && strlen(name) <= TITLE_MAX; }

Outcome add(JsonDocument &list, const char *id, const char *name) {
  if (!Store::safe(id) || !named(name) || find(list, id) >= 0) return INVALID;
  if (list["shows"].size() >= COUNT_MAX) return LIMIT;

  JsonObject show = list["shows"].add<JsonObject>();
  show["id"]     = id;
  show["name"]   = name;
  list["active"] = id;
  return DONE;
}

bool save(JsonDocument &list) {
  String text;
  serializeJson(list, text);
  return Store::writeList(text);
}

template <typename Fn>
Outcome change(Fn edit) {
  JsonDocument next = g_list;
  Outcome outcome = edit(next);
  if (outcome != DONE) return outcome;
  if (!save(next)) return STORAGE;
  Hold hold;
  g_list = std::move(next);
  return DONE;
}

}  // namespace

void begin() {
  g_lock = xSemaphoreCreateMutex();

  String text;
  if (!Store::readList(text) || deserializeJson(g_list, text)) g_list.clear();

  if (!g_list["shows"].is<JsonArray>()) g_list["shows"].to<JsonArray>();
  if (g_list["shows"].size()) {
    if (!contains(active())) g_list["active"] = g_list["shows"][0]["id"];
    return;
  }

  char id[17];
  snprintf(id, sizeof(id), "%08lx%08lx", (unsigned long)esp_random(), (unsigned long)esp_random());
  add(g_list, id, "Show 1");
  if (!save(g_list)) Serial.println(F("shows: the first show could not be stored"));
}

Outcome apply(const char *op, const char *id, const char *name) {
  if (!strcmp(op, "add")) return change([&](JsonDocument &list) { return add(list, id, name); });

  int index = find(g_list, id);
  if (index < 0) return INVALID;

  if (!strcmp(op, "open")) {
    if (!strcmp(active(), id)) return DONE;
    return change([&](JsonDocument &list) {
      list["active"] = id;
      return DONE;
    });
  }

  if (!strcmp(op, "rename")) {
    if (!named(name)) return INVALID;
    return change([&](JsonDocument &list) {
      list["shows"][index]["name"] = name;
      return DONE;
    });
  }

  if (strcmp(op, "remove") || g_list["shows"].size() < 2) return INVALID;

  Outcome removed = change([&](JsonDocument &list) {
    list["shows"].remove(index);
    if (!strcmp(list["active"] | "", id)) list["active"] = list["shows"][0]["id"];
    return DONE;
  });
  if (removed == DONE) Store::drop(id);
  return removed;
}

bool contains(const char *id) {
  Hold hold;
  return find(g_list, id) >= 0;
}

const char *active() { return g_list["active"] | ""; }

bool activeNamed(const char *name) {
  int index = find(g_list, active());
  return index >= 0 && !strcmp(g_list["shows"][index]["name"] | "", name);
}

String message() {
  JsonDocument out;
  out["t"]      = "shows";
  out["active"] = g_list["active"];
  out["shows"]  = g_list["shows"];

  String text;
  serializeJson(out, text);
  return text;
}

}  // namespace Shows
