# Strongcopy

[![CI](https://github.com/mahata/strongcopy/actions/workflows/ci.yml/badge.svg)](https://github.com/mahata/strongcopy/actions/workflows/ci.yml)

A macOS utility that confirms when data has been copied to the clipboard.

## Overview

Strongcopy runs as a background accessory app. It watches the macOS pasteboard
change counter and briefly displays a non-activating **Copied** HUD near the
mouse pointer whenever the clipboard changes. A clipboard icon in the menu bar
confirms that Strongcopy is running and provides **About** and **Quit** actions.

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
3. In Applications, Control-click **Strongcopy**, choose **Open**, then confirm
   that you want to open it. If macOS does not offer that option, try opening
   Strongcopy once, then use **System Settings > Privacy & Security > Open
   Anyway**.

Release builds contain an ad-hoc-signed app in an unsigned, unnotarized DMG, so
macOS Gatekeeper requires this manual approval the first time each downloaded
build is opened. Strongcopy runs without a Dock icon; it adds a clipboard icon
to the menu bar so you can confirm it is running. Click the menu bar icon and
choose **Quit Strongcopy** to stop it, or **About Strongcopy** to see the
version.

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
Like published releases, local builds contain an ad-hoc-signed app in an
unsigned, unnotarized DMG.

## Development

This project uses Swift Package Manager and follows a TDD (Test-Driven Development) approach.

### Project Structure

```
Strongcopy/
├── Package.swift              # Swift Package Manager configuration
├── Sources/
│   └── Strongcopy/
│       ├── Strongcopy.swift        # Application entry point
│       ├── AppDelegate.swift       # Application lifecycle
│       ├── ClipboardMonitor.swift  # Pasteboard change detection
│       ├── CopyFeedback.swift      # HUD feedback
│       ├── StatusItemController.swift # Menu bar status item
│       └── Scheduling.swift        # Timer abstraction
└── Tests/
    └── StrongcopyTests/
        └── StrongcopyTests.swift  # Unit tests
```

### Opening in Xcode

On macOS, you can open this project in Xcode:

```bash
open Package.swift
```

Or double-click `Package.swift` in Finder.

### Publishing a Release

Every successful CI run caused by a push to `main` automatically publishes an
unsigned, unnotarized universal DMG containing an ad-hoc-signed app through
GitHub Releases. Pull-request builds do not publish releases. No Apple Developer
credentials are required, but users must manually approve the app in Gatekeeper.

The first automated release is `v0.1.0`. Each later release increments the
patch component of the highest existing `vMAJOR.MINOR.PATCH` tag. A commit is
released at most once, so rerunning CI for an already released commit does not
create another version.

GitHub Actions must also have permission to write repository contents. Under
**Settings > Actions > General > Workflow permissions**, select **Read and write
permissions**. The automatically generated tag sets the marketing version,
while the GitHub Actions run number supplies the bundle build number.

### Current scope

The initial milestone uses fixed polling and display durations. Preferences,
launch at login, sounds, and a branded app icon are not implemented yet. Global
Command-C event capture is also out of scope.

## License

See LICENSE file for details.
