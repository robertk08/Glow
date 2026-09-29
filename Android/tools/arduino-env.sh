repo="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
cli_exe="$(cygpath -u "$LOCALAPPDATA")/Programs/Arduino IDE/resources/app/lib/backend/resources/arduino-cli.exe"
cli_config="$(cygpath -w "$USERPROFILE/.arduinoIDE/arduino-cli.yaml")"
fqbn="esp32:esp32:esp32s3:CDCOnBoot=cdc,FlashSize=8M,PartitionScheme=custom"
build="$(cygpath -w "$LOCALAPPDATA/Glow/build")"

if [[ ! -x "$cli_exe" ]]; then
  echo "arduino-cli from the Arduino IDE not found at $cli_exe" >&2
  exit 1
fi

cli() {
  "$cli_exe" --config-file "$cli_config" "$@"
}

pick_port() {
  if [[ -n "${1:-}" ]]; then
    echo "$1"
    return
  fi
  local ports
  mapfile -t ports < <(cli board list --format json | python3 -c '
import json, sys
for entry in json.load(sys.stdin).get("detected_ports", []):
    port = entry.get("port", {})
    if port.get("protocol") == "serial":
        boards = ", ".join(board.get("name", "") for board in entry.get("matching_boards", []))
        print(port.get("address", "") + "\t" + (boards or port.get("protocol_label", "")))
')
  if (( ${#ports[@]} == 0 )); then
    echo "No serial port found. Is the controller connected by USB?" >&2
    exit 1
  fi
  if (( ${#ports[@]} == 1 )); then
    echo "${ports[0]%%$'\t'*}"
    return
  fi
  if [[ ! -t 0 ]]; then
    echo "Several serial ports found. Pass one as argument:" >&2
    printf '  %s\n' "${ports[@]}" >&2
    exit 1
  fi
  local i
  for i in "${!ports[@]}"; do
    echo "  $((i + 1))) ${ports[$i]}" >&2
  done
  local choice
  read -rp "Port number: " choice
  if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#ports[@]} )); then
    echo "No such port" >&2
    exit 1
  fi
  echo "${ports[$((choice - 1))]%%$'\t'*}"
}
