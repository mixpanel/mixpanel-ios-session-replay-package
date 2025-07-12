# Mixpanel iOS Session Replay SDK

**Session Replay for iOS lets you visually replay your user's app interactions, providing powerful qualitative insights to complement your quantitative analytics.**

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
                MPSessionReplay.initialize(token: Mixpanel.mainInstance().apiToken, distinctId: Mixpanel.mainInstance().distinctId, config: config)
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
        MPSessionReplay.initialize(token: Mixpanel.mainInstance().apiToken, distinctId: Mixpanel.mainInstance().distinctId, config: config)

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
