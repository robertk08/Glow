#include "Access.h"
#include "Guard.h"

#include <Preferences.h>
#include <esp_random.h>
#include <mbedtls/md.h>

namespace Access {
namespace {

const char    *NS              = "access";
const char    *KEY             = "key";
const size_t   KEY_LENGTH      = 32;
const int      FREE_MISSES     = 5;
const uint32_t PAUSE_MS        = 30000;
const int      PAUSE_DOUBLINGS = 5;

Preferences g_nvs;
uint8_t     g_key[KEY_LENGTH];
bool        g_guarded     = false;
int         g_misses      = 0;
uint32_t    g_pausedUntil = 0;

bool unhex(const char *hex, uint8_t *out) {
  if (strlen(hex) != KEY_LENGTH * 2) return false;
  for (size_t i = 0; i < KEY_LENGTH; i++) {
    char  pair[3] = {hex[2 * i], hex[2 * i + 1], '\0'};
    char *end;
    out[i] = (uint8_t)strtoul(pair, &end, 16);
    if (*end) return false;
  }
  return true;
}

void sign(const char *label, const char *nonce, uint8_t *out) {
  char message[64];
  int  n = snprintf(message, sizeof(message), "%s%s", label, nonce);
  mbedtls_md_hmac(mbedtls_md_info_from_type(MBEDTLS_MD_SHA256), g_key, KEY_LENGTH, (const uint8_t *)message, n, out);
}

bool store() {
  return Flash::guarded([] {
    if (g_guarded) return g_nvs.putBytes(KEY, g_key, KEY_LENGTH) == KEY_LENGTH;
    return g_nvs.remove(KEY) || !g_nvs.isKey(KEY);
  });
}

}  // namespace

void begin() {
  if (!g_nvs.begin(NS, false)) {
    Serial.println(F("access: NVS unavailable, a password cannot be stored"));
    return;
  }
  g_guarded = g_nvs.isKey(KEY) && g_nvs.getBytes(KEY, g_key, KEY_LENGTH) == KEY_LENGTH;
}

bool guarded() { return g_guarded; }

uint32_t waiting() {
  if (!g_pausedUntil) return 0;
  int32_t left = (int32_t)(g_pausedUntil - millis());
  if (left <= 0) {
    g_pausedUntil = 0;
    return 0;
  }
  return ((uint32_t)left + 999) / 1000;
}

void fresh(char *token) {
  uint8_t bytes[(TOKEN_SIZE - 1) / 2];
  esp_fill_random(bytes, sizeof(bytes));
  for (size_t i = 0; i < sizeof(bytes); i++) snprintf(token + 2 * i, 3, "%02x", bytes[i]);
}

bool verify(const char *label, const char *nonce, const char *proof) {
  if (!g_guarded) return true;
  if (waiting()) return false;

  uint8_t claimed[KEY_LENGTH] = {};
  uint8_t expected[KEY_LENGTH];
  bool    readable = unhex(proof, claimed);
  sign(label, nonce, expected);

  uint8_t difference = 0;
  for (size_t i = 0; i < KEY_LENGTH; i++) difference |= claimed[i] ^ expected[i];

  if (readable && !difference) {
    g_misses = 0;
    return true;
  }

  g_misses++;
  if (g_misses >= FREE_MISSES) g_pausedUntil = millis() + (PAUSE_MS << min(g_misses - FREE_MISSES, PAUSE_DOUBLINGS));
  Serial.printf("access: wrong password, %d in a row\n", g_misses);
  return false;
}

bool replace(const char *nonce, const char *key) {
  uint8_t next[KEY_LENGTH];
  if (key[0] && !unhex(key, next)) return false;

  if (key[0] && g_guarded) {
    uint8_t pad[KEY_LENGTH];
    sign("wrap", nonce, pad);
    for (size_t i = 0; i < KEY_LENGTH; i++) next[i] ^= pad[i];
  }

  uint8_t held[KEY_LENGTH];
  bool    was = g_guarded;
  memcpy(held, g_key, KEY_LENGTH);

  g_guarded = key[0];
  if (g_guarded) memcpy(g_key, next, KEY_LENGTH);
  if (store()) return true;

  g_guarded = was;
  memcpy(g_key, held, KEY_LENGTH);
  return false;
}

void forget() {
  g_misses      = 0;
  g_pausedUntil = 0;
  if (!g_guarded) {
    Serial.println(F("access: no password is set"));
    return;
  }

  g_guarded = false;
  Serial.println(store() ? F("access: password removed") : F("access: the password could not be removed"));
}

void report() {
  Serial.print(F("key "));
  if (!g_guarded) {
    Serial.println(F("none"));
    return;
  }
  for (size_t i = 0; i < KEY_LENGTH; i++) Serial.printf("%02x", g_key[i]);
  Serial.println();
}

}  // namespace Access
