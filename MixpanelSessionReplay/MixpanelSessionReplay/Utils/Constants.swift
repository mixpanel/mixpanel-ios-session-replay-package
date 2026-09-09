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
    private static let libVersion = "1.5.2"
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

/// `data.source` of an rrweb incremental snapshot. Values are rrweb's, not ours —
/// `1` is MouseMove, which we never emit; touch drags are `6`.
struct IncrementalSource {
    static let mutation = 0
    static let mouseInteraction = 2
    static let touchMove = 6
}

/// `data.type` of a `IncrementalSource.mouseInteraction` snapshot. Touch gestures map onto
/// TOUCH_START / TOUCH_END / TOUCH_CANCEL; the drag path between them ships separately as
/// `IncrementalSource.touchMove` positions.
struct MouseInteraction {
    static let touchStart = 7
    static let touchEnd = 9
    static let touchCancel = 10
}

/// Sampling budget for `IncrementalSource.touchMove` batches, mirroring rrweb-web's
/// `sampling.mousemove` (50ms between samples) and its 500ms emit throttle.
struct TouchSampling {
    /// Minimum gap between two sampled `.moved` points.
    static let moveSampleIntervalMs: Int64 = 50

    /// Batch is emitted once it spans this much time.
    static let moveBatchIntervalMs: Int64 = 500

    /// Hard cap on a single batch, so a stuck gesture can't grow the queue without bound.
    static let maxPositionsPerBatch = 100
}

struct PayloadObjectID {
    static let mainSnapshot = 28
}

/// Data residency base URLs for Mixpanel Session Replay.
///
/// Use these constants to specify the data center region when configuring Session Replay.
///
/// Example:
/// ```swift
/// let config = MPSessionReplayConfig(serverURL: DataResidency.us)
/// ```
public enum DataResidency {
    /// Base URL for US data residency (default).
    public static let us = "https://api.mixpanel.com"
    /// Base URL for EU data residency.
    public static let eu = "https://api-eu.mixpanel.com"
    /// Base URL for India data residency.
    public static let `in` = "https://api-in.mixpanel.com"
}

struct MPSessionReplayAPI {
    /// Base URL for session replay redirect (works for all data residency regions).
    static let sessionReplayRedirect = "https://mixpanel.com/projects/replay-redirect"

    // Paths
    private static let recordPath = "/record"
    private static let settingsPath = "/settings"

    /// Returns the full settings endpoint URL for the given data residency base URL
    /// - Parameter serverURL: The data residency base URL (e.g., DataResidency.us)
    /// - Returns: Full settings endpoint URL (e.g., "https://api.mixpanel.com/settings")
    static func settingsEndpoint(for serverURL: String = DataResidency.us) -> String {
        "\(serverURL)\(settingsPath)"
    }

    /// Returns the full record endpoint URL for the given data residency base URL
    /// - Parameter serverURL: The data residency base URL (e.g., DataResidency.us)
    /// - Returns: Full record endpoint URL (e.g., "https://api.mixpanel.com/record")
    static func recordEndpoint(for serverURL: String = DataResidency.us) -> String {
        return "\(serverURL)\(recordPath)"
    }
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
