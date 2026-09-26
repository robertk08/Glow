#include "Store.h"

#include "Guard.h"
#include "Shows.h"

#include <LittleFS.h>
#include <algorithm>
#include <dirent.h>
#include <fcntl.h>
#include <freertos/queue.h>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace Store {
namespace {

const char    *ROOT         = "/littlefs";
const char    *LIST         = "/littlefs/shows.json";
const char    *LIST_SPARE   = "/littlefs/shows.json.tmp";
const size_t   PATH_LIMIT   = 64;
const uint8_t  PUT          = 0;
const uint8_t  ERASE        = 1;
const uint8_t  DROP         = 2;
const size_t   HEAD         = 5;
const uint32_t REVIEW_FROM  = 32768;
const uint32_t REVIEW_EVERY = 16384;
const uint32_t MEASURE_MS   = 500;
const int      JOBS_WAITING = 8;
const int      KEEPER_STACK = 4096;
const size_t   PIECE        = 1024;

bool              g_ready      = false;
volatile size_t   g_used       = 0;
volatile uint32_t g_generation = 0;
int               g_readers    = 0;
SemaphoreHandle_t g_lock       = nullptr;
QueueHandle_t     g_jobs       = nullptr;
QueueHandle_t     g_settled    = nullptr;
uint8_t           g_piece[PIECE];

struct Hold {
  Hold() { xSemaphoreTake(g_lock, portMAX_DELAY); }
  ~Hold() { xSemaphoreGive(g_lock); }
};

struct Record {
  uint8_t  op;
  uint32_t at;
  uint32_t body;
  uint32_t next;
  char     folder[NAME_LIMIT];
  char     id[NAME_LIMIT];
};

struct Entry {
  uint64_t key;
  uint32_t at;
  uint32_t length;
  bool     put;
};

bool path(char *out, const char *show, const char *suffix) {
  return safe(show) && snprintf(out, PATH_LIMIT, "%s/%s%s", ROOT, show, suffix) < (int)PATH_LIMIT;
}

uint64_t hash(uint64_t h, const char *text) {
  for (const char *p = text; *p; p++) h = (h ^ (uint8_t)*p) * 1099511628211ULL;
  return h;
}

uint64_t key(const Record &r) {
  return hash(hash(hash(1469598103934665603ULL, r.folder), "/"), r.id);
}

uint32_t sizeOf(int fd) {
  struct stat st;
  return fstat(fd, &st) ? 0 : (uint32_t)st.st_size;
}

bool record(int fd, uint32_t at, uint32_t size, Record &r) {
  uint8_t head[HEAD];
  if (at + HEAD > size || ::pread(fd, head, HEAD, at) != (ssize_t)HEAD) return false;

  size_t folderLength = head[1];
  size_t idLength     = head[2];
  if (head[0] > ERASE || folderLength >= NAME_LIMIT || idLength >= NAME_LIMIT) return false;

  r.op   = head[0];
  r.at   = at;
  r.body = at + HEAD + folderLength + idLength;
  r.next = r.body + (head[3] | (head[4] << 8));
  if (r.next > size) return false;
  if (::pread(fd, r.folder, folderLength, at + HEAD) != (ssize_t)folderLength) return false;
  if (::pread(fd, r.id, idLength, at + HEAD + folderLength) != (ssize_t)idLength) return false;

  r.folder[folderLength] = '\0';
  r.id[idLength]         = '\0';
  return true;
}

size_t showLength(const Job &job) { return job.frame[2]; }

bool sameShow(const Job &a, const Job &b) {
  return b.frame[1] != DROP && showLength(a) == showLength(b) && !memcmp(a.frame + DOC_HEADER, b.frame + DOC_HEADER, showLength(a));
}

bool append(const char *file, Job *jobs, int count, uint32_t &before, uint32_t &after) {
  Hold hold;
  return Flash::guarded([&] {
    int fd = ::open(file, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return false;
    before = sizeOf(fd);
    after  = before;

    bool written = true;
    for (int i = 0; i < count && written; i++) {
      const uint8_t *p          = jobs[i].frame;
      uint8_t        head[HEAD] = {p[1], p[3], p[4], p[5], p[6]};
      size_t         skip       = DOC_HEADER + showLength(jobs[i]);
      size_t         length     = jobs[i].length - skip;
      written = ::write(fd, head, HEAD) == (ssize_t)HEAD && ::write(fd, p + skip, length) == (ssize_t)length;
      after += HEAD + length;
    }
    if (!written) ftruncate(fd, before);
    return ::close(fd) == 0 && written;
  });
}

bool review(const char *show, bool always) {
  char file[PATH_LIMIT];
  char spare[PATH_LIMIT];
  if (!path(file, show, "") || !path(spare, show, ".tmp")) return false;

  Hold hold;
  if (!always && g_readers) return false;
  int from = ::open(file, O_RDONLY);
  if (from < 0) return false;
  uint32_t size = sizeOf(from);

  std::vector<Entry> entries;
  Record r;
  for (uint32_t at = 0; at < size && record(from, at, size, r); at = r.next) {
    entries.push_back({key(r), r.at, r.next - r.at, r.op == PUT});
  }

  std::sort(entries.begin(), entries.end(), [](const Entry &a, const Entry &b) { return a.key != b.key ? a.key < b.key : a.at < b.at; });

  std::vector<Entry> kept;
  uint32_t           holding = 0;
  for (size_t i = 0; i < entries.size(); i++) {
    if ((i + 1 < entries.size() && entries[i + 1].key == entries[i].key) || !entries[i].put) continue;
    kept.push_back(entries[i]);
    holding += entries[i].length;
  }
  std::vector<Entry>().swap(entries);

  if (!always && holding * 2 > size) {
    ::close(from);
    return false;
  }

  std::sort(kept.begin(), kept.end(), [](const Entry &a, const Entry &b) { return a.at < b.at; });

  int  to     = ::open(spare, O_WRONLY | O_CREAT | O_TRUNC, 0644);
  bool copied = to >= 0;
  for (const Entry &entry : kept) {
    for (uint32_t done = 0; copied && done < entry.length;) {
      size_t n = std::min(PIECE, (size_t)(entry.length - done));
      copied   = ::pread(from, g_piece, n, entry.at + done) == (ssize_t)n && Flash::guarded([&] { return ::write(to, g_piece, n) == (ssize_t)n; });
      done += n;
    }
  }
  ::close(from);

  if (to >= 0) copied = Flash::guarded([&] { return ::close(to) == 0; }) && copied;
  if (copied) copied = Flash::guarded([&] { return ::rename(spare, file) == 0; });
  if (!copied) Flash::guarded([&] { return ::unlink(spare) == 0; });
  if (copied) g_generation++;
  return copied;
}

void perform(Job *jobs, int count) {
  char show[NAME_LIMIT];
  memcpy(show, jobs[0].frame + DOC_HEADER, showLength(jobs[0]));
  show[showLength(jobs[0])] = '\0';

  char file[PATH_LIMIT];
  bool named = path(file, show, "");

  if (jobs[0].frame[1] == DROP) {
    if (named) {
      Hold hold;
      Flash::guarded([&] { return ::unlink(file) == 0; });
      g_generation++;
    }
    free(jobs[0].frame);
    return;
  }

  uint32_t before = 0;
  uint32_t after  = 0;
  bool     listed = named && Shows::contains(show);
  bool     stored = listed && append(file, jobs, count, before, after);
  if (listed && !stored && review(show, true)) stored = append(file, jobs, count, before, after);

  for (int i = 0; i < count; i++) {
    jobs[i].stored = stored;
    if (jobs[i].done) {
      *jobs[i].outcome = stored;
      xSemaphoreGive(jobs[i].done);
    }
    xQueueSend(g_settled, &jobs[i], portMAX_DELAY);
  }

  if (stored && after >= REVIEW_FROM && before / REVIEW_EVERY != after / REVIEW_EVERY) review(show, false);
}

void keeper(void *) {
  Job  jobs[JOBS_WAITING];
  bool changed = true;
  for (;;) {
    if (xQueueReceive(g_jobs, &jobs[0], changed ? pdMS_TO_TICKS(MEASURE_MS) : portMAX_DELAY) != pdTRUE) {
      g_used  = LittleFS.usedBytes();
      changed = false;
      continue;
    }

    int count = 1;
    while (count < JOBS_WAITING && jobs[0].frame[1] != DROP && xQueuePeek(g_jobs, &jobs[count], 0) == pdTRUE && sameShow(jobs[0], jobs[count])) {
      xQueueReceive(g_jobs, &jobs[count], 0);
      count++;
    }
    perform(jobs, count);
    changed = true;
  }
}

void erase(const String &at) {
  DIR *dir = opendir(at.c_str());
  if (!dir) {
    Flash::guarded([&] { return ::unlink(at.c_str()) == 0; });
    return;
  }

  std::vector<String> inside;
  while (dirent *entry = readdir(dir)) {
    if (strcmp(entry->d_name, ".") && strcmp(entry->d_name, "..")) inside.push_back(at + "/" + entry->d_name);
  }
  closedir(dir);

  for (const String &item : inside) erase(item);
  Flash::guarded([&] { return ::rmdir(at.c_str()) == 0; });
}

}  // namespace

bool begin() {
  g_lock    = xSemaphoreCreateMutex();
  g_jobs    = xQueueCreate(JOBS_WAITING, sizeof(Job));
  g_settled = xQueueCreate(JOBS_WAITING * 2, sizeof(Job));
  g_ready   = g_lock && g_jobs && g_settled && LittleFS.begin(true) &&
            xTaskCreatePinnedToCore(keeper, "store", KEEPER_STACK, nullptr, 1, nullptr, 0) == pdPASS;
  if (!g_ready) Serial.println(F("store: LittleFS unavailable, shows cannot be stored"));
  return g_ready;
}

void sweep() {
  if (!g_ready) return;

  std::vector<String> strays;
  if (DIR *root = opendir(ROOT)) {
    while (dirent *entry = readdir(root)) {
      if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..") || !strcmp(entry->d_name, "shows.json")) continue;
      if (entry->d_type == DT_REG && Shows::contains(entry->d_name)) continue;
      strays.push_back(String(ROOT) + "/" + entry->d_name);
    }
    closedir(root);
  }

  for (const String &stray : strays) erase(stray);
  g_used = LittleFS.usedBytes();
  Serial.printf("store: %u KB of %u KB used\n", (unsigned)(g_used / 1024), (unsigned)(capacity() / 1024));
}

bool ready() { return g_ready; }

bool safe(const char *name) {
  if (!name || !name[0]) return false;
  size_t n = 0;
  for (const char *p = name; *p; p++) {
    if (++n >= NAME_LIMIT) return false;
    bool ok = (*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') || (*p >= '0' && *p <= '9') || *p == '-' || *p == '_';
    if (!ok) return false;
  }
  return true;
}

bool readList(String &text) {
  text = "";
  if (!g_ready) return false;

  Hold hold;
  int fd = ::open(LIST, O_RDONLY);
  if (fd < 0) return false;
  ssize_t n;
  while ((n = ::read(fd, g_piece, PIECE)) > 0) text.concat((const char *)g_piece, n);
  ::close(fd);
  return n == 0;
}

bool writeList(const String &text) {
  if (!g_ready) return false;

  Hold hold;
  return Flash::guarded([&] {
    int fd = ::open(LIST_SPARE, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return false;
    bool written = ::write(fd, text.c_str(), text.length()) == (ssize_t)text.length();
    return ::close(fd) == 0 && written && ::rename(LIST_SPARE, LIST) == 0;
  });
}

bool submit(const Job &job, TickType_t wait) {
  return g_ready && xQueueSend(g_jobs, &job, wait) == pdTRUE;
}

bool settled(Job &job) {
  return g_settled && xQueueReceive(g_settled, &job, 0) == pdTRUE;
}

void drop(const char *show) {
  size_t   length = strlen(show);
  uint8_t *frame  = (uint8_t *)malloc(DOC_HEADER + length);
  if (!frame) return;

  const uint8_t head[DOC_HEADER] = {0x03, DROP, (uint8_t)length, 0, 0, 0, 0};
  memcpy(frame, head, DOC_HEADER);
  memcpy(frame + DOC_HEADER, show, length);

  Job job = {frame, DOC_HEADER + length, -1, false, nullptr, nullptr};
  if (!submit(job)) free(frame);
}

bool whole(const char *show, Span &span) {
  char file[PATH_LIMIT];
  if (!path(file, show, "")) return false;

  Hold        hold;
  struct stat st;
  span = {0, stat(file, &st) ? 0 : (uint32_t)st.st_size, g_generation};
  g_readers++;
  return true;
}

bool locate(const char *show, const char *folder, const char *id, Span &span) {
  char file[PATH_LIMIT];
  span = {0, 0, 0};
  if (!path(file, show, "")) return false;

  Hold hold;
  int  fd = ::open(file, O_RDONLY);
  if (fd < 0) return false;

  uint32_t size  = sizeOf(fd);
  bool     found = false;
  Record   r;
  for (uint32_t at = 0; at < size && record(fd, at, size, r); at = r.next) {
    if (strcmp(r.folder, folder) || strcmp(r.id, id)) continue;
    found = r.op == PUT;
    span  = {r.body, r.next, g_generation};
  }
  ::close(fd);
  if (found) g_readers++;
  return found;
}

long read(const char *show, Span &span, uint8_t *into, size_t max) {
  char file[PATH_LIMIT];
  if (!path(file, show, "")) return -1;

  size_t want = span.to - span.from;
  if (want > max) want = max;
  if (!want) return 0;

  Hold hold;
  if (span.generation != g_generation) return -1;
  int fd = ::open(file, O_RDONLY);
  if (fd < 0) return -1;
  ssize_t n = ::pread(fd, into, want, span.from);
  ::close(fd);
  if (n <= 0) return -1;
  span.from += n;
  return n;
}

void finish() {
  Hold hold;
  g_readers--;
}

size_t used() { return g_used; }

size_t capacity() { return g_ready ? LittleFS.totalBytes() : 0; }

}  // namespace Store
