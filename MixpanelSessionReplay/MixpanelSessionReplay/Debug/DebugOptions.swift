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

    /// When not nil, hands you each wireframe as it is captured so you can check
    /// your masking while you develop. You get exactly the elements that are
    /// sent to Mixpanel, plus the reason each one's text was kept or removed.
    ///
    /// This *observes* wireframe capture; it does not enable it. Wireframes are
    /// only captured when ``MPSessionReplayConfig/wireframesOptions`` is set, so
    /// setting this on its own is harmless but never calls you back.
    ///
    /// Delivered on a background queue so a slow callback never holds up
    /// recording; make your callback thread-safe. Nothing given to it is ever
    /// sent to Mixpanel.
    ///
    /// ⚠️ Not a stable contract — the ``MPWireframeDebugSnapshot`` shape and the
    /// ``MPMaskDecision`` case names are meant for interactive debugging.
    ///
    /// ```swift
    /// var config = MPSessionReplayConfig()
    /// config.wireframesOptions = MPWireframesOptions()   // turns capture on
    /// config.debugOptions = DebugOptions(
    ///     wireframeEmitter: { snapshot in print(snapshot.toJson()) }
    /// )
    /// ```
    public var wireframeEmitter: ((MPWireframeDebugSnapshot) -> Void)? = nil

    public init(
        overlayColors: DebugOverlayColors? = DebugOverlayColors(),
        wireframeEmitter: ((MPWireframeDebugSnapshot) -> Void)? = nil
    ) {
        self.overlayColors = overlayColors
        self.wireframeEmitter = wireframeEmitter
    }

    // `wireframeEmitter` is deliberately excluded: a closure has no JSON
    // representation. Cross-platform bridges decode this type from JSON and set
    // the callback directly, mirroring Android's `@Transient wireframeEmitter`.
    private enum CodingKeys: String, CodingKey {
        case overlayColors
    }
}
