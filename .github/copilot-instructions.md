# Copilot Coding Agent Instructions for Mixpanel iOS Session Replay SDK

## Repository Overview

This is the **Mixpanel Session Replay iOS SDK**, a Swift library that enables session replay recording for iOS applications. It captures screenshots and touch events to help developers understand user interactions. The SDK is distributed via Swift Package Manager (SPM) and works alongside the main Mixpanel iOS SDK.

- **Language**: Swift (iOS SDK)
- **Minimum Deployment Targets**: iOS 13.0, tvOS 13.0, macOS 10.15, watchOS 6.0
- **Swift Tools Version**: 5.3
- **License**: Apache 2.0

## Build and Test Instructions

### Prerequisites

- **macOS** with **Xcode 16.4** installed (required for full build/test)
- Xcode command-line tools (`xcode-select --install`)
- iOS Simulator (e.g., "iPhone 17 Pro")

### Building the Project

**Using Xcode (preferred for full testing):**
```bash
cd MixpanelSessionReplay
xcodebuild -scheme MixpanelSessionReplay -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -configuration Debug clean build
```

**Using Swift Package Manager (limited - no UI tests):**
```bash
swift build
```

> **Note:** Swift Package Manager can parse and partially build the package on Linux, but the SDK requires iOS frameworks (UIKit) and cannot be fully built or tested without macOS/Xcode.

### Running Tests

Tests require macOS with Xcode and an iOS Simulator:

```bash
cd MixpanelSessionReplay
xcodebuild -scheme MixpanelSessionReplay \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -configuration Debug \
  ONLY_ACTIVE_ARCH=NO \
  ENABLE_TESTABILITY=YES \
  -enableCodeCoverage YES \
  clean build test | xcpretty -c
```

### Creating XCFramework (Release)

```bash
./scripts/archive_all_destinations.sh
```

This creates `MixpanelSessionReplay.xcframework.zip` in the repository root.

## Project Layout

```
.
├── .github/
│   ├── CODEOWNERS              # Code review ownership
│   └── workflows/
│       ├── iOS.yml             # CI workflow (builds/tests on push/PR)
│       └── release.yml         # Release workflow (creates XCFramework on tag push)
├── MixpanelSessionReplay/      # Main project directory
│   ├── MixpanelSessionReplay/  # Source code
│   │   ├── MPSessionReplay.swift        # Public API entry point
│   │   ├── MPSessionReplayInstance.swift # Core instance implementation
│   │   ├── Extensions/         # Swift extensions
│   │   ├── Logging/            # Logging utilities
│   │   ├── Models/             # Data models (config, events)
│   │   ├── Network/            # Network layer (flush, requests)
│   │   ├── Resources/          # PrivacyInfo.xcprivacy
│   │   ├── SensitiveViews/     # View masking logic
│   │   ├── Services/           # Business logic services
│   │   ├── Tracking/           # Screen/touch event tracking
│   │   └── Utils/              # Helper utilities
│   ├── MixpanelSessionReplayTests/  # Unit tests
│   │   ├── BaseTests.swift     # Test base class with mock setup
│   │   ├── MockClasses.swift   # Test mocks
│   │   └── [subdirs]/          # Tests organized by feature
│   └── MixpanelSessionReplay.xcodeproj/  # Xcode project
├── scripts/
│   ├── archive_all_destinations.sh  # XCFramework build script
│   └── release.py              # Tag/release helper script
├── Package.swift               # Swift Package Manager manifest
└── README.md                   # User documentation
```

### Key Files

| File | Purpose |
|------|---------|
| `Package.swift` | SPM package definition with targets and dependencies |
| `MixpanelSessionReplay/MixpanelSessionReplay/MPSessionReplay.swift` | Public API for initialization |
| `MixpanelSessionReplay/MixpanelSessionReplay/MPSessionReplayInstance.swift` | Core session recording implementation |
| `MixpanelSessionReplay/MixpanelSessionReplay/Models/MPSessionReplayConfig.swift` | Configuration options |
| `MixpanelSessionReplay/MixpanelSessionReplay/Utils/Constants.swift` | Library version and constants |
| `MixpanelSessionReplayTests/BaseTests.swift` | Test base class for setting up mocks |

## CI/CD Workflows

### iOS CI (`iOS.yml`)
- **Triggers**: Push to `main`, PRs to `main` or `development`
- **Environment**: macOS-latest, Xcode 16.4
- **Actions**: Builds and runs all tests on iPhone 17 Pro Simulator

### Release (`release.yml`)
- **Triggers**: Push of tags matching `v*`
- **Actions**: Archives XCFramework, uploads artifact, creates GitHub release

## Coding Conventions

1. **File Headers**: Include copyright notice (`Copyright © [Year] Mixpanel. All rights reserved.`)
2. **Access Control**: Public API uses `open class` or `public`; internal implementation uses default access
3. **Testing**: Use `@testable import MixpanelSessionReplay`; extend `BaseTests` for common mock setup
4. **Thread Safety**: Use `ThreadUtils.runOnMainThread` for UI operations
5. **Logging**: Use `Logger.debug/info/warn/error` methods

## Version Updates

When updating the library version, modify `Constants.swift`:
```swift
private static let libVersion = "X.Y.Z"
```

## Trust These Instructions

If the information above is complete and accurate, trust it and avoid redundant searches. Only explore the codebase further if:
- Instructions are incomplete for your specific task
- You encounter errors that contradict these instructions
- You need implementation details not covered here
