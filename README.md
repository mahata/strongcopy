# Strongcopy

[![CI](https://github.com/mahata/strongcopy/actions/workflows/ci.yml/badge.svg)](https://github.com/mahata/strongcopy/actions/workflows/ci.yml)

A macOS utility that confirms when data has been copied to the clipboard.

## Overview

Strongcopy runs as a background accessory app. It watches the macOS pasteboard
change counter and briefly displays a non-activating **Copied** HUD near the
top-right of the screen whenever the clipboard changes.

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

### Current scope

The initial milestone uses fixed polling and display durations. Preferences,
launch at login, sounds, application packaging, and global Command-C event
capture are not implemented yet.

## License

See LICENSE file for details.
