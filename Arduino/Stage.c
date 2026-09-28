#include "Stage.h"

#include <stdlib.h>
#include <string.h>

enum { SLOTS = STAGE_SLOTS, BYTES = SLOTS / 8 + 1, NAME = 24, NONE = 0xFF };
enum { FADES = 1, DIMS = 2, BAND = 4, OPEN = 8, WIDE = 16, FINE = 32 };
enum { PLAY = 0, LAND = 1, STOP = 2, MORE = 3 };
enum { HELD = 0x8000 };

static const uint32_t LIVE   = 0x80000000u;
static const uint32_t PAIRED = 0x40000000u;
static const uint32_t SPAN   = 0x3FFFFFFFu;

typedef struct {
  uint8_t  flags;
  uint8_t  from;
  uint8_t  to;
  uint8_t  open;
  uint16_t partner;
} Channel;

typedef struct {
  uint16_t from;
  uint16_t to;
  uint32_t start;
  uint32_t length;
} Motion;

typedef struct {
  const uint8_t *at;
  const uint8_t *end;
  bool           ok;
} Reader;

typedef struct {
  char           cue[NAME];
  uint32_t       delay;
  uint32_t       fade;
  uint32_t       follow;
  const uint8_t *runs;
  size_t         size;
} Step;

typedef struct Scene {
  struct Scene  *next;
  char           id[NAME];
  char           cue[NAME];
  uint8_t       *steps;
  size_t         size;
  uint8_t        count;
  uint8_t        step;
  uint8_t        loop;
  bool           wants;
  uint32_t       started;
  uint32_t       delay;
  uint32_t       fade;
  uint32_t       follow;
  const uint8_t *runs;
  size_t         runsSize;
} Scene;

struct Stage {
  uint8_t  source[SLOTS + 1];
  uint8_t  output[SLOTS + 1];
  uint8_t  held[SLOTS + 1];
  uint8_t  target[SLOTS + 1];
  uint8_t  writer[SLOTS + 1];
  uint8_t  holding[BYTES];
  uint8_t  changed[BYTES];
  uint8_t  wanted[BYTES];
  uint8_t  kept[BYTES];
  Channel  channels[SLOTS + 1];
  Motion   motions[SLOTS + 1];
  Scene   *scenes;
  float    master;
  bool     blackout;
  int      dirtyFrom;
  int      dirtyTo;
  uint8_t  client;
  uint16_t seq;
};

static bool bit(const uint8_t *set, int a) { return set[a >> 3] & (1 << (a & 7)); }
static void mark(uint8_t *set, int a) { set[a >> 3] |= (uint8_t)(1 << (a & 7)); }
static void unmark(uint8_t *set, int a) { set[a >> 3] &= (uint8_t)~(1 << (a & 7)); }

static uint8_t byte(Reader *r) {
  if (r->at >= r->end) {
    r->ok = false;
    return 0;
  }
  return *r->at++;
}

static uint16_t word(Reader *r) {
  uint16_t low = byte(r);
  return low | (uint16_t)(byte(r) << 8);
}

static uint32_t number(Reader *r) {
  uint32_t value = 0;
  for (int shift = 0; shift < 35 && r->ok; shift += 7) {
    uint8_t next = byte(r);
    value |= (uint32_t)(next & 0x7F) << shift;
    if (next < 0x80) return value;
  }
  r->ok = false;
  return 0;
}

static const uint8_t *bytes(Reader *r, size_t count) {
  if ((size_t)(r->end - r->at) < count) {
    r->ok = false;
    return NULL;
  }
  r->at += count;
  return r->at - count;
}

static void text(Reader *r, char *out) {
  uint8_t        length = byte(r);
  const uint8_t *chars  = bytes(r, length);
  if (length >= NAME) r->ok = false;
  if (!r->ok) length = 0;
  if (chars) memcpy(out, chars, length);
  out[length] = '\0';
}

static bool run(Reader *r, bool heldAllowed, int *start, int *count, const uint8_t **values) {
  uint16_t head = word(r);
  *count        = word(r);
  *start        = head & 0x3FF;
  *values       = (head & HELD) ? NULL : bytes(r, (size_t)*count);
  bool shaped   = (head & ~(HELD | 0x3FF)) == 0 && (heldAllowed || !(head & HELD));
  if (!shaped || *start < 1 || *count < 1 || *start + *count - 1 > SLOTS) r->ok = false;
  return r->ok;
}

