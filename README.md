# Strongcopy

[![CI](https://github.com/mahata/strongcopy/actions/workflows/ci.yml/badge.svg)](https://github.com/mahata/strongcopy/actions/workflows/ci.yml)

A macOS utility that confirms when data has been copied to the clipboard.

## Overview

Strongcopy runs as a background accessory app. It watches the macOS pasteboard
change counter and briefly displays a non-activating **Copied** HUD near the
mouse pointer whenever the clipboard changes. The app's icon appears in the menu
bar to confirm that Strongcopy is running and provides **About** and **Quit**
actions.

Strongcopy does not read, log, or retain clipboard contents. It also does not
require Accessibility or notification permission.

> [!NOTE]
> Strongcopy observes pasteboard changes rather than intercepting Command-C.
> Clipboard updates made by menus, scripts, password managers, or other apps
> therefore produce the same feedback.

## Requirements

- macOS 13.0 or later
- Xcode 14.0 or later
- Swift 6.2 or later

## Getting Started

### Installing Strongcopy

1. Download `Strongcopy-<version>.dmg` from the
   [latest GitHub Release](https://github.com/mahata/strongcopy/releases/latest).
2. Open the DMG and drag **Strongcopy** to **Applications**.
3. Open Strongcopy from Applications.

Release builds are signed with a Developer ID certificate and notarized by
Apple, so macOS Gatekeeper can verify them without requiring a security
override. Strongcopy runs without a Dock icon; it puts its icon in the menu bar
so you can confirm it is running. Click the menu bar icon and choose
**Quit Strongcopy** to stop it, or **About Strongcopy** to see the version.

### Opening Strongcopy at Login

Click the menu bar icon and choose **Open at Login** to have macOS start
Strongcopy automatically when you log in. The item is off until you turn it on,
and choosing it again turns it back off. The checkmark reflects the system
setting, so it stays accurate even if you change it from **System Settings >
General > Login Items**.

macOS may require you to approve the login item before it takes effect. When
that happens, Strongcopy shows a dash instead of a checkmark and offers to open
the relevant System Settings pane.

> [!NOTE]
> **Open at Login** is greyed out unless Strongcopy runs from a real app bundle,
> so it is unavailable during development with `swift run`. The bundle itself can
> live anywhere, but avoid moving it once the item is on, because macOS tracks
> the login item by location. Ad-hoc signed local builds get a new signature on
> every build, so login items registered from them can go stale; notarized
> releases are stable.

### Building the App

```bash
swift build
```

### Running the App

```bash
swift run
```

### Running Tests

```bash
swift test
```

### Building an Installable App Locally

Create an ad-hoc-signed universal DMG for local testing:

```bash
scripts/package-macos.sh 0.1.0
scripts/verify-macos-package.sh dist/Strongcopy-0.1.0.dmg 0.1.0 1
```

The package contains native slices for both Apple Silicon and Intel Macs.
Ad-hoc local builds are not notarized and are intended only for development.

Build the sandboxed Mac App Store package the same way:

```bash
scripts/package-mas.sh 0.1.0
scripts/verify-mas-package.sh dist/Strongcopy-0.1.0.pkg 0.1.0 1
```

Without signing credentials this produces an ad-hoc-signed bundle in an unsigned
package. That build still runs under the App Sandbox, so it is the way to check
that sandboxing has not broken anything before spending a build number on an
upload. Installing it and copying something should show the HUD as usual.

## Development

This project uses Swift Package Manager and follows a TDD (Test-Driven Development) approach.

### Project Structure

```
Strongcopy/
├── Package.swift              # Swift Package Manager configuration
├── Sources/
│   ├── Strongcopy/
│   │   ├── Strongcopy.swift        # Application entry point
│   │   ├── AppDelegate.swift       # Application lifecycle
│   │   ├── ClipboardMonitor.swift  # Pasteboard change detection
│   │   ├── CopyFeedback.swift      # HUD feedback
│   │   ├── StatusItemController.swift # Menu bar status item
│   │   ├── LaunchAtLogin.swift     # Login item registration
│   │   └── Scheduling.swift        # Timer abstraction
│   ├── StrongcopyBrand/
│   │   ├── BrandCanvas.swift       # Icon canvas, squircle, palette
│   │   ├── BrandMark.swift         # Card and checkmark geometry
│   │   └── BrandArtwork.swift      # App icon and menu bar renderings
│   └── GenerateAppIcon/
│       └── main.swift              # Writes AppIcon.icns
├── Tests/
│   └── StrongcopyTests/
│       ├── StrongcopyTests.swift   # App unit tests
│       └── BrandTests.swift        # Brand artwork unit tests
└── web/                       # Website for strongcopy.mahata.org
```

### Website

The website served at <https://strongcopy.mahata.org> lives in `web/`. It is
plain HTML and CSS with no build step, no JavaScript, and no third-party
requests, so the deployed bytes are the committed bytes. The app icon and the
Copied badge are redrawn there as inline SVG and CSS, matching the convention
that artwork is code rather than a binary asset. `web/icon.svg` and
`web/favicon.svg` mirror the squircle, palette, and card geometry defined in
`Sources/StrongcopyBrand`, so a change to the brand there should be carried
across by hand.

Three pages are published: the landing page, `web/privacy/`, and `web/support/`.
The latter two are not decoration. App Store Connect refuses a submission
without both a privacy policy URL and a support URL, so those pages are part of
the App Store release path rather than the marketing site, and the URLs they
publish should stay stable once a submission cites them. Each lives in its own
directory so that the published address carries no `.html` extension.

The privacy policy makes claims the code has to keep true: that Strongcopy reads
only the pasteboard change counter, stores nothing, and opens no network
connections. Those are the same claims the App Store privacy declaration
answers, so a change to what the app reads or stores means editing the policy in
the same commit.

Preview it locally:

```bash
python3 -m http.server --directory web 8000
```

`.github/workflows/pages.yml` publishes `web/` to GitHub Pages when `main`
changes. Because a successful CI run on `main` cuts a release, `ci.yml` ignores
the website paths so editing a paragraph of copy does not ship a new version of
the app.

Setting the site up on a fresh repository takes three manual steps:

1. Under **Settings > Pages**, set the source to **GitHub Actions** and the
   custom domain to `strongcopy.mahata.org`. No `CNAME` file belongs in `web/`;
   workflow-based publishing reads the domain from settings and ignores the file.
2. In Cloudflare DNS, add `CNAME strongcopy -> mahata.github.io` with the proxy
   **disabled**. Proxying intercepts the challenge GitHub uses to issue the
   certificate. It can be turned on later, once HTTPS works, if the zone runs in
   Full SSL mode.
3. Once GitHub reports the certificate as issued, enable **Enforce HTTPS**.

### App Icon

The app icon is drawn in code rather than stored as a binary asset. The
`StrongcopyBrand` target lays out a stack of two copied cards carrying a
checkmark — the confirmation Strongcopy exists to provide — onto the standard
macOS squircle, drawing it with CoreGraphics. Every size in the icon set is
drawn as vectors at its native resolution, with heavier artwork at 16 and 32
pixels so the checkmark stays legible. The `GenerateAppIcon` target writes those
renditions out with ImageIO and hands the iconset to `iconutil`, so the icon
needs no framework beyond the system ones.

The menu bar reuses the same geometry. Because macOS tints menu bar images to
suit the light and dark menu bars, the status item drops the squircle and its
gradient and draws the mark as a template image, cutting the checkmark out of
the front card so it shows through as the bar's own colour.

`scripts/package-macos.sh` runs the `GenerateAppIcon` target during packaging,
writing `Contents/Resources/AppIcon.icns` into the bundle before it is signed and
reusing the same file as the DMG volume icon. To render and inspect the icon on
its own:

```bash
swift run GenerateAppIcon /tmp/AppIcon.icns
scripts/verify-app-icon.sh /tmp/AppIcon.icns
iconutil --convert iconset --output /tmp/AppIcon.iconset /tmp/AppIcon.icns
open /tmp/AppIcon.iconset
```

### Opening in Xcode

On macOS, you can open this project in Xcode:

```bash
open Package.swift
```

Or double-click `Package.swift` in Finder.

### Publishing a Release

Every successful CI run caused by a push to `main` automatically packages,
signs, notarizes, and publishes a universal DMG through GitHub Releases.
Pull-request builds do not publish releases.

The first automated release is `v0.1.0`. Each later release increments the
patch component of the highest existing `vMAJOR.MINOR.PATCH` tag. A commit is
released at most once, so rerunning CI for an already released commit does not
create another version.

Configure these GitHub Actions secrets before publishing the first release:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE` | Base64-encoded Developer ID Application `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | Password for the `.p12` |
| `DEVELOPER_ID_APPLICATION` | Full `Developer ID Application: ...` certificate identity |
| `APPLE_API_KEY` | Base64-encoded App Store Connect API `.p8` key |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer ID |

GitHub Actions must also have permission to write repository contents. Under
**Settings > Actions > General > Workflow permissions**, select **Read and write
permissions**. The automatically generated tag sets the marketing version,
while the GitHub Actions run number supplies the bundle build number.

### Publishing to the Mac App Store

The App Store build is a second distribution of the same source, not a
replacement for the DMG. Three things separate it from the Developer ID build:
it runs under the App Sandbox, it carries a provisioning profile, and it is
delivered as a signed installer package. Apple notarizes App Store builds
itself, so `scripts/package-mas.sh` has no notarization step.

Strongcopy needs no sandbox exceptions. The pasteboard change counter, the
pointer location, the floating panel, and `SMAppService` registration all work
inside the default sandbox, so `Packaging/Strongcopy.entitlements` asks only for
`com.apple.security.app-sandbox`. The team-specific entitlements are added at
packaging time from `TEAM_ID` so that no team identifier is committed.

Preparing the first submission takes these steps:

1. Join the Apple Developer Program and register the `org.mahata.strongcopy`
   bundle identifier. Decide first whether the App Store build should use its
   own identifier: if someone installs both it and the DMG, the two bundles
   compete over the same login item registration.
2. Create an **Apple Distribution** certificate, a **3rd Party Mac Developer
   Installer** certificate, and a **Mac App Store** provisioning profile.
3. Build and check the package:

   ```bash
   TEAM_ID=ABCDE12345 \
   PROVISIONING_PROFILE=~/Strongcopy_MAS.provisionprofile \
   APP_CODESIGN_IDENTITY="Apple Distribution: ..." \
   INSTALLER_CODESIGN_IDENTITY="3rd Party Mac Developer Installer: ..." \
   BUILD_NUMBER=1 \
     scripts/package-mas.sh 0.1.0

   REQUIRE_SUBMISSION_SIGNING=1 \
     scripts/verify-mas-package.sh dist/Strongcopy-0.1.0.pkg 0.1.0 1
   ```

4. Create the app record in App Store Connect. The support URL is
   <https://strongcopy.mahata.org/support/> and the privacy policy URL is
   <https://strongcopy.mahata.org/privacy/>; both are required fields, and both
   are served from `web/`. The record also needs at least one screenshot sized
   1280x800, 1440x900, 2560x1600, or 2880x1800, and a privacy declaration.
   Strongcopy collects nothing, so every category answers "Data Not Collected",
   which is what the privacy policy already states.
5. Upload the package with Transporter, or from the command line with the same
   App Store Connect API key the release workflow uses for notarization:

   ```bash
   xcrun iTMSTransporter -m upload -assetFile dist/Strongcopy-0.1.0.pkg \
       -apiKey "$APPLE_API_KEY_ID" -apiIssuer "$APPLE_API_ISSUER_ID"
   ```

   `altool` is deprecated, and `notarytool` only notarizes; neither uploads to
   App Store Connect.
6. Submit for review. `CFBundleVersion` has to increase on every upload, and a
   build number that App Store Connect has already seen cannot be reused, which
   is what `verify-mas-package.sh` exists to catch.

Two review guidelines are worth reading before submitting. Guideline 4.2 asks
that an app do enough to justify its own listing, and a menu bar app whose whole
job is a brief HUD invites that question. Reviewers also reject accessory apps
that appear to do nothing when opened, because `LSUIElement` means no window
opens on launch. The review notes should therefore say that Strongcopy reads
only the pasteboard change counter and never its contents, and should tell the
reviewer to press Command-C and watch the pointer.

### Dependency Updates

Dependabot checks weekly for newer GitHub Actions and Swift package
dependencies, opening one grouped pull request per ecosystem. Workflow actions
are pinned to commit SHAs, and Dependabot updates the pin and its trailing
version comment together, so the pins stay both current and explicit.

Because merging to `main` publishes a release, each accepted update ships as a
new patch version. Adjust the cadence in `.github/dependabot.yml` if that is
more churn than a release cycle warrants.

### Current scope

The initial milestone uses fixed polling and display durations. Preferences and
sounds are not implemented yet. Global Command-C event capture is also out of
scope.

## License

See LICENSE file for details.
