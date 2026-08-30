#!/bin/bash

# Shared helpers for assembling the Strongcopy app bundle. Both the Developer ID
# and the Mac App Store packaging scripts source this file so the bundle they
# sign is built the same way; only the signing and the delivery format differ.

readonly APP_NAME="Strongcopy"
readonly BUNDLE_IDENTIFIER="org.mahata.strongcopy"
readonly MINIMUM_MACOS_VERSION="13.0"

validate_version() {
    local version="$1"

    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Version must use MAJOR.MINOR.PATCH format: $version" >&2
        exit 64
    fi
}

validate_build_number() {
    local build_number="$1"

    if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
        echo "BUILD_NUMBER must be a positive integer: $build_number" >&2
        exit 64
    fi
}

# Builds one architecture and echoes the directory holding its binary. Build
# output goes to stderr because callers read stdout for that directory.
build_architecture() {
    local root_directory="$1"
    local architecture="$2"
    local sdk_path="$3"
    local scratch_path="$root_directory/.build/package-$architecture"
    local target="$architecture-apple-macosx$MINIMUM_MACOS_VERSION"

    swift build \
        --package-path "$root_directory" \
        --configuration release \
        --scratch-path "$scratch_path" \
        --triple "$target" \
        --sdk "$sdk_path" \
        --product "$APP_NAME" >&2

    swift build \
        --package-path "$root_directory" \
        --configuration release \
        --scratch-path "$scratch_path" \
        --triple "$target" \
        --sdk "$sdk_path" \
        --product "$APP_NAME" \
        --show-bin-path
}

# Writes an unsigned universal app bundle carrying the Info.plist and icon.
assemble_app_bundle() {
    local root_directory="$1"
    local app_bundle="$2"
    local version="$3"
    local build_number="$4"

    local sdk_path
    sdk_path="$(xcrun --sdk macosx --show-sdk-path)"

    echo "Building $APP_NAME $version for arm64..."
    local arm64_binary_directory
    arm64_binary_directory="$(build_architecture "$root_directory" arm64 "$sdk_path")"
    echo "Building $APP_NAME $version for x86_64..."
    local x86_64_binary_directory
    x86_64_binary_directory="$(build_architecture "$root_directory" x86_64 "$sdk_path")"

    local app_executable="$app_bundle/Contents/MacOS/$APP_NAME"
    mkdir -p "$(dirname "$app_executable")"
    lipo -create \
        "$arm64_binary_directory/$APP_NAME" \
        "$x86_64_binary_directory/$APP_NAME" \
        -output "$app_executable"
    chmod 755 "$app_executable"

    # Version and build number are per-build, so they are written over the
    # template's placeholders. Everything else, the bundle identifier included,
    # is already correct in Packaging/Info.plist and is left alone.
    local info_plist="$app_bundle/Contents/Info.plist"
    cp "$root_directory/Packaging/Info.plist" "$info_plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$info_plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$info_plist"

    echo "Generating the app icon..."
    local app_icon="$app_bundle/Contents/Resources/AppIcon.icns"
    mkdir -p "$(dirname "$app_icon")"
    swift run \
        --package-path "$root_directory" \
        --configuration release \
        --scratch-path "$root_directory/.build/package-icon" \
        GenerateAppIcon "$app_icon"
}
