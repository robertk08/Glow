#!/bin/zsh
host=${1:-glow.local}
port=$(ls /dev/cu.usbmodem* 2>/dev/null | head -1)
key=""

if [[ -n $port ]]; then
	stty -f $port 115200 raw -echo
	exec 3<>$port
	print -u 3 key
	while IFS= read -t 2 -u 3 line; do
		line=${line%$'\r'}
		if [[ $line == "key "* ]]; then
			key=${line#key }
			break
		fi
	done
	exec 3<&-
fi

[[ $key == none ]] && key=""
TEST_RUNNER_GLOW_CONTROLLER=$host TEST_RUNNER_GLOW_KEY=$key exec xcodebuild test -scheme Glow -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:GlowTests/ControllerTests -collect-test-diagnostics never