static bool runsValid(const uint8_t *p, size_t size, bool heldAllowed) {
  Reader         r = {p, p + size, true};
  int            start, count;
  const uint8_t *values;
  while (r.at < r.end) {
    if (!run(&r, heldAllowed, &start, &count, &values)) return false;
  }
  return true;
}

static bool step(Reader *r, Step *s) {
  text(r, s->cue);
  s->delay  = number(r);
  s->fade   = number(r);
  s->follow = number(r);
  s->size   = number(r);
  s->runs   = bytes(r, s->size);
  return r->ok && s->delay <= SPAN && s->fade <= SPAN && s->follow <= SPAN && runsValid(s->runs, s->size, true);
}

static bool stepAt(const Scene *scene, uint8_t index, Step *s) {
  Reader r = {scene->steps, scene->steps + scene->size, true};
  for (int i = 0; i <= index; i++) {
    if (!step(&r, s)) return false;
  }
  return true;
}

static float level(const Stage *stage) {
  if (stage->blackout || stage->master <= 0) return 0;
  return stage->master >= 1 ? 1 : stage->master;
}

static uint8_t band(uint8_t value, const Channel *c, float amount) {
  if (value < c->from) return value;
  if (value <= c->to) return c->from + (uint8_t)((value - c->from) * amount + 0.5f);
  if ((c->flags & OPEN) && value >= c->open) return c->from + (uint8_t)((c->to - c->from) * amount + 0.5f);
  return value;
}

static bool follower(const Stage *stage, int a) {
  const Channel *c = &stage->channels[a];
  return (c->flags & FINE) && (stage->channels[c->partner].flags & DIMS);
}

static void scaled(const Stage *stage, const uint8_t *source, uint8_t *out, int a) {
  const Channel *c      = &stage->channels[a];
  float          amount = level(stage);
  if (!(c->flags & DIMS)) {
    out[a] = source[a];
  } else if (c->flags & WIDE) {
    uint32_t value = (uint32_t)(source[a] << 8 | source[c->partner]);
    if (amount < 1) value = (uint32_t)(value * amount + 0.5f);
    out[a]          = (uint8_t)(value >> 8);
    out[c->partner] = (uint8_t)(value & 0xFF);
  } else if (amount >= 1) {
    out[a] = source[a];
  } else if (amount <= 0) {
    out[a] = 0;
  } else if (c->flags & BAND) {
    out[a] = band(source[a], c, amount);
  } else {
    out[a] = (uint8_t)(source[a] * amount + 0.5f);
  }
}

static void dirty(Stage *stage, int a) {
  if (!stage->dirtyTo || a < stage->dirtyFrom) stage->dirtyFrom = a;
  if (a > stage->dirtyTo) stage->dirtyTo = a;
}

static void shine(Stage *stage, int a) {
  if (follower(stage, a)) a = stage->channels[a].partner;
  int     partner = (stage->channels[a].flags & WIDE) ? stage->channels[a].partner : a;
  uint8_t was     = stage->output[a];
  uint8_t wasPair = stage->output[partner];
  scaled(stage, stage->source, stage->output, a);
  if (stage->output[a] != was) dirty(stage, a);
  if (stage->output[partner] != wasPair) dirty(stage, partner);
}

static void shineAll(Stage *stage) {
  for (int a = 1; a <= SLOTS; a++) shine(stage, a);
}

static void put(Stage *stage, int a, uint8_t value, uint8_t writer) {
  if (stage->source[a] == value) return;
  stage->source[a] = value;
  stage->writer[a] = writer;
  mark(stage->changed, a);
  shine(stage, a);
}

static uint16_t reading(const Stage *stage, int a, bool wide) {
  return wide ? (uint16_t)(stage->source[a] << 8 | stage->source[stage->channels[a].partner]) : stage->source[a];
}

static float bandShare(int value, const Channel *c, bool *known) {
  *known = true;
  if (value < c->from) return 0;
  if (value <= c->to) return (float)(value - c->from) / (c->to > c->from ? c->to - c->from : 1);
  if ((c->flags & OPEN) && value >= c->open) return 1;
  *known = false;
  return 0;
}

