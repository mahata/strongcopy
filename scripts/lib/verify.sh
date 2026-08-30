#!/bin/bash

# Shared assertions for checking a packaged Strongcopy bundle. Both the
# Developer ID and the Mac App Store verifiers source this file, so the two
# check the same bundle the same way and differ only in how they get at it and
# in what their own distribution channel additionally requires.
#
# The expected values live here rather than being read from
# `lib/app-bundle.sh`, so that a verifier still fails when packaging writes
# something other than what the project intends.

readonly APP_NAME="Strongcopy"
readonly BUNDLE_IDENTIFIER="org.mahata.strongcopy"
readonly MINIMUM_SYSTEM_VERSION="13.0"
readonly VERIFY_LIB_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

assert_plist_value() {
    local plist="$1"
    local key="$2"
    local expected="$3"
    local actual
    actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist")"

    if [[ "$actual" != "$expected" ]]; then
        echo "Unexpected $key: expected '$expected', got '$actual'" >&2
        exit 1
    fi
}

assert_universal_binary() {
    local executable="$1"
    local architectures
    architectures="$(lipo -archs "$executable")"

    local architecture
    for architecture in arm64 x86_64; do
        if [[ " $architectures " != *" $architecture "* ]]; then
            echo "Missing $architecture executable slice: $architectures" >&2
            exit 1
        fi
    done

    if [[ "$(wc -w <<< "$architectures" | tr -d ' ')" -ne 2 ]]; then
        echo "Unexpected executable architectures: $architectures" >&2
        exit 1
    fi
}

# Everything both distributions require of the bundle itself: the identity and
# version it declares, a complete icon, both architectures, and a valid
# signature.
assert_app_bundle() {
    local app_bundle="$1"
    local expected_version="$2"
    local expected_build_number="$3"
    local info_plist="$app_bundle/Contents/Info.plist"

    assert_plist_value "$info_plist" CFBundleIdentifier "$BUNDLE_IDENTIFIER"
    assert_plist_value "$info_plist" CFBundleShortVersionString "$expected_version"
    assert_plist_value "$info_plist" CFBundleVersion "$expected_build_number"
    assert_plist_value "$info_plist" CFBundlePackageType APPL
    assert_plist_value "$info_plist" LSMinimumSystemVersion "$MINIMUM_SYSTEM_VERSION"
    assert_plist_value "$info_plist" LSUIElement true
    assert_plist_value "$info_plist" CFBundleIconFile AppIcon

    "$VERIFY_LIB_DIRECTORY/../verify-app-icon.sh" "$app_bundle/Contents/Resources/AppIcon.icns"
    assert_universal_binary "$app_bundle/Contents/MacOS/$APP_NAME"
    codesign --verify --deep --strict "$app_bundle"
}
