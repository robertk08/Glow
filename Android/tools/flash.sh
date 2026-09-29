#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/arduino-env.sh"

compile_only=false
port_argument=""
for argument in "$@"; do
  if [[ "$argument" == --compile-only ]]; then
    compile_only=true
  else
    port_argument="$argument"
  fi
done

bash "$repo/Android/tools/sync.sh"

cd "$repo"
if ! git diff --quiet origin/main -- Arduino || [[ -n "$(git ls-files --others -- Arduino)" ]]; then
  echo "Arduino/ differs from origin/main. Only the firmware exactly as on origin/main is flashed:" >&2
  git diff --stat origin/main -- Arduino >&2
  git ls-files --others -- Arduino | sed 's/^/  untracked /' >&2
  exit 1
fi
echo "Firmware at origin/main $(git rev-parse --short origin/main)"

cli compile --fqbn "$fqbn" --build-path "$build" "$(cygpath -w "$repo/Arduino")"

size="$(stat -c %s "$(cygpath -u "$build")/Arduino.ino.bin")"
limit=$((0x200000))
if (( size > limit )); then
  echo "Arduino.ino.bin is $size bytes, app0 holds only $limit" >&2
  exit 1
fi
echo "Arduino.ino.bin is $size of $limit bytes in app0 ($((size * 100 / limit)) %)"

if [[ "$compile_only" == true ]]; then
  exit 0
fi

port="$(pick_port "$port_argument")"
echo "Uploading to $port. The controller restarts and every device disconnects."
if ! cli upload --fqbn "$fqbn" --input-dir "$build" --port "$port" "$(cygpath -w "$repo/Arduino")"; then
  echo "" >&2
  echo "Upload failed. If the port is busy, close every serial monitor (Arduino IDE, monitor.sh) and try again." >&2
  echo "If the bootloader is not reached, bridge GND and ESP_DOWNLOAD on the ESP 2x3 header, upload, then remove the bridge." >&2
  exit 1
fi