static int between(const Channel *c, const Motion *m, float progress) {
  if (!(c->flags & BAND)) return m->from + (int)((m->to - m->from) * progress + (m->to >= m->from ? 0.5f : -0.5f));
  bool  lowKnown, highKnown;
  float low  = bandShare(m->from, c, &lowKnown);
  float high = bandShare(m->to, c, &highKnown);
  if (!lowKnown || !highKnown) return m->to;
  float wanted = low + (high - low) * progress;
  if (wanted <= 0) return 0;
  return c->from + (int)((c->to - c->from) * wanted + 0.5f);
}

static bool live(const Stage *stage, int a) {
  const Channel *c = &stage->channels[a];
  return (stage->motions[a].length & LIVE) || ((c->flags & (WIDE | FINE)) && (stage->motions[c->partner].length & LIVE));
}

static void cancel(Stage *stage, int a) {
  const Channel *c = &stage->channels[a];
  stage->motions[a].length &= ~LIVE;
  if (c->flags & (WIDE | FINE)) stage->motions[c->partner].length &= ~LIVE;
}

static void aim(Stage *stage, uint32_t start, uint32_t length) {
  for (int a = 1; a <= SLOTS; a++) {
    if (!bit(stage->wanted, a)) continue;
    const Channel *c = &stage->channels[a];
    if ((c->flags & FINE) && bit(stage->wanted, c->partner)) continue;

    bool     wide = (c->flags & WIDE) && bit(stage->wanted, c->partner);
    uint16_t to   = wide ? (uint16_t)(stage->target[a] << 8 | stage->target[c->partner]) : stage->target[a];
    uint16_t from = reading(stage, a, wide);
    cancel(stage, a);
    if (from == to) continue;

    uint32_t span     = (c->flags & (FADES | BAND)) ? length : 0;
    stage->motions[a] = (Motion){from, to, start, span | LIVE | (wide ? PAIRED : 0)};
  }
  memset(stage->wanted, 0, BYTES);
}

static void want(Stage *stage, const uint8_t *runs, size_t size) {
  Reader         r = {runs, runs + size, true};
  int            start, count;
  const uint8_t *values;
  while (r.at < r.end && run(&r, true, &start, &count, &values)) {
    for (int i = 0; i < count; i++) {
      int a            = start + i;
      stage->target[a] = values ? values[i] : bit(stage->holding, a) ? stage->held[a] : stage->source[a];
      mark(stage->wanted, a);
    }
  }
}

static void capture(Stage *stage, const uint8_t *runs, size_t size) {
  Reader         r = {runs, runs + size, true};
  int            start, count;
  const uint8_t *values;
  while (r.at < r.end && run(&r, true, &start, &count, &values)) {
    for (int a = start; a < start + count; a++) {
      if (bit(stage->holding, a)) continue;
      stage->held[a] = stage->source[a];
      mark(stage->holding, a);
    }
  }
}

static Scene *find(Stage *stage, const char *id) {
  for (Scene *scene = stage->scenes; scene; scene = scene->next) {
    if (!strcmp(scene->id, id)) return scene;
  }
  return NULL;
}

static void unlink(Stage *stage, Scene *gone) {
  for (Scene **link = &stage->scenes; *link; link = &(*link)->next) {
    if (*link != gone) continue;
    *link      = gone->next;
    gone->next = NULL;
    return;
  }
}

static void append(Stage *stage, Scene *scene) {
  Scene **link = &stage->scenes;
  while (*link) link = &(*link)->next;
  *link = scene;
}

static void enter(Stage *stage, Scene *scene, uint8_t index, uint32_t now, bool moving) {
  Step s;
  if (!stepAt(scene, index, &s)) return;
  memcpy(scene->cue, s.cue, NAME);
  scene->step     = index;
  scene->started  = now;
  scene->delay    = s.delay;
  scene->fade     = s.fade;
  scene->follow   = s.follow;
  scene->runs     = s.runs;
  scene->runsSize = s.size;
  scene->wants    = false;
  if (!moving) return;
  want(stage, s.runs, s.size);
  aim(stage, now + s.delay, s.fade);
}

