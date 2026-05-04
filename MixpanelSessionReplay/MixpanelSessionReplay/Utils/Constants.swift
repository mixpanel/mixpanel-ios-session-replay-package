//
//  Constants.swift
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation

#if !os(OSX)
import UIKit
#endif  // !os(OSX)

public struct APIConstants {
    static let maxBatchSize = 50
    static let flushSize = 1000
    static let minRetryBackoff = 60.0
    static let maxRetryBackoff = 600.0
    static let failuresTillBackoff = 2
    private static let libVersion = "1.5.0"
    private static let mpLib = "swift-sr"
}

extension APIConstants {
    private static var _overriddenLibVersion: String?
    private static var _overriddenMpLib: String?

    public static var currentLibVersion: String {
        return _overriddenLibVersion ?? libVersion
    }

    public static func setLibVersion(_ version: String) {
        _overriddenLibVersion = version
    }

    public static var currentMpLib: String {
        return _overriddenMpLib ?? mpLib
    }

    public static func setMpLib(_ lib: String) {
        _overriddenMpLib = lib
    }
}

struct BundleConstants {
    static let ID = "com.mixpanel.Mixpanel"
}

#if !os(OSX) && !os(watchOS) && !os(visionOS)
extension UIDevice {
    var iPhoneX: Bool {
        return UIScreen.main.nativeBounds.height == 2436
    }
}
#endif  // !os(OSX)

struct EventType {
    static let load = 1
    static let fullSnapshot = 2
    static let incrementalSnapshot = 3
    static let meta = 4
    static let custom = 5
    static let plugin = 6
}

struct IncrementalSource {
    static let mutation = 0
    static let touchMove = 1
    static let touchInteraction = 2
}

struct TouchInteraction {
    static let start = 7
    static let swipeDistanceThreshold = 10.0
}

struct PayloadObjectID {
    static let mainSnapshot = 28
}

struct EndPoints {
    static let defaultRecord = "https://api-js.mixpanel.com/record"
}

struct TimingAdjustment {
    static let touchAdjustment = -600
}

struct ReplaySettings {
    static let recordInterval: Int64 = 500  // milliseconds
    static let flushInterval: TimeInterval = 10
    static let queueBatchSize = 50
    static let queueSizeLimit = 1000
    static let userDefaultsName = "mp_session_replay_prefs"
}

struct GzipSettings {
    static let gzipHeaderOffset = Int32(16)
}

struct ImageSettings {
    static let jpegCompressionRate = 0.4
}

struct NetworkError {
    static let domain = "com.mixpanel.sessionreplay"
    static let invalidRequestCode = 1001
    static let invalidResponseCode = 1002
    static let decodingErrorCode = 1003
    static let timeoutErrorCode = 1004
}
