#!/bin/bash

set -euo pipefail

readonly APP_NAME="Strongcopy"
readonly BUNDLE_IDENTIFIER="org.mahata.strongcopy"
readonly MINIMUM_MACOS_VERSION="13.0"

usage() {
    echo "Usage: $0 <version> [output-directory]" >&2
    echo "Environment: BUILD_NUMBER (default: 1), CODESIGN_IDENTITY (default: ad hoc)" >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
    exit 64
fi

readonly VERSION="$1"
readonly BUILD_NUMBER="${BUILD_NUMBER:-1}"
readonly CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must use MAJOR.MINOR.PATCH format: $VERSION" >&2
    exit 64
fi

if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "BUILD_NUMBER must be a positive integer: $BUILD_NUMBER" >&2
    exit 64
fi

readonly ROOT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REQUESTED_OUTPUT_DIRECTORY="${2:-"$ROOT_DIRECTORY/dist"}"
mkdir -p "$REQUESTED_OUTPUT_DIRECTORY"
readonly OUTPUT_DIRECTORY="$(cd "$REQUESTED_OUTPUT_DIRECTORY" && pwd)"
readonly SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
readonly WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/strongcopy-package.XXXXXX")"
readonly APP_BUNDLE="$WORK_DIRECTORY/$APP_NAME.app"
readonly APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
readonly DMG_ROOT="$WORK_DIRECTORY/dmg"
readonly DMG_PATH="$OUTPUT_DIRECTORY/$APP_NAME-$VERSION.dmg"
readonly CHECKSUM_PATH="$DMG_PATH.sha256"

cleanup() {
    rm -rf "$WORK_DIRECTORY"
}
trap cleanup EXIT

build_architecture() {
    local architecture="$1"
    local scratch_path="$ROOT_DIRECTORY/.build/package-$architecture"
    local target="$architecture-apple-macosx$MINIMUM_MACOS_VERSION"

    swift build \
        --package-path "$ROOT_DIRECTORY" \
        --configuration release \
        --scratch-path "$scratch_path" \
        --triple "$target" \
        --sdk "$SDK_PATH" >&2

    swift build \
        --package-path "$ROOT_DIRECTORY" \
        --configuration release \
        --scratch-path "$scratch_path" \
        --triple "$target" \
        --sdk "$SDK_PATH" \
        --show-bin-path
}

echo "Building $APP_NAME $VERSION for arm64..."
readonly ARM64_BINARY_DIRECTORY="$(build_architecture arm64)"
echo "Building $APP_NAME $VERSION for x86_64..."
readonly X86_64_BINARY_DIRECTORY="$(build_architecture x86_64)"

mkdir -p "$(dirname "$APP_EXECUTABLE")"
lipo -create \
    "$ARM64_BINARY_DIRECTORY/$APP_NAME" \
    "$X86_64_BINARY_DIRECTORY/$APP_NAME" \
    -output "$APP_EXECUTABLE"
chmod 755 "$APP_EXECUTABLE"

cp "$ROOT_DIRECTORY/Packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP_BUNDLE"
else
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$CODESIGN_IDENTITY" \
        "$APP_BUNDLE"
fi
codesign --verify --deep --strict "$APP_BUNDLE"

mkdir -p "$DMG_ROOT"
ditto "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"

rm -f "$DMG_PATH" "$CHECKSUM_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_ROOT" \
    -format UDZO \
    -ov \
    "$DMG_PATH"

if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
    codesign \
        --force \
        --timestamp \
        --sign "$CODESIGN_IDENTITY" \
        "$DMG_PATH"
    codesign --verify --strict "$DMG_PATH"
fi

(
    cd "$OUTPUT_DIRECTORY"
    shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

echo "Created $DMG_PATH"
echo "Created $CHECKSUM_PATH"
