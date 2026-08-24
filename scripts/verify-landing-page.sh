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

# URLs are interpolated into extended regular expressions, and a URL is full of
# metacharacters. An unescaped dot matches any character, so a canonical link
# pointing at strongcopyXmahataYorg would satisfy a check meant to pin the exact
# host. Escape them so these assertions test what they claim to test.
escape_regex() {
    local input="$1" output="" index char
    for (( index = 0; index < ${#input}; index++ )); do
        char="${input:index:1}"
        case "$char" in
            .|\[|\]|\(|\)|\{|\}|\*|\+|\?|\||\^|\$|\\) output="$output\\$char" ;;
            *) output="$output$char" ;;
        esac
    done
    printf '%s' "$output"
}

readonly CANONICAL_PATTERN="$(escape_regex "$CANONICAL_URL")"
readonly RELEASES_PATTERN="$(escape_regex "$RELEASES_URL")"
readonly SITEMAP_LINE_PATTERN="$(escape_regex "Sitemap: ${CANONICAL_URL}sitemap.xml")"

# Attributes may be single or double quoted, and a guard that only understands
# one style is a guard that can be walked around.
readonly Q='["'"'"']'

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

assert_contains "$PAGE" "<html[^>]+lang=${Q}en${Q}" 'a language on the html element'
assert_contains "$PAGE" "<meta[^>]+name=${Q}viewport${Q}" 'a viewport meta tag'
assert_contains "$PAGE" "<meta[^>]+name=${Q}description${Q}" 'a description meta tag'
assert_contains "$PAGE" "<meta[^>]+name=${Q}theme-color${Q}" 'a theme-color meta tag'
assert_contains "$PAGE" "<link[^>]+rel=${Q}canonical${Q}[^>]+href=${Q}${CANONICAL_PATTERN}${Q}" \
    "a canonical link to $CANONICAL_URL"
assert_contains "$PAGE" "<meta[^>]+property=${Q}og:title${Q}" 'an og:title meta tag'
assert_contains "$PAGE" "<meta[^>]+property=${Q}og:description${Q}" 'an og:description meta tag'
assert_contains "$PAGE" "<meta[^>]+property=${Q}og:url${Q}[^>]+content=${Q}${CANONICAL_PATTERN}${Q}" \
    "an og:url meta tag pointing at $CANONICAL_URL"
assert_contains "$PAGE" "href=${Q}${RELEASES_PATTERN}${Q}" "a download link to $RELEASES_URL"

# The page promises a build-free, third-party-free download. Loading a remote
# stylesheet, script, font, or image would quietly break that promise.
refute_contains "$PAGE" '<script' 'ships JavaScript, but the page is meant to be script-free'
refute_contains "$PAGE" "src=${Q}(https?:)?//" 'loads a remote resource through a src attribute'
refute_contains "$PAGE" "<link[^>]+rel=${Q}stylesheet${Q}[^>]+href=${Q}(https?:)?//" \
    'loads a remote stylesheet'

for stylesheet in "$SITE_DIRECTORY"/*.css; do
    refute_contains "$stylesheet" '@import' 'imports another stylesheet'
    refute_contains "$stylesheet" "url\\([[:space:]]*${Q}?(https?:)?//" 'loads a remote resource'
done

assert_local_references_exist() {
    local reference path
    while read -r reference; do
        [[ -n "$reference" ]] || continue

        case "$reference" in
            http://* | https://* | //* | \#* | mailto:* | data:*) continue ;;
        esac

        path="${reference%%[?#]*}"
        [[ -n "$path" ]] || continue

        # A parent-directory hop resolves inside the repository while landing
        # outside the uploaded artifact, so the check would pass while the
        # deployed link 404s.
        case "/$path" in
            */../* | */..)
                echo "index.html references a path outside the site: $reference" >&2
                exit 1
                ;;
        esac

        if [[ ! -f "$SITE_DIRECTORY/$path" ]]; then
            echo "index.html references a missing file: $reference" >&2
            exit 1
        fi
    done < <(grep -oE "(href|src)=(\"[^\"]*\"|'[^']*')" "$PAGE" |
        cut -d= -f2- | sed -e 's/^.//' -e 's/.$//')
}

assert_local_references_exist

assert_contains "$SITE_DIRECTORY/sitemap.xml" "<loc>${CANONICAL_PATTERN}</loc>" \
    "a location entry for $CANONICAL_URL"
assert_contains "$SITE_DIRECTORY/robots.txt" "^${SITEMAP_LINE_PATTERN}$" \
    'a sitemap reference'

# Publishing through a GitHub Actions workflow means the custom domain lives in
# the repository settings, and a committed CNAME file is ignored. Keeping one
# around would suggest the domain can be changed by editing the site.
if [[ -f "$SITE_DIRECTORY/CNAME" ]]; then
    echo "Unexpected CNAME file: Actions-based Pages publishing ignores it" >&2
    exit 1
fi

echo "Verified $SITE_DIRECTORY"
