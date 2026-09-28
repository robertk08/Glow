#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct Stage Stage;

enum {
  STAGE_SLOTS     = 512,
  STAGE_CLIENTS   = 8,
  STAGE_FRAME     = 0x02,
  STAGE_COMMAND   = 0x05,
  STAGE_MAP       = 0x06,
  STAGE_FRAME_MAX = 3 + 4 * (STAGE_SLOTS / 2 + 1) + STAGE_SLOTS,
};

Stage         *stage_new(void);
void           stage_free(Stage *stage);
void           stage_clear(Stage *stage);
void           stage_map(Stage *stage, const uint8_t *message, size_t length);
void           stage_levels(Stage *stage, float master, bool blackout);
bool           stage_write(Stage *stage, const uint8_t *message, size_t length, uint8_t writer);
void           stage_command(Stage *stage, const uint8_t *message, size_t length, uint8_t caller, uint32_t now);
bool           stage_tick(Stage *stage, uint32_t now);
bool           stage_busy(const Stage *stage);
bool           stage_forget(Stage *stage, uint8_t client);
size_t         stage_frame(Stage *stage, uint8_t client, bool whole, uint8_t *out, size_t room);
size_t         stage_state(const Stage *stage, uint32_t now, uint8_t *out, size_t room);
const uint8_t *stage_source(const Stage *stage);
const uint8_t *stage_output(Stage *stage, int *from, int *to);
void           stage_scale(const Stage *stage, uint8_t *values);

#ifdef __cplusplus
}
#endif
