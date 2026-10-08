## [2.0.0](https://github.com/mixpanel/mixpanel-ios-session-replay-package/tree/2.0.0) (2026-10-08)

### Breaking changes([#58](https://github.com/mixpanel/mixpanel-ios-session-replay-package/pull/58))

- Minimum iOS is now 15, matching Xcode 27.
- Removed `enableSessionReplayOniOS26AndLater` from `MPSessionReplayConfig`. Session Replay now runs on iOS 26+ by default, so just delete the flag from your config.
- Requires MixpanelSwiftCommon 2.0.

### Heads up
Check automasking on Liquid Glass in a test build, and mark sensitive views with `mpReplaySensitive(true)`.

### Older iOS or Xcode
Stay on 1.x with Xcode 26. It gets security and critical fixes until April 2027.


[Full Changelog](https://github.com/mixpanel/mixpanel-ios-session-replay-package/compare/1.6.1...2.0.0)

## [1.6.1](https://github.com/mixpanel/mixpanel-ios-session-replay-package/tree/1.6.1) (2026-10-08)

### Fixes

- Send app bundle_id and build_number as settings API query params (#51) ([#51](https://github.com/mixpanel/mixpanel-ios-session-replay-package/pull/51))

[Full Changelog](https://github.com/mixpanel/mixpanel-ios-session-replay-package/compare/1.6.0...1.6.1)

## [1.6.0](https://github.com/mixpanel/mixpanel-ios-session-replay-package/tree/1.6.0) (2026-09-09)

### Features

- wireframes (beta) (#50) ([#50](https://github.com/mixpanel/mixpanel-ios-session-replay-package/pull/50))

### Fixes

- prevent event processing during exponential backoff (#43) ([#43](https://github.com/mixpanel/mixpanel-ios-session-replay-package/pull/43))

[Full Changelog](https://github.com/mixpanel/mixpanel-ios-session-replay-package/compare/1.5.2...1.6.0)

## [1.5.2](https://github.com/mixpanel/mixpanel-ios-session-replay-package/tree/1.5.2) (2026-07-13)

### Fixes

- decode SwiftUI private class name at runtime to avoid App Store rejection (#41) ([#41](https://github.com/mixpanel/mixpanel-ios-session-replay-package/pull/41))
- inconsistent sdkconfig handling in ios remotesettingsmode (#38) ([#38](https://github.com/mixpanel/mixpanel-ios-session-replay-package/pull/38))

[Full Changelog](https://github.com/mixpanel/mixpanel-ios-session-replay-package/compare/1.5.1...1.5.2)

## [1.5.1](https://github.com/mixpanel/mixpanel-ios-session-replay-package/tree/1.5.1) (2026-06-09)

### Features

- support for data residency (#36) ([#36](https://github.com/mixpanel/mixpanel-ios-session-replay-package/pull/36))
- Add getSessionReplayUrl API to return replay link for active session (#34) ([#34](https://github.com/mixpanel/mixpanel-ios-session-replay-package/pull/34))

[Full Changelog](https://github.com/mixpanel/mixpanel-ios-session-replay-package/compare/1.5.0...1.5.1)

# Changelog

Last tag: 1.4.0
## [1.5.0](https://github.com/mixpanel/mixpanel-ios-session-replay-package/tree/1.5.0) (2026-05-05)

### Features

- Feature - Event bridge integration and Event trigger based session recording.

### Fixes

- Fix - Restricted debug overlay to `debug` builds only, preventing accidental exposure in production releases.

### Chores

- Enhance security policy with reporting guidelines (#30) ([#30](https://github.com/mixpanel/mixpanel-ios-session-replay-package/pull/30))

[Full Changelog](https://github.com/mixpanel/mixpanel-ios-session-replay-package/compare/1.4.0...1.5.0)
