#!/usr/bin/env bash
# Make esp_dmx 4.1.0 compile against ESP-IDF >= 5.3 (arduino-esp32 core >= 3.1).
# Implements https://github.com/gunstr/esp_dmx/tree/fix_for_esp-idf_5.3
# Then force the DMX ISR into IRAM, which Kconfig would do under ESP-IDF but
# cannot under Arduino, and without which a flash access corrupts the packet
# that is on the wire.
# Safe to re-run: it backs up once and skips if already patched.
set -euo pipefail

SRC="${1:-$HOME/Documents/Arduino/libraries/esp_dmx/src}"
UART_C="$SRC/dmx/hal/uart.c"

if [[ ! -f "$UART_C" ]]; then
  echo "not found: $UART_C" >&2
  echo "Install esp_dmx via the Arduino IDE Library Manager first," >&2
  echo "or pass the path to its src directory as an argument." >&2
  exit 1
fi

if grep -q "ESP_IDF_VERSION_VAL(5, 3, 0)" "$UART_C"; then
  echo "already patched: $UART_C"
else
  [[ -f "$UART_C.orig" ]] || cp "$UART_C" "$UART_C.orig"

  python3 - "$UART_C" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()

def guard(call, idx):
    return (f'#if ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(5, 3, 0)\n'
            f'    {call}((periph_module_t)({idx} + 1));\n'
            f'#else\n'
            f'    {call}(uart_periph_signal[{idx}].module);\n'
            f'#endif')

replacements = [
    ('  periph_module_enable(uart_periph_signal[dmx_num].module);',
     guard('periph_module_enable', 'dmx_num')),
    ('    periph_module_reset(uart_periph_signal[dmx_num].module);',
     guard('periph_module_reset', 'dmx_num')),
    ('    periph_module_disable(uart_periph_signal[uart->num].module);',
     guard('periph_module_disable', 'uart->num')),
]

for old, new in replacements:
    if old not in src:
        sys.exit(f"pattern not found, library version changed?\n  {old.strip()}")
    src = src.replace(old, new)

open(path, 'w').write(src)
PY

  echo "patched: $UART_C"
  grep -c "ESP_IDF_VERSION_VAL(5, 3, 0)" "$UART_C" | xargs -I{} echo "{} guard(s) inserted (expect 4)"
fi

OLD_GUARD='#if defined(CONFIG_DMX_ISR_IN_IRAM) || ESP_IDF_VERSION_MAJOR < 5'
NEW_GUARD='#if 1 || defined(CONFIG_DMX_ISR_IN_IRAM)'

for f in "$SRC/esp_dmx.h" "$SRC/dmx/include/service.h" "$SRC/dmx/sniffer.h"; do
  if [[ ! -f "$f" ]]; then
    echo "not found: $f" >&2
    exit 1
  fi

  if grep -qF "$NEW_GUARD" "$f"; then
    echo "already in IRAM: $f"
    continue
  fi

  if ! grep -qF "$OLD_GUARD" "$f"; then
    echo "guard not found, library version changed? $f" >&2
    exit 1
  fi

  [[ -f "$f.orig" ]] || cp "$f" "$f.orig"
  python3 - "$f" "$OLD_GUARD" "$NEW_GUARD" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()
open(path, 'w').write(src.replace(old, new))
PY
  echo "forced into IRAM: $f"
done

echo "backups end in .orig, restore them to undo"
