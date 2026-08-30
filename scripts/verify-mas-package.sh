#!/bin/bash

# Checks a Mac App Store package before it is uploaded, because App Store
# Connect rejects a bad build minutes after the upload rather than at build
# time, and a rejected build number cannot be reused.

set -euo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$SCRIPT_DIRECTORY/lib/verify.sh"

usage() {
    echo "Usage: $0 <pkg-path> <version> <build-number>" >&2
    echo "Environment: REQUIRE_SUBMISSION_SIGNING=1 to validate distribution signing" >&2
}

if [[ $# -ne 3 ]]; then
    usage
    exit 64
fi

readonly PKG_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
readonly EXPECTED_VERSION="$2"
readonly EXPECTED_BUILD_NUMBER="$3"
readonly EXPECTED_PKG_NAME="$APP_NAME-$EXPECTED_VERSION.pkg"
readonly WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/strongcopy-verify-mas.XXXXXX")"
readonly EXPANDED_DIRECTORY="$WORK_DIRECTORY/expanded"
readonly ENTITLEMENTS="$WORK_DIRECTORY/entitlements.plist"

cleanup() {
    rm -rf "$WORK_DIRECTORY"
}
trap cleanup EXIT

if [[ "$(basename "$PKG_PATH")" != "$EXPECTED_PKG_NAME" ]]; then
    echo "Unexpected package name: $(basename "$PKG_PATH")" >&2
    exit 1
fi

if [[ "${REQUIRE_SUBMISSION_SIGNING:-0}" == "1" ]]; then
    pkgutil --check-signature "$PKG_PATH"
fi

pkgutil --expand-full "$PKG_PATH" "$EXPANDED_DIRECTORY"

readonly APP_BUNDLE="$(find "$EXPANDED_DIRECTORY" -type d -name "$APP_NAME.app" -print -quit)"

if [[ -z "$APP_BUNDLE" ]]; then
    echo "Package does not contain $APP_NAME.app" >&2
    exit 1
fi

readonly INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"

assert_app_bundle "$APP_BUNDLE" "$EXPECTED_VERSION" "$EXPECTED_BUILD_NUMBER"

# App Store Connect rejects an upload that declares no category, and asks the
# export compliance question on every build that does not answer it up front.
assert_plist_value "$INFO_PLIST" LSApplicationCategoryType public.app-category.utilities
assert_plist_value "$INFO_PLIST" ITSAppUsesNonExemptEncryption false

codesign --display --entitlements "$ENTITLEMENTS" --xml "$APP_BUNDLE" 2>/dev/null

assert_plist_value "$ENTITLEMENTS" "com.apple.security.app-sandbox" true

if [[ "${REQUIRE_SUBMISSION_SIGNING:-0}" == "1" ]]; then
    if [[ ! -f "$APP_BUNDLE/Contents/embedded.provisionprofile" ]]; then
        echo "Submission build is missing Contents/embedded.provisionprofile" >&2
        exit 1
    fi

    # Assigned before being made read-only so that `set -e` still sees a missing
    # entitlement: `readonly VAR="$(...)"` masks the exit status of the
    # substitution and would leave the variable silently empty.
    APPLICATION_IDENTIFIER="$(/usr/libexec/PlistBuddy -c "Print :com.apple.application-identifier" "$ENTITLEMENTS")"
    TEAM_IDENTIFIER="$(/usr/libexec/PlistBuddy -c "Print :com.apple.developer.team-identifier" "$ENTITLEMENTS")"
    readonly APPLICATION_IDENTIFIER TEAM_IDENTIFIER

    if [[ ! "$TEAM_IDENTIFIER" =~ ^[A-Z0-9]{10}$ ]]; then
        echo "Team identifier entitlement is not a 10-character team identifier: $TEAM_IDENTIFIER" >&2
        exit 1
    fi

    # App Store Connect reads the application identifier as the team identifier
    # joined to the bundle identifier, so comparing the whole string catches a
    # prefix that disagrees with the team identifier entitlement as well as a
    # bundle identifier that is merely a suffix of the expected one.
    if [[ "$APPLICATION_IDENTIFIER" != "$TEAM_IDENTIFIER.$BUNDLE_IDENTIFIER" ]]; then
        echo "Unexpected application identifier entitlement: expected '$TEAM_IDENTIFIER.$BUNDLE_IDENTIFIER', got '$APPLICATION_IDENTIFIER'" >&2
        exit 1
    fi
fi

echo "Verified $PKG_PATH"
