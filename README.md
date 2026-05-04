
<p align="center">
  <img src="https://user-images.githubusercontent.com/71290498/231855731-2d3774c3-dc41-4595-abfb-9c49f5f84103.png" alt="Mixpanel Session Replay iOS SDK" height="150"/>
</p>


<a name="introduction"></a>
# Mixpanel iOS Session Replay SDK

**Session Replay for iOS lets you visually replay your user's app interactions, providing powerful qualitative insights to complement your quantitative analytics.**

---

## Overview

Mixpanel Session Replay enables you to quickly understand **why** users behave a certain way in your app, complementing analytics insights on **where** they drop off.

---

# SDK Development

This section is relevant **only if you are developing or contributing to this SDK repository**.

## Swift Formatting (Apple swift-format)

This repository uses Apple's swift-format to ensure consistent Swift formatting across all developers.

Formatting rules are defined in the `.swift-format` file at the repo root.

### Prerequisite
Install swift-format:
```bash
brew install swift-format
```

### Format Swift Code Locally

Format the entire repository:
```bash
sh ./scripts/format-swift.sh
```

Format a single file:
```bash
sh ./scripts/format-swift.sh MixpanelSessionReplay/MixpanelSessionReplay/MyFile.swift
```

Format multiple files:
```bash
sh ./scripts/format-swift.sh MixpanelSessionReplay/FileA.swift MixpanelSessionReplay/FileB.swift
```

## Required Git Hook Setup

After pulling the repo, run:

```bash
git config core.hooksPath .githooks
```

This enables the pre-commit hook that checks formatting before each commit.

### How it works

1. When you commit, the hook checks if staged Swift files are properly formatted
2. If formatting issues are found, the commit is blocked
3. The hook displays which files need formatting and provides the exact command to fix them
4. After running the formatter, stage the files again and recommit

### Example

```
🧹 Running Apple swift-format pre-commit hook (staged only)
→ Checking formatting on staged Swift files

❌ These files need formatting:
   MixpanelSessionReplay/Foo.swift
   MixpanelSessionReplay/Bar.swift

Run the formatter and re-stage:
  sh ./scripts/format-swift.sh MixpanelSessionReplay/Foo.swift MixpanelSessionReplay/Bar.swift
```

Then run the suggested command, re-stage, and commit again.

---

# SDK Integration

This section is for **app developers integrating the SDK** into their iOS applications.

## Requirements

- Active Mixpanel account (Enterprise)

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
     pod 'MixpanelSessionReplay', :git => 'https://github.com/mixpanel/mixpanel-ios-session-replay-package.git', :tag => '1.0.0'
end
```

Install the Mixpanel Session Replay by running the following in the Xcode project directory:
```
pod install
```

---

## Setup & Usage

For detailed setup instructions, configuration options, and usage examples, please visit our official documentation:

**[📚 Mixpanel Session Replay for Swift - Complete Guide](https://docs.mixpanel.com/docs/tracking-methods/sdks/swift/swift-replay)**

The documentation covers:
- Quick start setup
- Initialization and configuration
- Recording sessions
- Privacy controls and sensitive data masking
- Advanced features and customization

---

Have any questions? Reach out to Mixpanel [Support](https://help.mixpanel.com/hc/en-us/requests/new) to speak to someone smart, quickly.

