#pragma once
#include "Config.h"

#include <FS.h>

namespace Store {

static const size_t PATH_LIMIT   = 128;
static const size_t NAME_LIMIT   = 40;
static const int    FOLDER_LIMIT = 16;

bool begin();
bool ready();

const char *showsPath();
bool showPath(char *out, size_t size, const char *showID);
bool folderPath(char *out, size_t size, const char *showID, const char *folder);
bool objectPath(char *out, size_t size, const char *showID, const char *folder, const char *objID);

int folderNames(const char *showID, char names[][NAME_LIMIT], int max);

File open(const char *path);
bool write(const char *path, const uint8_t *data, size_t len);
bool remove(const char *path);
bool removeShow(const char *showID);

size_t used();
size_t capacity();

}  // namespace Store
