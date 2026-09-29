#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/arduino-env.sh"

port="$(pick_port "${1:-}")"
echo "Serial console on $port at 115200. Commands: net, setup, forget, home, unpair, password, key. Ctrl+C quits."
echo "This holds the port. Quit it before flashing."
cli monitor --port "$port" --config baudrate=115200
