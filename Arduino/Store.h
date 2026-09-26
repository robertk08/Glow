#pragma once
#include "Config.h"

#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>

namespace Store {

static const size_t NAME_LIMIT = 40;
static const size_t DOC_HEADER = 7;

struct Job {
  uint8_t          *frame;
  size_t            length;
  int               client;
  bool              stored;
  SemaphoreHandle_t done;
  bool             *outcome;
};

struct Span {
  uint32_t from;
  uint32_t to;
  uint32_t generation;
};

bool begin();
void sweep();
bool ready();
bool safe(const char *name);

bool readList(String &text);
bool writeList(const String &text);

bool submit(const Job &job, TickType_t wait = 0);
bool settled(Job &job);
void drop(const char *show);

bool whole(const char *show, Span &span);
bool locate(const char *show, const char *folder, const char *id, Span &span);
long read(const char *show, Span &span, uint8_t *into, size_t max);
void finish();

size_t used();
size_t capacity();

}  // namespace Store
