#!/usr/bin/env bash

set -euo pipefail

source_app=${1:?Pass the built Cue.app path as the first argument.}
destination=/Applications/Cue.app
staged_destination=/Applications/.Cue.app.installing
script_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
designated_requirement="$script_directory/../build-support/CueDesignatedRequirement.txt"

if [[ ! -d "$source_app" ]]; then
    echo "Cue installer could not find the built app at $source_app" >&2
    exit 1
fi

if [[ ! -f "$designated_requirement" ]]; then
    echo "Cue installer could not find its signing requirement at $designated_requirement" >&2
    exit 1
fi

cleanup() {
    /bin/rm -rf "$staged_destination"
}
trap cleanup EXIT

/bin/rm -rf "$staged_destination"
/usr/bin/ditto "$source_app" "$staged_destination"
shopt -s nullglob
for nested_code in "$staged_destination"/Contents/MacOS/*.dylib; do
    /usr/bin/codesign --force --sign - "$nested_code"
done
shopt -u nullglob
/usr/bin/codesign --force --sign - \
    --preserve-metadata=entitlements \
    --requirements "$designated_requirement" \
    "$staged_destination"
/usr/bin/codesign --verify --deep --strict "$staged_destination"

/usr/bin/pkill -x Cue >/dev/null 2>&1 || true
/bin/rm -rf "$destination"
/bin/mv "$staged_destination" "$destination"

/usr/bin/codesign --verify --deep --strict "$destination"
/usr/bin/open "$destination"

echo "Installed and launched $destination"
