#!/usr/bin/env bash

set -euo pipefail

configuration="${1:-Debug}"

case "$configuration" in
    Debug|Release) ;;
    *)
        echo "Usage: $0 [Debug|Release]" >&2
        exit 2
        ;;
esac

xcodebuild test \
  -project Cue.xcodeproj \
  -scheme Cue \
  -configuration "$configuration" \
  -destination "platform=macOS,arch=arm64" \
  ARCHS=arm64 \
  ENABLE_TESTABILITY=YES
