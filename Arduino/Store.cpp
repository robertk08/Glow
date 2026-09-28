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
const int      JOBS_WAITING = 32;
const int      KEEPER_STACK = 6144;
const size_t   PIECE        = 1024;
const size_t   BATCH        = 4096;
const int      SORTED       = 2048;
const int      SLICES_MAX   = 64;
const uint32_t PUT_BIT      = 0x80000000;
const int      SHOWS_HASHED = 64;

bool              g_ready      = false;
volatile size_t   g_used       = 0;
size_t            g_total      = 0;
char              g_spent[NAME_LIMIT];
uint32_t          g_generations[SHOWS_HASHED] = {};
int               g_readers    = 0;
SemaphoreHandle_t g_lock       = nullptr;
QueueHandle_t     g_jobs       = nullptr;
QueueHandle_t     g_settled    = nullptr;
uint8_t           g_piece[BATCH];
uint8_t           g_scan[PIECE];
uint32_t          g_pieces     = 0;

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
};

Entry g_entries[SORTED];

bool path(char *out, const char *show, int file, const char *suffix) {
  if (!safe(show)) return false;
  int n = file ? snprintf(out, PATH_LIMIT, "%s/%s.%d%s", ROOT, show, file, suffix) : snprintf(out, PATH_LIMIT, "%s/%s%s", ROOT, show, suffix);
  return n < (int)PATH_LIMIT;
}

void breathe() {
  if (++g_pieces % 16 == 0) vTaskDelay(1);
}

uint64_t hash(uint64_t h, const char *text) {
  for (const char *p = text; *p; p++) h = (h ^ (uint8_t)*p) * 1099511628211ULL;
  return h;
}

uint64_t key(const char *folder, const char *id) {
  return hash(hash(hash(1469598103934665603ULL, folder), "/"), id);
}

uint64_t key(const Record &r) { return key(r.folder, r.id); }

uint32_t &generation(const char *show) { return g_generations[hash(1469598103934665603ULL, show) % SHOWS_HASHED]; }

uint32_t sizeOf(int fd) {
  struct stat st;
  return fstat(fd, &st) ? 0 : (uint32_t)st.st_size;
}

struct Cursor {
  int      fd;
  uint32_t size;
  uint32_t base   = 0;
  uint32_t filled = 0;

  const uint8_t *at(uint32_t offset, size_t length) {
    if (offset < base || offset + length > base + filled) {
      breathe();
      base      = offset;
      ssize_t n = ::pread(fd, g_scan, std::min(PIECE, (size_t)(size - offset)), offset);
      filled    = n > 0 ? n : 0;
      if (length > filled) return nullptr;
    }
    return g_scan + (offset - base);
  }
};

bool record(Cursor &c, uint32_t at, Record &r) {
  const uint8_t *head = at + HEAD <= c.size ? c.at(at, HEAD) : nullptr;
  if (!head) return false;

  size_t folderLength = head[1];
  size_t idLength     = head[2];
  if (head[0] > ERASE || folderLength >= NAME_LIMIT || idLength >= NAME_LIMIT) return false;

  r.op   = head[0];
  r.at   = at;
  r.body = at + HEAD + folderLength + idLength;
  r.next = r.body + (head[3] | (head[4] << 8));
  if (r.next > c.size) return false;

  const uint8_t *names = c.at(at + HEAD, folderLength + idLength);
  if (!names) return false;
  memcpy(r.folder, names, folderLength);
  memcpy(r.id, names + folderLength, idLength);
  r.folder[folderLength] = '\0';
  r.id[idLength]         = '\0';
  return true;
}

size_t showLength(const Job &job) { return job.frame[2]; }

int fileOf(const Job &job) {
  const uint8_t *p = job.frame + DOC_HEADER + job.frame[2];
  char folder[NAME_LIMIT];
  char id[NAME_LIMIT];
  memcpy(folder, p, job.frame[3]);
  memcpy(id, p + job.frame[3], job.frame[4]);
  folder[job.frame[3]] = '\0';
  id[job.frame[4]]     = '\0';
  return (int)(key(folder, id) % FILES);
}

