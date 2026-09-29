#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/arduino-env.sh"

index="https://espressif.github.io/arduino-esp32/package_esp32_index.json"
core="esp32:esp32@3.3.12"
libraries=("esp_dmx@4.1.0" "WebSockets@2.7.2" "ArduinoJson@7.4.3" "HomeSpan@2.1.8")

if ! cli config get board_manager.additional_urls | grep -qF "$index"; then
  cli config add board_manager.additional_urls "$index"
fi

cli core update-index
cli core install "$core"
cli lib update-index
cli lib install "${libraries[@]}"

esp_dmx="$(cygpath -u "$(cli config get directories.user)")/libraries/esp_dmx/src"
PYTHONUTF8=1 bash "$repo/Arduino/patch_esp_dmx.sh" "$esp_dmx"

stamp="$(grep -o 'GLOW_ESP_DMX_PATCHED [0-9]*' "$repo/Arduino/patch_esp_dmx.sh" | tail -1)"
if ! tr -d '\r' < "$esp_dmx/esp_dmx.h" | grep -qx "#define $stamp"; then
  echo "esp_dmx.h does not carry #define $stamp after patching" >&2
  exit 1
fi

echo ""
cli core list
cli lib list
echo "esp_dmx patched: #define $stamp"
