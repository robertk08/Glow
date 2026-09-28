#include "Stage.h"

#include <stdlib.h>
#include <string.h>

enum { SLOTS = STAGE_SLOTS, BYTES = SLOTS / 8 + 1, NAME = 40, NONE = 0xFF, ONWARD = 0xFE };
enum { FADES = 1, DIMS = 2, BAND = 4, OPEN = 8, WIDE = 16, FINE = 32 };
enum { PLAY = 0, LAND = 1, STOP = 2, MORE = 3 };
enum { HELD = 0x8000, ADDRESS = 0x3FF };

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
  int            start;
  int            count;
  const uint8_t *values;
} Run;

typedef struct {
  char           cue[NAME];
  uint32_t       delay;
  uint32_t       fade;
  uint32_t       follow;
  const uint8_t *runs;
  size_t         size;
} Step;

typedef struct {
  const uint8_t *steps;
  size_t         size;
  size_t         loopAt;
  uint8_t        count;
  uint8_t        loop;
} Program;

typedef struct Scene {
  struct Scene *next;
  char          id[NAME];
  uint8_t      *steps;
  size_t        size;
  size_t        loopAt;
  size_t        nextAt;
  uint8_t       count;
  uint8_t       loop;
  uint8_t       step;
  uint8_t       caller;
  bool          wants;
  uint32_t      started;
  Step          current;
} Scene;

