# Strongcopy

[![CI](https://github.com/mahata/strongcopy/actions/workflows/ci.yml/badge.svg)](https://github.com/mahata/strongcopy/actions/workflows/ci.yml)

A macOS utility that confirms when data has been copied to the clipboard.

## Overview

Strongcopy runs as a background accessory app. It watches the macOS pasteboard
change counter and briefly displays a non-activating **Copied** HUD near the
mouse pointer whenever the clipboard changes. The app's icon appears in the menu
bar to confirm that Strongcopy is running and provides **About**, **Quit**, and
software update actions.

Strongcopy does not read, log, or retain clipboard contents. It also does not
require Accessibility or notification permission. It does contact GitHub once a
day to look for a new release, which you can turn off from the menu.

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
This is the only install you have to do by hand; Strongcopy keeps itself up to
date from then on.

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

### Keeping Strongcopy Up to Date

Strongcopy updates itself. Once a day it asks GitHub for the latest release, and
when one is newer than the running copy it offers to install it. Choosing
**Update Now** downloads the release disk image, replaces the installed app, and
restarts it. Choosing **Later** dismisses that version for good; you will not be
asked about it again, only about something newer. Since a release is published
for every change merged to `main`, this keeps a steady stream of patch releases
from turning into a steady stream of prompts.

**Check for Updates…** asks straight away and reports the result either way,
including for a version you previously dismissed. **Automatically Check for
Updates** turns the daily check on and off; it starts out on. With it off,
nothing contacts GitHub unless you ask.

An update is only installed if the downloaded copy is signed by the same
Developer ID as the copy already running, and carries the version the release
claims. The published `.sha256` file is checked too, but only to catch a damaged
download: it travels beside the disk image, so it says nothing about who built
it. The signature is what does. A newer version is also required, so a withdrawn
release cannot move you backwards.

> [!NOTE]
> Both update items are greyed out unless Strongcopy runs from an app bundle
> signed with a Developer ID, because the signature of the running copy is what
> the download is checked against. Development builds and ad-hoc signed local
> builds have no such signature, so they never check for or install updates.

> [!NOTE]
> Installing writes to the folder holding the app, so an update fails if you
> cannot write there. Strongcopy reports this rather than asking for an
> administrator password. Keeping the app in `/Applications` or `~/Applications`
> avoids it.

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
│   │   ├── UpdateFeed.swift        # Release versions and the GitHub feed
│   │   ├── UpdateController.swift  # When an update is offered
│   │   ├── UpdateInstaller.swift   # Signature checks and installation
│   │   └── Scheduling.swift        # Timer abstraction
│   ├── StrongcopyBrand/
│   │   ├── BrandCanvas.swift       # Icon canvas, squircle, palette
│   │   ├── BrandMark.swift         # Card and checkmark geometry
│   │   └── BrandArtwork.swift      # App icon and menu bar renderings
│   └── GenerateAppIcon/
│       └── main.swift              # Writes AppIcon.icns
└── Tests/
    └── StrongcopyTests/
        ├── StrongcopyTests.swift   # App unit tests
        ├── BrandTests.swift        # Brand artwork unit tests
        └── UpdateTests.swift       # Update unit tests
```

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

> [!IMPORTANT]
> Installed copies find updates by asset name, so `Strongcopy-<version>.dmg` and
> `Strongcopy-<version>.dmg.sha256` are a compatibility contract, not just a
> convention. Renaming them, or publishing a release whose assets disagree with
> its tag, strands every copy already in the wild: the updater refuses a release
> it cannot match rather than downloading something unexpected. The signing
> identity matters just as much, because an update is only installed when it
> carries the same Developer ID as the copy it replaces.

### Dependency Updates

Dependabot checks weekly for newer GitHub Actions and Swift package
dependencies, opening one grouped pull request per ecosystem. Workflow actions
are pinned to commit SHAs, and Dependabot updates the pin and its trailing
version comment together, so the pins stay both current and explicit.

Because merging to `main` publishes a release, each accepted update ships as a
new patch version. Adjust the cadence in `.github/dependabot.yml` if that is
more churn than a release cycle warrants.

### Current scope

The initial milestone uses fixed polling and display durations. Sounds are not
implemented yet, and the only preference is whether to check for updates
automatically. Global Command-C event capture is also out of scope.

## License

See LICENSE file for details.