static bool program(Reader *r, uint8_t *loop, uint8_t *count, const uint8_t **steps, size_t *size) {
  *loop  = byte(r);
  *count = byte(r);
  *steps = r->at;
  Step s;
  for (int i = 0; i < *count && r->ok; i++) step(r, &s);
  *size = (size_t)(r->at - *steps);
  return r->ok && r->at == r->end && *count && (*loop == NONE || *loop < *count);
}

static void release(Stage *stage, Scene *scene) {
  unlink(stage, scene);
  free(scene->steps);
  free(scene);
}

static void play(Stage *stage, const char *id, Reader *r, uint32_t now, bool moving) {
  uint8_t        loop, count;
  const uint8_t *steps;
  size_t         size;
  if (!program(r, &loop, &count, &steps, &size)) return;

  Scene   *scene = find(stage, id);
  uint8_t *copy  = (uint8_t *)malloc(size);
  if (!scene) scene = (Scene *)calloc(1, sizeof(Scene));
  if (!copy || !scene) {
    free(copy);
    if (scene && !find(stage, id)) free(scene);
    return;
  }

  unlink(stage, scene);
  free(scene->steps);
  strcpy(scene->id, id);
  scene->steps = copy;
  scene->size  = size;
  scene->count = count;
  scene->loop  = loop;
  memcpy(copy, steps, size);
  append(stage, scene);

  Step first;
  stepAt(scene, 0, &first);
  capture(stage, first.runs, first.size);
  enter(stage, scene, 0, now, moving);
  if (moving) return;

  Reader         runs = {first.runs, first.runs + first.size, true};
  int            start, length;
  const uint8_t *values;
  while (runs.at < runs.end && run(&runs, true, &start, &length, &values)) {
    for (int a = start; values && a < start + length; a++) cancel(stage, a);
  }
  scene->delay  = 0;
  scene->fade   = 0;
  scene->follow = 0;
}

static void more(Scene *scene, Reader *r) {
  char after[NAME];
  text(r, after);
  uint8_t        loop, count;
  const uint8_t *steps;
  size_t         size;
  if (!program(r, &loop, &count, &steps, &size) || !scene || !scene->wants || strcmp(scene->cue, after)) return;

  uint8_t *copy = (uint8_t *)malloc(size);
  if (!copy) return;
  memcpy(copy, steps, size);
  free(scene->steps);
  scene->steps = copy;
  scene->size  = size;
  scene->count = count;
  scene->loop  = loop;
  scene->step  = 0;
  scene->wants = false;

  Step first;
  stepAt(scene, 0, &first);
  scene->runs     = first.runs;
  scene->runsSize = first.size;
}

static void stop(Stage *stage, Scene *scene, uint32_t fade, uint32_t now) {
  if (!scene) return;
  unlink(stage, scene);
  want(stage, scene->runs, scene->runsSize);
  memset(stage->kept, 0, BYTES);

  for (Scene *other = stage->scenes; other; other = other->next) {
    Reader         r = {other->runs, other->runs + other->runsSize, true};
    int            start, count;
    const uint8_t *values;
    while (r.at < r.end && run(&r, true, &start, &count, &values)) {
      for (int i = 0; i < count; i++) {
        int a = start + i;
        if (!bit(stage->wanted, a)) continue;
        stage->target[a] = values ? values[i] : stage->held[a];
        mark(stage->kept, a);
      }
    }
  }

  for (int a = 1; a <= SLOTS; a++) {
    if (!bit(stage->wanted, a) || bit(stage->kept, a)) continue;
    if (bit(stage->holding, a)) stage->target[a] = stage->held[a];
    unmark(stage->holding, a);
  }

  aim(stage, now, fade);
  if (!stage->scenes) memset(stage->holding, 0, BYTES);
  free(scene->steps);
  free(scene);
}

Stage *stage_new(void) {
  Stage *stage = (Stage *)calloc(1, sizeof(Stage));
  if (stage) stage->master = 1;
  if (stage) stage->client = NONE;
  return stage;
}

void stage_free(Stage *stage) {
  if (!stage) return;
  stage_clear(stage);
  free(stage);
}

void stage_clear(Stage *stage) {
  while (stage->scenes) release(stage, stage->scenes);
  for (int a = 0; a <= SLOTS; a++) stage->motions[a].length &= ~LIVE;
  memset(stage->holding, 0, BYTES);
}

