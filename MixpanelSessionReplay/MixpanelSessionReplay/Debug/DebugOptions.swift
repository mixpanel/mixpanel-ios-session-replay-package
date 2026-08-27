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
/// The two members differ in where they take effect. ``overlayColors`` draws on
/// the user's screen, so it is compiled out of release builds. ``wireframeEmitter``
/// renders nothing and only hands your own code a description of a frame the SDK
/// already built, so it is delivered in any build — a release app can legitimately
/// want one, for example to attach the last wireframe to a crash report.
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
    /// Unlike ``overlayColors``, this is not restricted to debug builds.
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

    /// Whether to build a debug snapshot of each captured wireframe.
    ///
    /// `Codable`, and therefore the switch a cross-platform host can set: React Native's whole
    /// configuration crosses the bridge as JSON, so it cannot pass ``wireframeEmitter`` and
    /// instead sets this, leaving its bridge to attach the callback.
    ///
    /// A native caller has no use for it — providing ``wireframeEmitter`` is both the switch and
    /// the destination, and setting this without a callback delivers nowhere.
    ///
    /// - Default: `false`
    public var emitWireframes: Bool = false

    public init(
        overlayColors: DebugOverlayColors? = DebugOverlayColors(),
        emitWireframes: Bool = false,
        wireframeEmitter: ((MPWireframeDebugSnapshot) -> Void)? = nil
    ) {
        self.overlayColors = overlayColors
        self.emitWireframes = emitWireframes
        self.wireframeEmitter = wireframeEmitter
    }

    // `wireframeEmitter` is deliberately excluded: a closure has no JSON
    // representation. Cross-platform bridges decode this type from JSON and set
    // the callback directly, mirroring Android's `@Transient wireframeEmitter`.
    private enum CodingKeys: String, CodingKey {
        case overlayColors
        case emitWireframes
    }
}
