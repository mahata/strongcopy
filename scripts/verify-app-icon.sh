#!/bin/bash

set -euo pipefail

readonly EXPECTED_MEMBERS=(
    "icon_16x16.png"
    "icon_16x16@2x.png"
    "icon_32x32.png"
    "icon_32x32@2x.png"
    "icon_128x128.png"
    "icon_128x128@2x.png"
    "icon_256x256.png"
    "icon_256x256@2x.png"
    "icon_512x512.png"
    "icon_512x512@2x.png"
)

usage() {
    echo "Usage: $0 <icns-path>" >&2
}

if [[ $# -ne 1 ]]; then
    usage
    exit 64
fi

readonly ICNS_PATH="$1"

if [[ ! -f "$ICNS_PATH" ]]; then
    echo "Missing icon: $ICNS_PATH" >&2
    exit 1
fi

readonly WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/strongcopy-icon.XXXXXX")"

cleanup() {
    rm -rf "$WORK_DIRECTORY"
}
trap cleanup EXIT

readonly ICONSET_DIRECTORY="$WORK_DIRECTORY/AppIcon.iconset"
iconutil --convert iconset --output "$ICONSET_DIRECTORY" "$ICNS_PATH"

for member in "${EXPECTED_MEMBERS[@]}"; do
    if [[ ! -f "$ICONSET_DIRECTORY/$member" ]]; then
        echo "Icon is missing $member" >&2
        exit 1
    fi
done

assert_pixel_size() {
    local member="$1"
    local expected="$2"
    local width
    local height
    width="$(sips -g pixelWidth "$ICONSET_DIRECTORY/$member" | awk '/pixelWidth/ { print $2 }')"
    height="$(sips -g pixelHeight "$ICONSET_DIRECTORY/$member" | awk '/pixelHeight/ { print $2 }')"

    if [[ "$width" != "$expected" || "$height" != "$expected" ]]; then
        echo "Unexpected $member size: expected ${expected}x${expected}, got ${width}x${height}" >&2
        exit 1
    fi
}

assert_pixel_size "icon_16x16.png" 16
assert_pixel_size "icon_512x512@2x.png" 1024

echo "Verified $ICNS_PATH"
