#!/usr/bin/env bash

set -euo pipefail

xcodebuild build \
  -project Cue.xcodeproj \
  -scheme Cue \
  -destination "platform=macOS,arch=arm64"
