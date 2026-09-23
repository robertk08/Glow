#include "Store.h"

#include "Guard.h"

#include <LittleFS.h>

namespace Store {
namespace {

const char *SHOWS     = "/shows.json";
const char *SHOWS_DIR = "/s";
const char *UPLOAD    = "/upload.part";

bool g_ready = false;

bool safe(const char *name) {
  if (!name || !name[0]) return false;
  size_t n = 0;
  for (const char *p = name; *p; p++) {
    if (++n >= NAME_LIMIT) return false;
    bool ok = (*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
              (*p >= '0' && *p <= '9') || *p == '-' || *p == '_';
    if (!ok) return false;
  }
  return true;
}

bool ensure(const char *dir) {
  if (LittleFS.exists(dir)) return true;
  return LittleFS.mkdir(dir);
}

bool ensureParents(const char *path) {
  char dir[PATH_LIMIT];
  if (snprintf(dir, sizeof(dir), "%s", path) >= (int)sizeof(dir)) return false;

  for (char *p = dir + 1; *p; p++) {
    if (*p != '/') continue;
    *p = '\0';
    bool made = ensure(dir);
    *p = '/';
    if (!made) return false;
  }
  return true;
}

void emptyFolder(const char *dir) {
  File folder = LittleFS.open(dir);
  if (!folder) return;

  File entry = folder.openNextFile();
  while (entry) {
    char path[PATH_LIMIT];
    snprintf(path, sizeof(path), "%s", entry.path());
    entry.close();
    LittleFS.remove(path);
    entry = folder.openNextFile();
  }
  folder.close();
  LittleFS.rmdir(dir);
}

}  // namespace

bool begin() {
  g_ready = LittleFS.begin(true);
  if (!g_ready) {
    Serial.println(F("store: LittleFS unavailable - shows cannot be stored"));
    return false;
  }

  LittleFS.remove(UPLOAD);
  Serial.printf("store: %u of %u bytes used\n", (unsigned)used(), (unsigned)capacity());
  return true;
}

bool ready() { return g_ready; }

const char *showsPath() { return SHOWS; }

bool showPath(char *out, size_t size, const char *showID) {
  if (!safe(showID)) return false;
  return snprintf(out, size, "%s/%s", SHOWS_DIR, showID) < (int)size;
}

bool folderPath(char *out, size_t size, const char *showID, const char *folder) {
  if (!safe(showID) || !safe(folder)) return false;
  return snprintf(out, size, "%s/%s/%s", SHOWS_DIR, showID, folder) < (int)size;
}

bool objectPath(char *out, size_t size, const char *showID, const char *folder, const char *objID) {
  if (!safe(showID) || !safe(folder) || !safe(objID)) return false;
  return snprintf(out, size, "%s/%s/%s/%s.json", SHOWS_DIR, showID, folder, objID) < (int)size;
}

int folderNames(const char *showID, char names[][NAME_LIMIT], int max) {
  char show[PATH_LIMIT];
  if (!g_ready || !showPath(show, sizeof(show), showID)) return 0;

  File root = LittleFS.open(show);
  if (!root) return 0;

  int found = 0;
  File entry = root.openNextFile();
  while (entry && found < max) {
    if (entry.isDirectory()) {
      snprintf(names[found], NAME_LIMIT, "%s", entry.name());
      found++;
    }
    entry.close();
    entry = root.openNextFile();
  }
  root.close();
  return found;
}

File open(const char *path) {
  if (!g_ready) return File();
  return LittleFS.open(path);
}

bool write(const char *path, const uint8_t *data, size_t len) {
  if (!g_ready) return false;

  return Flash::guarded([&] {
    if (!ensureParents(path)) return false;
    File f = LittleFS.open(UPLOAD, FILE_WRITE, true);
    if (!f) return false;
    size_t written = f.write(data, len);
    f.close();
    if (written != len) {
      LittleFS.remove(UPLOAD);
      return false;
    }
    if (LittleFS.rename(UPLOAD, path)) return true;
    LittleFS.remove(path);
    return LittleFS.rename(UPLOAD, path);
  });
}

bool remove(const char *path) {
  if (!g_ready) return false;
  if (!LittleFS.exists(path)) return true;
  return Flash::guarded([&] { return LittleFS.remove(path); });
}

bool removeShow(const char *showID) {
  char show[PATH_LIMIT];
  if (!g_ready || !showPath(show, sizeof(show), showID)) return false;
  if (!LittleFS.exists(show)) return true;

  char names[FOLDER_LIMIT][NAME_LIMIT];
  int count = folderNames(showID, names, FOLDER_LIMIT);

  return Flash::guarded([&] {
    for (int i = 0; i < count; i++) {
      char dir[PATH_LIMIT];
      if (!folderPath(dir, sizeof(dir), showID, names[i])) continue;
      emptyFolder(dir);
    }
    return LittleFS.rmdir(show);
  });
}

size_t used() { return g_ready ? LittleFS.usedBytes() : 0; }

size_t capacity() { return g_ready ? LittleFS.totalBytes() : 0; }

}  // namespace Store
