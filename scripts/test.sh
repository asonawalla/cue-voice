#!/usr/bin/env bash

set -euo pipefail

xcodebuild test \
  -project Cue.xcodeproj \
  -scheme Cue \
  -configuration "${1:-Debug}" \
  -destination "platform=macOS,arch=arm64" \
  ARCHS=arm64 \
  ENABLE_TESTABILITY=YES
