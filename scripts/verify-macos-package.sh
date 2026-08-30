#!/bin/bash

set -euo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$SCRIPT_DIRECTORY/lib/verify.sh"

usage() {
    echo "Usage: $0 <dmg-path> <version> <build-number>" >&2
    echo "Environment: REQUIRE_NOTARIZATION=1 to validate a stapled notarization ticket" >&2
}

if [[ $# -ne 3 ]]; then
    usage
    exit 64
fi

readonly DMG_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
readonly EXPECTED_VERSION="$2"
readonly EXPECTED_BUILD_NUMBER="$3"
readonly EXPECTED_DMG_NAME="$APP_NAME-$EXPECTED_VERSION.dmg"
readonly CHECKSUM_PATH="$DMG_PATH.sha256"
readonly MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/strongcopy-mount.XXXXXX")"
ATTACHED=0

cleanup() {
    if [[ "$ATTACHED" -eq 1 ]]; then
        hdiutil detach "$MOUNT_POINT" -quiet || true
    fi
    rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

if [[ "$(basename "$DMG_PATH")" != "$EXPECTED_DMG_NAME" ]]; then
    echo "Unexpected DMG name: $(basename "$DMG_PATH")" >&2
    exit 1
fi

if [[ ! -f "$CHECKSUM_PATH" ]]; then
    echo "Missing checksum file: $CHECKSUM_PATH" >&2
    exit 1
fi

(
    cd "$(dirname "$DMG_PATH")"
    shasum -a 256 -c "$(basename "$CHECKSUM_PATH")"
)

if [[ "${REQUIRE_NOTARIZATION:-0}" == "1" ]]; then
    xcrun stapler validate "$DMG_PATH"
fi

hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_POINT" -quiet
ATTACHED=1

readonly APP_BUNDLE="$MOUNT_POINT/$APP_NAME.app"
readonly APP_ICON="$APP_BUNDLE/Contents/Resources/AppIcon.icns"
readonly VOLUME_ICON="$MOUNT_POINT/.VolumeIcon.icns"

if [[ ! -L "$MOUNT_POINT/Applications" || "$(readlink "$MOUNT_POINT/Applications")" != "/Applications" ]]; then
    echo "DMG does not contain an Applications shortcut" >&2
    exit 1
fi

assert_app_bundle "$APP_BUNDLE" "$EXPECTED_VERSION" "$EXPECTED_BUILD_NUMBER"

if ! cmp -s "$APP_ICON" "$VOLUME_ICON"; then
    echo "DMG volume icon does not match the app icon" >&2
    exit 1
fi

# The mounted volume advertises its custom icon through the kHasCustomIcon bit
# of the Finder flags, which live in bytes 8-9 of the 32-byte Finder info.
readonly VOLUME_FINDER_INFO="$(xattr -px com.apple.FinderInfo "$MOUNT_POINT" 2>/dev/null | tr -d ' \n')"
readonly VOLUME_FINDER_FLAGS="${VOLUME_FINDER_INFO:16:4}"

if [[ -z "$VOLUME_FINDER_FLAGS" || $((16#$VOLUME_FINDER_FLAGS & 0x0400)) -eq 0 ]]; then
    echo "DMG volume does not have the custom icon flag set" >&2
    exit 1
fi

echo "Verified $DMG_PATH"
