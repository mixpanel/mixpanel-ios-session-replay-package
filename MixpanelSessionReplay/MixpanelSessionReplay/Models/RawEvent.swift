//
//  Event.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation

/// One sampled point of a drag, in window-relative logical points, paired with the
/// wall-clock millisecond at which the finger was actually there (derived from
/// `UITouch.timestamp`, not from when the SDK got around to processing it).
struct TouchSample {
    var point: CGPoint
    var timestamp: Int64
}

/// A touch captured off the window's `UIEvent` stream, before it is encoded into an rrweb
/// incremental snapshot by `EventHandler`.
///
/// Timestamps are wall-clock milliseconds taken from the originating `UITouch`, so no
/// pipeline-lag fudge factor is applied downstream.
enum RawTouchEvent {
    /// A discrete gesture boundary — down, lift, or cancel — carrying a single point.
    /// Encoded as `source = mouseInteraction`, `type` = a `MouseInteraction` value.
    case interaction(type: Int, point: CGPoint, timestamp: Int64)

    /// A batch of sampled drag positions between a down and a lift. Encoded as
    /// `source = touchMove`. `samples` is never empty — `TouchEventTracker` is the only
    /// producer and drops empty batches — and is ordered oldest to newest, so the batch's
    /// timestamp is that of its final sample.
    case move(samples: [TouchSample])

    var timestamp: Int64 {
        switch self {
            case .interaction(_, _, let timestamp): return timestamp
            case .move(let samples): return samples.last?.timestamp ?? 0
        }
    }
}

struct RawScreenshotEvent {
    var data: Data
    var isInitial: Bool  // is initial screenshot
    var timestamp: Int64
}
