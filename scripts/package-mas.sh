#!/bin/bash

# Builds the Mac App Store submission package. An App Store build differs from
# the Developer ID DMG in three ways that matter: it is sandboxed, it carries a
# provisioning profile, and it is delivered as a signed installer package rather
# than a disk image. Apple notarizes App Store builds itself, so unlike
# `package-macos.sh` this script has no notarization step.

set -euo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$SCRIPT_DIRECTORY/lib/app-bundle.sh"

usage() {
    cat >&2 <<'USAGE'
Usage: package-mas.sh <version> [output-directory]

Environment:
  BUILD_NUMBER                 Bundle build number (default: 1)
  TEAM_ID                      Apple Developer team identifier
  PROVISIONING_PROFILE         Path to the Mac App Store .provisionprofile
  APP_CODESIGN_IDENTITY        "Apple Distribution: ..." identity
  INSTALLER_CODESIGN_IDENTITY  "3rd Party Mac Developer Installer: ..." identity

Setting APP_CODESIGN_IDENTITY requires the other three as well, and produces a
package that App Store Connect accepts. Leaving it unset produces an ad-hoc
signed, sandboxed bundle in an unsigned package, which is useful for checking
sandbox behaviour locally but cannot be submitted.
USAGE
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
    exit 64
fi

readonly VERSION="$1"
readonly BUILD_NUMBER="${BUILD_NUMBER:-1}"
readonly TEAM_ID="${TEAM_ID:-}"
readonly PROVISIONING_PROFILE="${PROVISIONING_PROFILE:-}"
readonly APP_CODESIGN_IDENTITY="${APP_CODESIGN_IDENTITY:-}"
readonly INSTALLER_CODESIGN_IDENTITY="${INSTALLER_CODESIGN_IDENTITY:-}"

validate_version "$VERSION"
validate_build_number "$BUILD_NUMBER"

if [[ -n "$APP_CODESIGN_IDENTITY" ]]; then
    readonly IS_SUBMISSION_BUILD=1

    for required in TEAM_ID PROVISIONING_PROFILE INSTALLER_CODESIGN_IDENTITY; do
        if [[ -z "${!required}" ]]; then
            echo "$required is required when APP_CODESIGN_IDENTITY is set" >&2
            exit 64
        fi
    done

    if [[ ! -f "$PROVISIONING_PROFILE" ]]; then
        echo "Provisioning profile not found: $PROVISIONING_PROFILE" >&2
        exit 66
    fi

    # The team identifier prefixes the application identifier entitlement, so a
    # malformed value fails late inside App Store Connect rather than here.
    if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
        echo "TEAM_ID must be a 10-character Apple Developer team identifier: $TEAM_ID" >&2
        exit 64
    fi
else
    readonly IS_SUBMISSION_BUILD=0
    echo "No APP_CODESIGN_IDENTITY set; building an ad-hoc signed package for local testing only." >&2
fi

readonly ROOT_DIRECTORY="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
readonly REQUESTED_OUTPUT_DIRECTORY="${2:-"$ROOT_DIRECTORY/dist"}"
mkdir -p "$REQUESTED_OUTPUT_DIRECTORY"
readonly OUTPUT_DIRECTORY="$(cd "$REQUESTED_OUTPUT_DIRECTORY" && pwd)"
readonly WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/strongcopy-mas.XXXXXX")"
readonly APP_BUNDLE="$WORK_DIRECTORY/$APP_NAME.app"
readonly ENTITLEMENTS="$WORK_DIRECTORY/$APP_NAME.entitlements"
readonly PKG_PATH="$OUTPUT_DIRECTORY/$APP_NAME-$VERSION.pkg"

cleanup() {
    rm -rf "$WORK_DIRECTORY"
}
trap cleanup EXIT

assemble_app_bundle "$ROOT_DIRECTORY" "$APP_BUNDLE" "$VERSION" "$BUILD_NUMBER"

cp "$ROOT_DIRECTORY/Packaging/$APP_NAME.entitlements" "$ENTITLEMENTS"

if [[ "$IS_SUBMISSION_BUILD" -eq 1 ]]; then
    # Both entitlements have to match the provisioning profile, and the profile
    # has to be in place before signing so its hash covers it.
    /usr/libexec/PlistBuddy \
        -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_IDENTIFIER" \
        -c "Add :com.apple.developer.team-identifier string $TEAM_ID" \
        "$ENTITLEMENTS"

    cp "$PROVISIONING_PROFILE" "$APP_BUNDLE/Contents/embedded.provisionprofile"

    codesign \
        --force \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$APP_CODESIGN_IDENTITY" \
        "$APP_BUNDLE"
else
    codesign \
        --force \
        --entitlements "$ENTITLEMENTS" \
        --sign - \
        "$APP_BUNDLE"
fi
codesign --verify --deep --strict "$APP_BUNDLE"

rm -f "$PKG_PATH"
if [[ "$IS_SUBMISSION_BUILD" -eq 1 ]]; then
    productbuild \
        --component "$APP_BUNDLE" /Applications \
        --sign "$INSTALLER_CODESIGN_IDENTITY" \
        "$PKG_PATH"
    pkgutil --check-signature "$PKG_PATH"
else
    productbuild \
        --component "$APP_BUNDLE" /Applications \
        "$PKG_PATH"
fi

echo "Created $PKG_PATH"
if [[ "$IS_SUBMISSION_BUILD" -eq 0 ]]; then
    echo "This package is unsigned and cannot be uploaded to App Store Connect." >&2
fi