void stage_map(Stage *stage, const uint8_t *message, size_t length) {
  Reader r = {message, message + length, true};
  if (byte(&r) != STAGE_MAP) return;
  memset(stage->channels, 0, sizeof(stage->channels));

  while (r.at < r.end && r.ok) {
    uint16_t a     = word(&r);
    uint8_t  flags = byte(&r) & (FADES | DIMS | BAND | OPEN | WIDE);
    Channel  c     = {flags, 0, 0, 0, 0};
    if (flags & WIDE) c.partner = word(&r);
    if (flags & BAND) c.from = byte(&r);
    if (flags & BAND) c.to = byte(&r);
    if (flags & OPEN) c.open = byte(&r);
    bool fits = a >= 1 && a <= SLOTS && (!(flags & WIDE) || (c.partner >= 1 && c.partner <= SLOTS && c.partner != a));
    if (!r.ok || !fits) break;
    stage->channels[a] = c;
    if (flags & WIDE) stage->channels[c.partner] = (Channel){FINE, 0, 0, 0, a};
  }

  shineAll(stage);
}

void stage_levels(Stage *stage, float master, bool blackout) {
  stage->master   = master;
  stage->blackout = blackout;
  shineAll(stage);
}

bool stage_write(Stage *stage, const uint8_t *message, size_t length, uint8_t writer) {
  Reader r = {message, message + length, true};
  if (byte(&r) != STAGE_FRAME || byte(&r) != 0 || r.at == r.end || !runsValid(r.at, (size_t)(r.end - r.at), false)) return false;

  int            start, count;
  const uint8_t *values;
  Reader         moving = r;
  while (moving.at < moving.end && run(&moving, false, &start, &count, &values)) {
    for (int a = start; a < start + count; a++) {
      if (live(stage, a)) mark(stage->kept, a);
    }
  }

  while (r.at < r.end && run(&r, false, &start, &count, &values)) {
    for (int i = 0; i < count; i++) {
      int a = start + i;
      cancel(stage, a);
      put(stage, a, values[i], writer);
      if (!bit(stage->kept, a)) continue;
      mark(stage->changed, a);
      stage->writer[a] = NONE;
    }
  }
  memset(stage->kept, 0, BYTES);
  return true;
}

void stage_command(Stage *stage, uint8_t client, const uint8_t *message, size_t length, uint32_t now) {
  Reader r = {message, message + length, true};
  if (byte(&r) != STAGE_COMMAND) return;
  stage->client = client;
  stage->seq    = word(&r);

  uint8_t action = byte(&r);
  char    id[NAME];
  text(&r, id);
  if (!r.ok || !id[0]) return;

  switch (action) {
    case PLAY: play(stage, id, &r, now, true); break;
    case LAND: play(stage, id, &r, now, false); break;
    case STOP: {
      uint32_t fade = number(&r);
      if (r.ok && r.at == r.end && fade <= SPAN) stop(stage, find(stage, id), fade, now);
      break;
    }
    case MORE: more(find(stage, id), &r); break;
    default: break;
  }
}

bool stage_tick(Stage *stage, uint32_t now) {
  for (int a = 1; a <= SLOTS; a++) {
    Motion *m = &stage->motions[a];
    if (!(m->length & LIVE) || (int32_t)(now - m->start) < 0) continue;

    uint32_t length = m->length & SPAN;
    uint32_t since  = now - m->start;
    bool     done   = since >= length;
    int      value  = done ? m->to : between(&stage->channels[a], m, (float)since / length);
    if (done) m->length &= ~LIVE;

    if ((m->length & PAIRED) && (stage->channels[a].flags & WIDE)) {
      put(stage, a, (uint8_t)(value >> 8), NONE);
      put(stage, stage->channels[a].partner, (uint8_t)(value & 0xFF), NONE);
    } else {
      put(stage, a, (uint8_t)value, NONE);
    }
  }

  bool   restated = false;
  size_t left     = 0;
  for (Scene *scene = stage->scenes; scene; scene = scene->next) left++;
  for (Scene *scene = stage->scenes; scene && left--;) {
    Scene   *next = scene->next;
    uint32_t due  = scene->started + scene->delay + scene->fade + scene->follow - 1;
    if (!scene->follow || scene->wants || (int32_t)(now - due) < 0) {
      scene = next;
      continue;
    }

    restated = true;
    if (scene->step + 1 < scene->count || scene->loop != NONE) {
      unlink(stage, scene);
      append(stage, scene);
      enter(stage, scene, scene->step + 1 < scene->count ? scene->step + 1 : scene->loop, now, true);
    } else {
      scene->wants = true;
    }
    scene = next;
  }
  return restated;
}

