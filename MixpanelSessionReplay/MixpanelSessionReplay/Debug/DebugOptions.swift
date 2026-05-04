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
/// to enable debug features.
///
/// - Warning: Debug options should only be enabled in debug builds. It is the caller's
///   responsibility to ensure these options are not enabled in production, as they may
///   expose visual overlays and other debug information to end users.
///
/// ## Example
/// ```swift
/// var config = MPSessionReplayConfig()
/// #if DEBUG
/// config.debugOptions = DebugOptions(overlayColors: DebugOverlayColors())
/// #endif
/// ```
public struct DebugOptions: Codable {

    /// When not nil, enables a visual overlay showing which views are being masked.
    ///
    /// - Warning: Do not enable in production builds. It is the caller's responsibility
    ///   to ensure this is only set in debug builds.
    /// - Default: `DebugOverlayColors()` (uses default colors)
    public var overlayColors: DebugOverlayColors?

    public init(overlayColors: DebugOverlayColors? = DebugOverlayColors()) {
        self.overlayColors = overlayColors
    }
}
