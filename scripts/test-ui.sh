#!/usr/bin/env bash

set -euo pipefail

xcodebuild test \
  -project Cue.xcodeproj \
  -scheme CueUI \
  -destination "platform=macOS" \
  -only-testing:CueUITests