bool stage_busy(const Stage *stage) {
  for (int a = 1; a <= SLOTS; a++) {
    if (stage->motions[a].length & LIVE) return true;
  }
  for (const Scene *scene = stage->scenes; scene; scene = scene->next) {
    if (scene->follow && !scene->wants) return true;
  }
  return false;
}

static bool owed(const Stage *stage, int a, uint8_t client) {
  return bit(stage->changed, a) && (stage->writer[a] != client || client == NONE);
}

size_t stage_frame(const Stage *stage, uint8_t client, uint8_t *out, size_t room) {
  size_t n = 2;
  if (room < 2 + 4 + SLOTS + 4 * (SLOTS / 2)) return 0;
  out[0] = STAGE_FRAME;
  out[1] = 0;

  for (int a = 1; a <= SLOTS;) {
    if (!owed(stage, a, client)) {
      a++;
      continue;
    }
    int start = a;
    while (a <= SLOTS && owed(stage, a, client)) a++;
    int count  = a - start;
    out[n++]   = (uint8_t)(start & 0xFF);
    out[n++]   = (uint8_t)(start >> 8);
    out[n++]   = (uint8_t)(count & 0xFF);
    out[n++]   = (uint8_t)(count >> 8);
    memcpy(out + n, stage->source + start, (size_t)count);
    n += (size_t)count;
  }

  return n > 2 ? n : 0;
}

void stage_relayed(Stage *stage) { memset(stage->changed, 0, BYTES); }

static size_t writeNumber(uint8_t *out, uint32_t value) {
  size_t n = 0;
  while (value >= 0x80) {
    out[n++] = (uint8_t)(value & 0x7F) | 0x80;
    value >>= 7;
  }
  out[n++] = (uint8_t)value;
  return n;
}

static size_t writeText(uint8_t *out, const char *value) {
  size_t length = strlen(value);
  out[0]        = (uint8_t)length;
  memcpy(out + 1, value, length);
  return length + 1;
}

size_t stage_state(Stage *stage, uint32_t now, uint8_t *out, size_t room) {
  size_t count = 0;
  for (Scene *scene = stage->scenes; scene; scene = scene->next) count++;
  size_t need = 4 + 5 + count * (2 * NAME + 16);
  if (!out) return need;
  if (room < need) return 0;

  size_t n = 0;
  out[n++] = STAGE_COMMAND;
  out[n++] = stage->client;
  out[n++] = (uint8_t)(stage->seq & 0xFF);
  out[n++] = (uint8_t)(stage->seq >> 8);
  n += writeNumber(out + n, (uint32_t)count);

  for (Scene *scene = stage->scenes; scene; scene = scene->next) {
    uint32_t whole   = scene->delay + scene->fade;
    uint32_t elapsed = now - scene->started;
    n += writeText(out + n, scene->id);
    n += writeText(out + n, scene->cue);
    n += writeNumber(out + n, scene->delay);
    n += writeNumber(out + n, scene->fade);
    n += writeNumber(out + n, elapsed < whole ? elapsed : whole);
    out[n++] = scene->wants;
  }

  stage->client = NONE;
  stage->seq    = 0;
  return n;
}

const uint8_t *stage_source(const Stage *stage) { return stage->source; }

const uint8_t *stage_output(Stage *stage, int *from, int *to) {
  *from            = stage->dirtyFrom;
  *to              = stage->dirtyTo;
  stage->dirtyFrom = 0;
  stage->dirtyTo   = 0;
  return stage->output;
}

void stage_scale(const Stage *stage, uint8_t *values) {
  uint8_t source[SLOTS + 1];
  memcpy(source + 1, values, SLOTS);
  for (int a = 1; a <= SLOTS; a++) {
    if (!follower(stage, a)) scaled(stage, source, values - 1, a);
  }
}
