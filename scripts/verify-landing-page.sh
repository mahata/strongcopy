#!/bin/bash

set -euo pipefail

readonly CANONICAL_URL="https://strongcopy.mahata.org/"
readonly RELEASES_URL="https://github.com/mahata/strongcopy/releases/latest"
readonly REQUIRED_FILES=(
    "index.html"
    "styles.css"
    "icon.svg"
    "favicon.svg"
    "robots.txt"
    "sitemap.xml"
)

usage() {
    echo "Usage: $0 [site-directory]" >&2
}

if [[ $# -gt 1 ]]; then
    usage
    exit 64
fi

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SITE_DIRECTORY="${1:-$SCRIPT_DIRECTORY/../web}"

if [[ ! -d "$SITE_DIRECTORY" ]]; then
    echo "Missing site directory: $SITE_DIRECTORY" >&2
    exit 1
fi

for required_file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$SITE_DIRECTORY/$required_file" ]]; then
        echo "Missing $required_file in $SITE_DIRECTORY" >&2
        exit 1
    fi
done

readonly PAGE="$SITE_DIRECTORY/index.html"

assert_contains() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    if ! grep -qE "$pattern" "$file"; then
        echo "$(basename "$file") is missing $description" >&2
        exit 1
    fi
}

refute_contains() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    if grep -qE "$pattern" "$file"; then
        echo "$(basename "$file") $description" >&2
        exit 1
    fi
}

assert_contains "$PAGE" '<html[^>]+lang="en"' 'a language on the html element'
assert_contains "$PAGE" '<meta[^>]+name="viewport"' 'a viewport meta tag'
assert_contains "$PAGE" '<meta[^>]+name="description"' 'a description meta tag'
assert_contains "$PAGE" '<meta[^>]+name="theme-color"' 'a theme-color meta tag'
assert_contains "$PAGE" "<link[^>]+rel=\"canonical\"[^>]+href=\"$CANONICAL_URL\"" \
    "a canonical link to $CANONICAL_URL"
assert_contains "$PAGE" '<meta[^>]+property="og:title"' 'an og:title meta tag'
assert_contains "$PAGE" '<meta[^>]+property="og:description"' 'an og:description meta tag'
assert_contains "$PAGE" "<meta[^>]+property=\"og:url\"[^>]+content=\"$CANONICAL_URL\"" \
    "an og:url meta tag pointing at $CANONICAL_URL"
assert_contains "$PAGE" "href=\"$RELEASES_URL\"" "a download link to $RELEASES_URL"

# The page promises a build-free, third-party-free download. Loading a remote
# stylesheet, script, font, or image would quietly break that promise.
refute_contains "$PAGE" '<script' 'ships JavaScript, but the page is meant to be script-free'
refute_contains "$PAGE" 'src="(https?:)?//' 'loads a remote resource through a src attribute'
refute_contains "$PAGE" '<link[^>]+rel="stylesheet"[^>]+href="(https?:)?//' \
    'loads a remote stylesheet'

for stylesheet in "$SITE_DIRECTORY"/*.css; do
    refute_contains "$stylesheet" '@import' 'imports another stylesheet'
    refute_contains "$stylesheet" 'url\((https?:)?//' 'loads a remote resource'
done

assert_local_references_exist() {
    local reference
    while read -r reference; do
        [[ -n "$reference" ]] || continue

        case "$reference" in
            http://* | https://* | //* | \#* | mailto:* | data:*) continue ;;
        esac

        if [[ ! -f "$SITE_DIRECTORY/${reference%%[?#]*}" ]]; then
            echo "index.html references a missing file: $reference" >&2
            exit 1
        fi
    done < <(grep -oE '(href|src)="[^"]+"' "$PAGE" | sed -E 's/^(href|src)="//; s/"$//')
}

assert_local_references_exist

assert_contains "$SITE_DIRECTORY/sitemap.xml" "<loc>$CANONICAL_URL</loc>" \
    "a location entry for $CANONICAL_URL"
assert_contains "$SITE_DIRECTORY/robots.txt" "^Sitemap: ${CANONICAL_URL}sitemap.xml$" \
    'a sitemap reference'

# Publishing through a GitHub Actions workflow means the custom domain lives in
# the repository settings, and a committed CNAME file is ignored. Keeping one
# around would suggest the domain can be changed by editing the site.
if [[ -f "$SITE_DIRECTORY/CNAME" ]]; then
    echo "Unexpected CNAME file: Actions-based Pages publishing ignores it" >&2
    exit 1
fi

echo "Verified $SITE_DIRECTORY"
