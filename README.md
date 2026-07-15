# Strongcopy

[![CI](https://github.com/mahata/strongcopy/actions/workflows/ci.yml/badge.svg)](https://github.com/mahata/strongcopy/actions/workflows/ci.yml)

A macOS utility that confirms when data has been copied to the clipboard.

## Overview

Strongcopy runs as a background accessory app. It watches the macOS pasteboard
change counter and briefly displays a non-activating **Copied** HUD near the
mouse pointer whenever the clipboard changes.

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
override. Strongcopy runs without a Dock icon; quit it with Activity Monitor or
by logging out.

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
│   └── Strongcopy/
│       ├── Strongcopy.swift        # Application entry point
│       ├── AppDelegate.swift       # Application lifecycle
│       ├── ClipboardMonitor.swift  # Pasteboard change detection
│       ├── CopyFeedback.swift      # HUD feedback
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

Pushing a semantic version tag packages, signs, notarizes, and publishes a
universal DMG:

```bash
git tag v1.2.3
git push origin v1.2.3
```

Configure these GitHub Actions secrets before publishing the first release:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE` | Base64-encoded Developer ID Application `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | Password for the `.p12` |
| `DEVELOPER_ID_APPLICATION` | Full `Developer ID Application: ...` certificate identity |
| `APPLE_API_KEY` | Base64-encoded App Store Connect API `.p8` key |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer ID |

The release workflow accepts tags only in `vMAJOR.MINOR.PATCH` form. The tag
sets the marketing version, while the GitHub Actions run number supplies the
bundle build number.

### Current scope

The initial milestone uses fixed polling and display durations. Preferences,
launch at login, sounds, a branded app icon, and global Command-C event capture
are not implemented yet.

## License

See LICENSE file for details.
