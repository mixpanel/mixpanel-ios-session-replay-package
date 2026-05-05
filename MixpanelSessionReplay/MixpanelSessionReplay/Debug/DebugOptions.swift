//
//  DebugOptions.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation

/// Configuration for debug features in Session Replay.
///
/// Pass an instance of this class to ``MPSessionReplayConfig/debugOptions``
/// to enable debug features. Only works in debug builds.
///
/// ## Example
/// ```swift
/// var config = MPSessionReplayConfig()
/// config.debugOptions = DebugOptions(overlayColors: DebugOverlayColors())
/// ```
public struct DebugOptions: Codable {

    /// When not nil, enables a visual overlay showing which views are being masked.
    /// Only works in debug builds.
    ///
    /// - Default: `DebugOverlayColors()` (uses default colors)
    public var overlayColors: DebugOverlayColors?

    public init(overlayColors: DebugOverlayColors? = DebugOverlayColors()) {
        self.overlayColors = overlayColors
    }
}
