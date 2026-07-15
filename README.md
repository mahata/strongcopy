# strongcopy

[![CI](https://github.com/mahata/strongcopy/actions/workflows/ci.yml/badge.svg)](https://github.com/mahata/strongcopy/actions/workflows/ci.yml)

A Swift macOS application for strong copy functionality.

## Overview

This is a Hello World scaffolding app in Swift for macOS, designed to support TDD-style development.

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
│       └── Strongcopy.swift   # Main application code
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

### Adding New Features

1. Write a failing test in `Tests/StrongcopyTests/StrongcopyTests.swift`
2. Implement the feature in `Sources/Strongcopy/Strongcopy.swift`
3. Run tests to verify: `swift test`
4. Refactor as needed

## License

See LICENSE file for details.
