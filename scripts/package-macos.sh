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
readonly APP_ICON="$APP_BUNDLE/Contents/Resources/AppIcon.icns"
readonly DMG_ROOT="$WORK_DIRECTORY/dmg"
readonly STAGING_DMG_PATH="$WORK_DIRECTORY/staging.dmg"
readonly STAGING_MOUNT_POINT="$WORK_DIRECTORY/volume"
readonly DMG_PATH="$OUTPUT_DIRECTORY/$APP_NAME-$VERSION.dmg"
readonly CHECKSUM_PATH="$DMG_PATH.sha256"
STAGING_VOLUME_ATTACHED=0

detach_staging_volume() {
    local attempt
    for attempt in 1 2 3; do
        if hdiutil detach "$STAGING_MOUNT_POINT" -quiet; then
            return 0
        fi
        sleep 2
    done

    hdiutil detach "$STAGING_MOUNT_POINT" -force -quiet
}

cleanup() {
    if [[ "$STAGING_VOLUME_ATTACHED" -eq 1 ]]; then
        # Removing the work directory while the volume is still attached would
        # delete through the mount point into the mounted volume itself.
        if ! detach_staging_volume; then
            echo "Could not detach $STAGING_MOUNT_POINT; leaving $WORK_DIRECTORY in place" >&2
            return
        fi
    fi

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

echo "Generating the app icon..."
mkdir -p "$(dirname "$APP_ICON")"
swift "$ROOT_DIRECTORY/scripts/generate-app-icon.swift" "$APP_ICON"

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
cp "$APP_ICON" "$DMG_ROOT/.VolumeIcon.icns"

rm -f "$DMG_PATH" "$CHECKSUM_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_ROOT" \
    -format UDRW \
    -ov \
    "$STAGING_DMG_PATH"

# hdiutil does not carry Finder info from the source folder, so the volume needs
# the kHasCustomIcon bit (byte 8 of the 32-byte Finder info) set while mounted
# for Finder to display .VolumeIcon.icns.
mkdir -p "$STAGING_MOUNT_POINT"
hdiutil attach "$STAGING_DMG_PATH" -nobrowse -mountpoint "$STAGING_MOUNT_POINT" -quiet
STAGING_VOLUME_ATTACHED=1
xattr -wx com.apple.FinderInfo \
    "0000000000000000040000000000000000000000000000000000000000000000" \
    "$STAGING_MOUNT_POINT"
detach_staging_volume
STAGING_VOLUME_ATTACHED=0

hdiutil convert "$STAGING_DMG_PATH" -format UDZO -o "$DMG_PATH"

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
