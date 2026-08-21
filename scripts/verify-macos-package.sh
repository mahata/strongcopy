#!/bin/bash

set -euo pipefail

readonly APP_NAME="Strongcopy"
readonly BUNDLE_IDENTIFIER="org.mahata.strongcopy"

usage() {
    echo "Usage: $0 <dmg-path> <version> <build-number>" >&2
    echo "Environment: REQUIRE_NOTARIZATION=1 to validate a stapled notarization ticket" >&2
}

if [[ $# -ne 3 ]]; then
    usage
    exit 64
fi

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
readonly INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
readonly APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
readonly APP_ICON="$APP_BUNDLE/Contents/Resources/AppIcon.icns"
readonly VOLUME_ICON="$MOUNT_POINT/.VolumeIcon.icns"

if [[ ! -L "$MOUNT_POINT/Applications" || "$(readlink "$MOUNT_POINT/Applications")" != "/Applications" ]]; then
    echo "DMG does not contain an Applications shortcut" >&2
    exit 1
fi

assert_plist_value() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST")"

    if [[ "$actual" != "$expected" ]]; then
        echo "Unexpected $key: expected '$expected', got '$actual'" >&2
        exit 1
    fi
}

assert_plist_value CFBundleIdentifier "$BUNDLE_IDENTIFIER"
assert_plist_value CFBundleShortVersionString "$EXPECTED_VERSION"
assert_plist_value CFBundleVersion "$EXPECTED_BUILD_NUMBER"
assert_plist_value CFBundlePackageType APPL
assert_plist_value LSMinimumSystemVersion 13.0
assert_plist_value LSUIElement true
assert_plist_value CFBundleIconFile AppIcon

"$SCRIPT_DIRECTORY/verify-app-icon.sh" "$APP_ICON"

if ! cmp -s "$APP_ICON" "$VOLUME_ICON"; then
    echo "DMG volume icon does not match the app icon" >&2
    exit 1
fi

# The mounted volume advertises its custom icon through the kHasCustomIcon bit
# of the Finder flags, which live in bytes 8-9 of the 32-byte Finder info.
readonly VOLUME_FINDER_INFO="$(xattr -px com.apple.FinderInfo "$MOUNT_POINT" 2>/dev/null | tr -d ' \n')"
readonly VOLUME_FINDER_FLAGS="${VOLUME_FINDER_INFO:16:2}"

if [[ -z "$VOLUME_FINDER_FLAGS" || $((16#$VOLUME_FINDER_FLAGS & 0x04)) -eq 0 ]]; then
    echo "DMG volume does not have the custom icon flag set" >&2
    exit 1
fi

readonly ARCHITECTURES="$(lipo -archs "$APP_EXECUTABLE")"
for architecture in arm64 x86_64; do
    if [[ " $ARCHITECTURES " != *" $architecture "* ]]; then
        echo "Missing $architecture executable slice: $ARCHITECTURES" >&2
        exit 1
    fi
done

if [[ "$(wc -w <<< "$ARCHITECTURES" | tr -d ' ')" -ne 2 ]]; then
    echo "Unexpected executable architectures: $ARCHITECTURES" >&2
    exit 1
fi

codesign --verify --deep --strict "$APP_BUNDLE"
echo "Verified $DMG_PATH"
