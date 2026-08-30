#!/bin/bash

set -euo pipefail

readonly EXPECTED_MEMBERS=(
    "icon_16x16.png:16"
    "icon_16x16@2x.png:32"
    "icon_32x32.png:32"
    "icon_32x32@2x.png:64"
    "icon_128x128.png:128"
    "icon_128x128@2x.png:256"
    "icon_256x256.png:256"
    "icon_256x256@2x.png:512"
    "icon_512x512.png:512"
    "icon_512x512@2x.png:1024"
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

assert_member() {
    local member="$1"
    local expected="$2"
    local path="$ICONSET_DIRECTORY/$member"

    if [[ ! -f "$path" ]]; then
        echo "Icon is missing $member" >&2
        exit 1
    fi

    local width
    local height
    width="$(sips -g pixelWidth "$path" | awk '/pixelWidth/ { print $2 }')"
    height="$(sips -g pixelHeight "$path" | awk '/pixelHeight/ { print $2 }')"

    if [[ "$width" != "$expected" || "$height" != "$expected" ]]; then
        echo "Unexpected $member size: expected ${expected}x${expected}, got ${width}x${height}" >&2
        exit 1
    fi
}

for member in "${EXPECTED_MEMBERS[@]}"; do
    assert_member "${member%%:*}" "${member##*:}"
done

echo "Verified $ICNS_PATH"
