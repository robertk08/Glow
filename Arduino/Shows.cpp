#include "Shows.h"

#include "Store.h"

#include <ArduinoJson.h>
#include <esp_random.h>

namespace Shows {
namespace {

const size_t TITLE_MAX = 64;
const size_t LIMIT     = 64;

JsonDocument g_list;

int find(JsonDocument &list, const char *id) {
  int index = 0;
  for (JsonObject show : list["shows"].as<JsonArray>()) {
    if (!strcmp(show["id"] | "", id)) return index;
    index++;
  }
  return -1;
}

bool named(const char *name) { return name[0] && strlen(name) <= TITLE_MAX; }

bool add(JsonDocument &list, const char *id, const char *name) {
  char path[Store::PATH_LIMIT];
  if (!Store::showPath(path, sizeof(path), id) || !named(name)) return false;
  if (find(list, id) >= 0 || list["shows"].size() >= LIMIT) return false;

  JsonObject show = list["shows"].add<JsonObject>();
  show["id"]     = id;
  show["name"]   = name;
  list["active"] = id;
  return true;
}

bool save(JsonDocument &list) {
  String text;
  serializeJson(list, text);
  return Store::write(Store::showsPath(), (const uint8_t *)text.c_str(), text.length());
}

template <typename Fn>
bool change(Fn edit) {
  JsonDocument next = g_list;
  if (!edit(next) || !save(next)) return false;
  g_list = std::move(next);
  return true;
}

}  // namespace

void begin() {
  File file = Store::open(Store::showsPath());
  if (file) {
    if (deserializeJson(g_list, file)) g_list.clear();
    file.close();
  }

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

bool apply(const char *op, const char *id, const char *name) {
  if (!strcmp(op, "add")) return change([&](JsonDocument &list) { return add(list, id, name); });

  int index = find(g_list, id);
  if (index < 0) return false;

  if (!strcmp(op, "open")) {
    if (!strcmp(active(), id)) return true;
    return change([&](JsonDocument &list) {
      list["active"] = id;
      return true;
    });
  }

  if (!strcmp(op, "rename")) {
    if (!named(name)) return false;
    return change([&](JsonDocument &list) {
      list["shows"][index]["name"] = name;
      return true;
    });
  }

  if (strcmp(op, "remove") || g_list["shows"].size() < 2) return false;

  bool removed = change([&](JsonDocument &list) {
    list["shows"].remove(index);
    if (!strcmp(list["active"] | "", id)) list["active"] = list["shows"][0]["id"];
    return true;
  });
  if (removed) Store::removeShow(id);
  return removed;
}

bool contains(const char *id) { return find(g_list, id) >= 0; }

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