struct Stage {
  uint8_t source[SLOTS + 1];
  uint8_t output[SLOTS + 1];
  uint8_t base[SLOTS + 1];
  uint8_t target[SLOTS + 1];
  uint8_t owed[SLOTS + 1];
  uint8_t wanted[BYTES];
  Channel channels[SLOTS + 1];
  Motion  motions[SLOTS + 1];
  Scene  *scenes;
  float   master;
  bool    blackout;
  int     dirtyFrom;
  int     dirtyTo;
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

static bool run(Reader *r, bool heldAllowed, Run *out) {
  if (r->at >= r->end) return false;
  uint16_t head = word(r);
  out->count    = word(r);
  out->start    = head & ADDRESS;
  out->values   = (head & HELD) ? NULL : bytes(r, (size_t)out->count);
  bool shaped   = (head & ~(HELD | ADDRESS)) == 0 && (heldAllowed || !(head & HELD));
  if (!shaped || out->start < 1 || out->count < 1 || out->start + out->count - 1 > SLOTS) r->ok = false;
  return r->ok;
}

static Reader runs(const Step *s) { return (Reader){s->runs, s->runs + s->size, true}; }

static bool valid(const uint8_t *p, size_t size, bool heldAllowed) {
  Reader r = {p, p + size, true};
  Run    x;
  while (run(&r, heldAllowed, &x)) {}
  return r.ok;
}

static bool step(Reader *r, Step *s) {
  text(r, s->cue);
  s->delay  = number(r);
  s->fade   = number(r);
  s->follow = number(r);
  s->size   = number(r);
  s->runs   = bytes(r, s->size);
  return r->ok && s->delay <= SPAN && s->fade <= SPAN && s->follow <= SPAN && valid(s->runs, s->size, true);
}

static bool program(Reader *r, Program *p) {
  Step s;
  p->loop   = byte(r);
  p->count  = byte(r);
  p->steps  = r->at;
  p->loopAt = 0;
  for (int i = 0; i < p->count && r->ok; i++) {
    if (i == p->loop) p->loopAt = (size_t)(r->at - p->steps);
    if (!step(r, &s)) r->ok = false;
  }
  p->size = (size_t)(r->at - p->steps);
  return r->ok && r->at == r->end && p->count && p->count <= ONWARD && (p->loop >= ONWARD || p->loop < p->count);
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

static uint8_t except(uint8_t client) { return client < STAGE_CLIENTS ? (uint8_t)~(1u << client) : 0xFF; }

static void put(Stage *stage, int a, uint8_t value, uint8_t writer) {
  if (stage->source[a] == value) return;
  stage->source[a] = value;
  stage->owed[a]   = except(writer);
  shine(stage, a);
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
    uint16_t from = wide ? (uint16_t)(stage->source[a] << 8 | stage->source[c->partner]) : stage->source[a];
    cancel(stage, a);
    if (from == to) continue;

    uint32_t span     = (c->flags & (FADES | BAND)) ? length : 0;
    stage->motions[a] = (Motion){from, to, start, span | LIVE | (wide ? PAIRED : 0)};
  }
  memset(stage->wanted, 0, BYTES);
}

static void mention(Stage *stage, const Step *s, bool held, bool valued) {
  Reader r = runs(s);
  Run    x;
  while (run(&r, true, &x)) {
    if (x.values ? !valued : !held) continue;
    for (int i = 0; i < x.count; i++) {
      mark(stage->wanted, x.start + i);
      if (x.values) stage->target[x.start + i] = x.values[i];
    }
  }
}

static void settle(Stage *stage, const Scene *skip) {
  for (int a = 1; a <= SLOTS; a++) {
    if (bit(stage->wanted, a)) stage->target[a] = stage->base[a];
  }

  bool later = false;
  for (const Scene *scene = stage->scenes; scene; scene = scene->next) {
    later = later || scene == skip;
    if (scene == skip) continue;
    Reader r = runs(&scene->current);
    Run    x;
    while (run(&r, true, &x)) {
      for (int i = 0; x.values && i < x.count; i++) {
        int a = x.start + i;
        if (!bit(stage->wanted, a)) continue;
        if (later) unmark(stage->wanted, a);
        else stage->target[a] = x.values[i];
      }
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

static void release(Stage *stage, Scene *scene) {
  unlink(stage, scene);
  free(scene->steps);
  free(scene);
}

static bool wanting(const Scene *scene) {
  return scene->loop == ONWARD && (scene->step + 1) * 2 > scene->count;
}

static bool advancing(const Scene *scene) {
  return scene->current.follow && (scene->step + 1 < scene->count || scene->loop < scene->count);
}

static void enter(Stage *stage, Scene *scene, size_t at, uint8_t index, uint32_t now) {
  Reader r = {scene->steps + at, scene->steps + scene->size, true};
  step(&r, &scene->current);
  scene->step    = index;
  scene->nextAt  = (size_t)(r.at - scene->steps);
  scene->started = now;
  scene->wants   = wanting(scene);

  unlink(stage, scene);
  Scene **link = &stage->scenes;
  while (*link) link = &(*link)->next;
  *link = scene;
}

static void move(Stage *stage, Scene *scene) {
  mention(stage, &scene->current, true, false);
  settle(stage, scene);
  mention(stage, &scene->current, false, true);
  aim(stage, scene->started + scene->current.delay, scene->current.fade);
}

static void load(Scene *scene, const Program *p, uint8_t *steps) {
  memcpy(steps, p->steps, p->size);
  free(scene->steps);
  scene->steps  = steps;
  scene->size   = p->size;
  scene->count  = p->count;
  scene->loop   = p->loop;
  scene->loopAt = p->loopAt;
}

static void play(Stage *stage, const char *id, Reader *r, uint8_t caller, uint32_t now, bool moving) {
  Program p;
  if (!program(r, &p)) return;

  Scene   *scene = find(stage, id);
  bool     fresh = !scene;
  uint8_t *steps = (uint8_t *)malloc(p.size);
  if (fresh) scene = (Scene *)calloc(1, sizeof(Scene));
  if (!steps || !scene) {
    free(steps);
    if (fresh) free(scene);
    return;
  }

  if (!fresh && moving) mention(stage, &scene->current, true, true);
  if (fresh) strcpy(scene->id, id);
  scene->caller = caller;
  load(scene, &p, steps);
  enter(stage, scene, 0, 0, now);
  if (moving) return move(stage, scene);

  Reader values = runs(&scene->current);
  Run    x;
  while (run(&values, true, &x)) {
    for (int i = 0; x.values && i < x.count; i++) cancel(stage, x.start + i);
  }
}

static void more(Stage *stage, Scene *scene, Reader *r, uint8_t caller, uint32_t now) {
  Program p;
  if (!program(r, &p) || !scene || !scene->wants) return;

  Reader s = {p.steps, p.steps + p.size, true};
  Step   found;
  for (uint8_t i = 0; i < p.count; i++) {
    step(&s, &found);
    if (strcmp(found.cue, scene->current.cue)) continue;

    uint8_t *steps = (uint8_t *)malloc(p.size);
    if (!steps) return;
    mention(stage, &scene->current, true, true);
    Reader kept = runs(&found);
    Run    x;
    while (run(&kept, true, &x)) {
      for (int a = x.start; a < x.start + x.count; a++) unmark(stage->wanted, a);
    }
    load(scene, &p, steps);
    scene->current.runs = steps + (found.runs - p.steps);
    scene->current.size = found.size;
    scene->nextAt       = (size_t)(s.at - p.steps);
    scene->step         = i;
    scene->caller       = caller;
    scene->wants        = wanting(scene);
    settle(stage, scene);
    aim(stage, now, scene->current.fade);
    return;
  }
}

static void stop(Stage *stage, Scene *scene, uint32_t fade, uint32_t now) {
  if (!scene) return;
  mention(stage, &scene->current, true, true);
  settle(stage, scene);
  aim(stage, now, fade);
  release(stage, scene);
}

Stage *stage_new(void) {
  Stage *stage = (Stage *)calloc(1, sizeof(Stage));
  if (stage) stage->master = 1;
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
  memcpy(stage->base, stage->source, sizeof(stage->base));
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
    bool fits = a >= 1 && a <= SLOTS && (!(flags & WIDE) || (c.partner >= 1 && c.partner <= SLOTS && c.partner != a)) && c.from <= c.to;
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
  if (byte(&r) != STAGE_FRAME) return false;
  word(&r);
  if (!r.ok || r.at == r.end || !valid(r.at, (size_t)(r.end - r.at), false)) return false;

  Run x;
  while (run(&r, false, &x)) {
    for (int i = 0; i < x.count; i++) {
      int a = x.start + i;
      cancel(stage, a);
      stage->base[a] = x.values[i];
      put(stage, a, x.values[i], writer);
    }
  }
  return true;
}

void stage_command(Stage *stage, const uint8_t *message, size_t length, uint8_t caller, uint32_t now) {
  Reader r = {message, message + length, true};
  if (byte(&r) != STAGE_COMMAND) return;
  word(&r);

  uint8_t action = byte(&r);
  char    id[NAME];
  text(&r, id);
  if (!r.ok || !id[0]) return;

  switch (action) {
    case PLAY: play(stage, id, &r, caller, now, true); break;
    case LAND: play(stage, id, &r, caller, now, false); break;
    case STOP: {
      uint32_t fade = number(&r);
      if (r.ok && r.at == r.end && fade <= SPAN) stop(stage, find(stage, id), fade, now);
      break;
    }
    case MORE: more(stage, find(stage, id), &r, caller, now); break;
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

    bool paired = m->length & PAIRED;
    put(stage, a, (uint8_t)(paired ? value >> 8 : value), NONE);
    if (paired && (stage->channels[a].flags & WIDE)) put(stage, stage->channels[a].partner, (uint8_t)(value & 0xFF), NONE);
  }

  bool   restated = false;
  size_t left     = 0;
  for (Scene *scene = stage->scenes; scene; scene = scene->next) left++;
  for (Scene *scene = stage->scenes; scene && left--;) {
    Scene   *next    = scene->next;
    uint32_t due     = scene->started + scene->current.delay + scene->current.fade + scene->current.follow - 1;
    bool     overdue = scene->current.follow && (int32_t)(now - due) >= 0;
    uint32_t start   = now - due < scene->current.follow ? due : now;
    if (overdue && advancing(scene)) {
      bool last = scene->step + 1 == scene->count;
      enter(stage, scene, last ? scene->loopAt : scene->nextAt, last ? scene->loop : scene->step + 1, start);
      move(stage, scene);
      restated = true;
    } else if (overdue && scene->wants && scene->caller != NONE) {
      scene->caller = NONE;
      restated      = true;
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
    if (advancing(scene)) return true;
  }
  return false;
}

bool stage_forget(Stage *stage, uint8_t client) {
  bool released = false;
  for (Scene *scene = stage->scenes; scene; scene = scene->next) {
    if (scene->caller != client) continue;
    scene->caller = NONE;
    released      = true;
  }
  return released;
}

size_t stage_frame(Stage *stage, uint8_t client, bool whole, uint8_t *out, size_t room) {
  uint8_t mine = (uint8_t)(1u << client);
  size_t  n    = 3;
  if (room < STAGE_FRAME_MAX || client >= STAGE_CLIENTS) return 0;
  out[0] = STAGE_FRAME;
  out[1] = 0;
  out[2] = 0;

  for (int a = 1; a <= SLOTS;) {
    if (!whole && !(stage->owed[a] & mine)) {
      a++;
      continue;
    }
    int start = a;
    while (a <= SLOTS && (whole || (stage->owed[a] & mine))) stage->owed[a++] &= (uint8_t)~mine;
    int count = a - start;
    out[n++]  = (uint8_t)(start & 0xFF);
    out[n++]  = (uint8_t)(start >> 8);
    out[n++]  = (uint8_t)(count & 0xFF);
    out[n++]  = (uint8_t)(count >> 8);
    memcpy(out + n, stage->source + start, (size_t)count);
    n += (size_t)count;
  }

  return n > 3 ? n : 0;
}

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

size_t stage_state(const Stage *stage, uint32_t now, uint8_t *out, size_t room) {
  size_t count = 0;
  for (const Scene *scene = stage->scenes; scene; scene = scene->next) count++;
  size_t need = 4 + 5 + count * (2 * NAME + 17);
  if (!out) return need;
  if (room < need) return 0;

  size_t n = 0;
  out[n++] = STAGE_COMMAND;
  out[n++] = NONE;
  out[n++] = 0;
  out[n++] = 0;
  n += writeNumber(out + n, (uint32_t)count);

  for (const Scene *scene = stage->scenes; scene; scene = scene->next) {
    uint32_t whole   = scene->current.delay + scene->current.fade;
    uint32_t elapsed = now - scene->started;
    n += writeText(out + n, scene->id);
    n += writeText(out + n, scene->current.cue);
    n += writeNumber(out + n, scene->current.delay);
    n += writeNumber(out + n, scene->current.fade);
    n += writeNumber(out + n, elapsed < whole ? elapsed : whole);
    out[n++] = scene->wants;
    out[n++] = scene->caller;
  }
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
  uint8_t out[SLOTS + 1];
  memcpy(source + 1, values, SLOTS);
  for (int a = 1; a <= SLOTS; a++) {
    if (!follower(stage, a)) scaled(stage, source, out, a);
  }
  memcpy(values, out + 1, SLOTS);
}