bool sameShow(const Job &a, const Job &b) {
  return b.frame[1] != DROP && showLength(a) == showLength(b) && !memcmp(a.frame + DOC_HEADER, b.frame + DOC_HEADER, showLength(a));
}

bool append(const char *file, Job **jobs, int count, uint32_t &before, uint32_t &after) {
  Hold hold;
  return Flash::guarded([&] {
    int fd = ::open(file, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return false;
    before = sizeOf(fd);
    after  = before;

    bool written = true;
    for (int i = 0; i < count && written; i++) {
      const uint8_t *p          = jobs[i]->frame;
      uint8_t        head[HEAD] = {p[1], p[3], p[4], p[5], p[6]};
      size_t         skip       = DOC_HEADER + showLength(*jobs[i]);
      size_t         length     = jobs[i]->length - skip;
      written = ::write(fd, head, HEAD) == (ssize_t)HEAD && ::write(fd, p + skip, length) == (ssize_t)length;
      after += HEAD + length;
    }
    if (!written) ftruncate(fd, before);
    return ::close(fd) == 0 && written;
  });
}

int gather(int fd, uint32_t size, int slices, int slice) {
  int    count = 0;
  Cursor c{fd, size};
  Record r;
  for (uint32_t at = 0; at < size && record(c, at, r); at = r.next) {
    uint64_t k = key(r);
    if ((int)((k >> 32) % slices) != slice) continue;
    if (count == SORTED) return -1;
    g_entries[count++] = {k, r.at, (r.next - r.at) | (r.op == PUT ? PUT_BIT : 0)};
  }

  std::sort(g_entries, g_entries + count, [](const Entry &a, const Entry &b) { return a.key != b.key ? a.key < b.key : a.at < b.at; });

  int kept = 0;
  for (int i = 0; i < count; i++) {
    if ((i + 1 < count && g_entries[i + 1].key == g_entries[i].key) || !(g_entries[i].length & PUT_BIT)) continue;
    g_entries[kept] = g_entries[i];
    g_entries[kept++].length &= ~PUT_BIT;
  }

  std::sort(g_entries, g_entries + kept, [](const Entry &a, const Entry &b) { return a.at < b.at; });
  return kept;
}

bool flush(int fd, size_t &waiting) {
  bool written = Flash::guarded([&] { return ::write(fd, g_piece, waiting) == (ssize_t)waiting; });
  waiting      = 0;
  return written;
}

bool review(const char *show, int file, bool always, uint32_t room = UINT32_MAX) {
  char name[PATH_LIMIT];
  char spare[PATH_LIMIT];
  if (!path(name, show, file, "") || !path(spare, show, file, ".tmp")) return false;

  Hold     hold;
  uint32_t began = millis();
  if (!always && g_readers) return false;
  int from = ::open(name, O_RDONLY);
  if (from < 0) return false;
  uint32_t size = sizeOf(from);
  if (size / 2 > room) {
    ::close(from);
    return false;
  }

  uint32_t records = 0;
  Cursor   c{from, size};
  Record   r;
  for (uint32_t at = 0; at < size && record(c, at, r); at = r.next) records++;

  int      slices  = records / SORTED + 1;
  uint32_t holding = 0;
  int      slice   = 0;
  while (slice < slices && slices <= SLICES_MAX) {
    int kept = gather(from, size, slices, slice);
    if (kept < 0) {
      slices++;
      slice   = 0;
      holding = 0;
      continue;
    }
    for (int i = 0; i < kept; i++) holding += g_entries[i].length;
    slice++;
  }

  if (slices > SLICES_MAX || holding == size || holding > room || (!always && holding * 2 > size)) {
    ::close(from);
    return false;
  }

  int    to      = ::open(spare, O_WRONLY | O_CREAT | O_TRUNC, 0644);
  bool   copied  = to >= 0;
  size_t waiting = 0;
  for (slice = 0; copied && slice < slices; slice++) {
    int kept = gather(from, size, slices, slice);
    copied   = kept >= 0;
    for (int i = 0; copied && i < kept; i++) {
      for (uint32_t done = 0; copied && done < g_entries[i].length;) {
        size_t n = std::min(BATCH - waiting, (size_t)(g_entries[i].length - done));
        copied   = ::pread(from, g_piece + waiting, n, g_entries[i].at + done) == (ssize_t)n;
        waiting += n;
        done += n;
        if (copied && waiting == BATCH) copied = flush(to, waiting);
        breathe();
      }
    }
  }
  if (copied && waiting) copied = flush(to, waiting);
  ::close(from);

  if (to >= 0) copied = Flash::guarded([&] { return ::close(to) == 0; }) && copied;
  if (copied) copied = Flash::guarded([&] { return ::rename(spare, name) == 0; });
  if (!copied) Flash::guarded([&] { return ::unlink(spare) == 0; });
  if (copied) generation(show)++;
  Serial.printf("store: %s.%d kept %u of %u bytes in %u ms\n", show, file, (unsigned)holding, (unsigned)size, (unsigned)(millis() - began));
  return copied;
}

bool fits(uint32_t bytes) { return g_used + bytes + g_total / 8 <= g_total; }

void perform(Job *jobs, int count) {
  char show[NAME_LIMIT];
  memcpy(show, jobs[0].frame + DOC_HEADER, showLength(jobs[0]));
  show[showLength(jobs[0])] = '\0';

  if (jobs[0].frame[1] == DROP) {
    if (safe(show)) {
      Hold hold;
      for (int file = 0; file < FILES; file++) {
        char name[PATH_LIMIT];
        if (path(name, show, file, "")) Flash::guarded([&] { return ::unlink(name) == 0; });
      }
      generation(show)++;
    }
    free(jobs[0].frame);
    return;
  }

  bool listed = safe(show) && Shows::contains(show);
  int  grown  = 0;
  for (int file = 0; listed && file < FILES; file++) {
    Job *group[JOBS_WAITING];
    int  members = 0;
    for (int i = 0; i < count; i++) {
      if (fileOf(jobs[i]) == file) group[members++] = &jobs[i];
    }
    if (!members) continue;

    bool     erasing = true;
    bool     erased  = false;
    uint32_t adding  = 0;
    for (int i = 0; i < members; i++) {
      erasing = erasing && group[i]->frame[1] == ERASE;
      erased  = erased || group[i]->frame[1] == ERASE;
      adding += HEAD + group[i]->length - DOC_HEADER - showLength(*group[i]);
    }

    char     name[PATH_LIMIT];
    uint32_t before = 0;
    uint32_t after  = 0;
    bool     stored = path(name, show, file, "") && (erasing || fits(adding)) && append(name, group, members, before, after);
    if (!stored && strcmp(g_spent, show)) {
      g_used = LittleFS.usedBytes();
      for (int other = 0; other < FILES && !(erasing || fits(adding)); other++) {
        if (review(show, other, true, g_total - g_used)) g_used = LittleFS.usedBytes();
      }
      stored = (erasing || fits(adding)) && append(name, group, members, before, after);
      if (!stored) strcpy(g_spent, show);
    }
    if (stored) g_used += after - before;
    if (stored && erased) g_spent[0] = '\0';
    for (int i = 0; i < members; i++) group[i]->stored = stored;

    uint32_t step = REVIEW_EVERY;
    while (step * 8 <= before) step *= 2;
    if (stored && after >= REVIEW_FROM && before / step != after / step) grown |= 1 << file;
  }

  for (int i = 0; i < count; i++) {
    if (jobs[i].done) {
      *jobs[i].outcome = jobs[i].stored;
      xSemaphoreGive(jobs[i].done);
    }
    xQueueSend(g_settled, &jobs[i], portMAX_DELAY);
  }

  for (int file = 0; file < FILES; file++) {
    if (grown & (1 << file)) review(show, file, false);
  }
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

}  // namespace

bool begin() {
  g_lock    = xSemaphoreCreateMutex();
  g_jobs    = xQueueCreate(JOBS_WAITING, sizeof(Job));
  g_settled = xQueueCreate(JOBS_WAITING * 2, sizeof(Job));
  g_ready   = g_lock && g_jobs && g_settled && LittleFS.begin(true) && (g_total = LittleFS.totalBytes()) &&
            xTaskCreatePinnedToCore(keeper, "store", KEEPER_STACK, nullptr, 1, nullptr, 0) == pdPASS;
  if (!g_ready) Serial.println(F("store: LittleFS unavailable, shows cannot be stored"));
  return g_ready;
}

void sweep() {
  if (!g_ready) return;

  std::vector<String> strays;
  if (DIR *root = opendir(ROOT)) {
    while (dirent *entry = readdir(root)) {
      char   show[NAME_LIMIT + 4];
      size_t n = strlen(entry->d_name);
      snprintf(show, sizeof(show), "%s", entry->d_name);
      if (n > 2 && show[n - 2] == '.' && show[n - 1] > '0' && show[n - 1] < '0' + FILES) show[n - 2] = '\0';
      if (entry->d_type == DT_REG && strcmp(entry->d_name, "shows.json") && !Shows::contains(show)) strays.push_back(String(ROOT) + "/" + entry->d_name);
    }
    closedir(root);
  }

  for (const String &stray : strays) Flash::guarded([&] { return ::unlink(stray.c_str()) == 0; });
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
  Hold hold;
  span = {0, 0, generation(show), {}};
  for (int file = 0; file < FILES; file++) {
    char        name[PATH_LIMIT];
    struct stat st;
    if (!path(name, show, file, "")) return false;
    span.sizes[file] = stat(name, &st) ? 0 : (uint32_t)st.st_size;
    span.to += span.sizes[file];
  }
  g_readers++;
  return true;
}

bool locate(const char *show, const char *folder, const char *id, Span &span) {
  span = {0, 0, 0, {}};
  Hold hold;
  bool found = false;
  for (int file = 0; file < FILES; file++) {
    char name[PATH_LIMIT];
    if (!path(name, show, file, "")) return false;
    int fd = ::open(name, O_RDONLY);
    if (fd < 0) continue;

    Cursor c{fd, sizeOf(fd)};
    Record r;
    for (uint32_t at = 0; at < c.size && record(c, at, r); at = r.next) {
      if (strcmp(r.folder, folder) || strcmp(r.id, id)) continue;
      found            = r.op == PUT;
      span             = {r.body, r.next, generation(show), {}};
      span.sizes[file] = r.next;
    }
    ::close(fd);
  }
  if (found) g_readers++;
  return found;
}

long read(const char *show, Span &span, uint8_t *into, size_t max) {
  Hold hold;
  if (span.generation != generation(show)) return -1;

  uint32_t offset = span.from;
  int      file   = 0;
  while (file < FILES && offset >= span.sizes[file]) offset -= span.sizes[file++];
  if (file == FILES) return span.from < span.to ? -1 : 0;

  size_t want = std::min(max, (size_t)std::min(span.sizes[file] - offset, span.to - span.from));
  if (!want) return 0;

  char name[PATH_LIMIT];
  if (!path(name, show, file, "")) return -1;
  int fd = ::open(name, O_RDONLY);
  if (fd < 0) return -1;
  ssize_t n = ::pread(fd, into, want, offset);
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

size_t capacity() { return g_ready ? g_total : 0; }

}  // namespace Store
