# Mixpanel iOS Session Replay SDK

**Session Replay for iOS lets you visually replay your user's app interactions, providing powerful qualitative insights to complement your quantitative analytics.**

---

### ⚠️ iOS 26 Compatibility Notice

-   **iOS 26+ with Xcode 26: SwiftUI Automasking Issue — Fixed in [v1.2.1](https://github.com/mixpanel/mixpanel-ios-session-replay-package/releases/tag/v1.2.1)**

  The iOS 26 "Liquid Glass" rendering changes that affected automasking in Session Replay for SwiftUI apps have been addressed in v1.2.1. Upgrade to v1.2.1 to get the fix.

  **Who was affected:** SwiftUI apps using automasking for text or images, built with Xcode 26, and running on iOS 26+.

  **If you are on v1.2.0:** Session Replay is disabled by default for apps built with Xcode 26+ running on iOS 26+. Upgrade to v1.2.1 and enable session replay by setting `config.enableSessionReplayOniOS26AndLater = true` during SDK initialization.

  **If you re-enabled Session Replay on v1.2.0:** Upgrade to v1.2.1 to get the fix.

  **If you disabled automasking as a workaround:** Upgrade to v1.2.1 and enable the automasking config.

  While the iOS 26 "Liquid Glass" fix is now available, we still recommend thoroughly testing session replays in your app before pushing to production. We also encourage explicitly masking sensitive views rather than relying solely on the SDK's automasking.

  **Note:** The `enableSessionReplayOniOS26AndLater` flag is still used by SDK in v1.2.1 but will be removed in a future minor version.

---

## Overview

Mixpanel Session Replay enables you to quickly understand **why** users behave a certain way in your app, complementing analytics insights on **where** they drop off.

---

## Requirements

- Active Mixpanel account (Enterprise)
- Mixpanel Swift SDK `v4.3.1` or later

---

## Installation
### Using Swift Package Manager
Add the Session Replay SDK using Swift Package Manager directly in Xcode:

1. In Xcode, go to **File → Add Package Dependencies...**
2. Paste the GitHub URL: `https://github.com/mixpanel/mixpanel-ios-session-replay-package`
3. Follow the prompts to select the latest version and add the package to your project.

### Using Cocoapods
Open **podfile** and add Mixpanel Session Replay library to your dependencies: 

```
target 'MyApp' do
     pod 'MixpanelSessionReplay', :git => 'https://github.com/mixpanel/mixpanel-ios-session-replay-package.git', :tag => 'v1.0.0'
end
```

Install the Mixpanel Session Replay by running the following in the Xcode project directory:
```
pod install
```
---

## Quick Start

### SwiftUI

```swift
import Mixpanel
import MixpanelSessionReplay

struct YourApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                let config = MPSessionReplayConfig(wifiOnly: false, enableLogging: true)
                MPSessionReplay.initialize(
                    token: Mixpanel.mainInstance().apiToken,
                    distinctId: Mixpanel.mainInstance().distinctId,
                    config: config
                )
            }
        }
    }
}
```

### UIKit

```swift
import UIKit
import Mixpanel
import MixpanelSessionReplay

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Mixpanel.initialize(token: "YOUR_MIXPANEL_TOKEN")

        let config = MPSessionReplayConfig(wifiOnly: false, enableLogging: true)
        MPSessionReplay.initialize(
            token: Mixpanel.mainInstance().apiToken,
            distinctId: Mixpanel.mainInstance().distinctId,
            config: config
        )
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        MPSessionReplay.getInstance()?.startRecording()
    }
}
```

---

## Configuration

Customize your session replay by modifying `MPSessionReplayConfig`:

- `wifiOnly`: Restricts uploads to WiFi connections (default: `true`).
- `autoMaskedViews`: Automatically masks sensitive views (`.image`, `.text`, `.web`, `.map` by default).
- `autoStartRecording`: Whether or not to automatically start recording upon initialization (default: `true`)
- `autoStartRecordingSessionsPercent`: Controls session sampling from `0.0` (none) to `100.0` (all, default) when `autoStartRecording` is `true` .
- `enableLogging`: Turn on debug logs (default: false)
- `flushInterval`: How frequently to flush replay events (default: 10 seconds)

---

## Privacy & Data Masking

By default, Mixpanel automatically masks sensitive views:

- All text field inputs (cannot be unmasked)
- Images, Labels, WebViews, MapViews (can be manually adjusted)

To manually control sensitivity:

```swift
// SwiftUI
Image("photo").mpReplaySensitive(true)

// UIKit
yourUIView.mpReplaySensitive = true
```

---

## Resources

- [Full Documentation](https://mixpanel.com/docs/session-replay/session-replay-web)
- [Legal: Beta Terms](https://mixpanel.com/legal/session-replay-beta-service-addendum)

---

## Support

Questions or feedback? Contact your Mixpanel Account Manager.
