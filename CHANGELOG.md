## [1.6.1](https://github.com/mixpanel/mixpanel-ios-session-replay-package/tree/1.6.1) (2026-10-07)

### Features

- raise minimum iOS to 15 for Xcode 27 and remove the iOS 26 opt-in flag (#54) ([#54](https://github.com/mixpanel/mixpanel-ios-session-replay-package/pull/54))

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
