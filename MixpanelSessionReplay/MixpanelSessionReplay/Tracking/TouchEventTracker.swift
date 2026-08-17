//
//  TouchEventTracker.swift
//  MixpanelSessionReplay
//
//  Created by Jared McFarland on 10/24/24.
//  Copyright © 2024 Mixpanel. All rights reserved.
//

#if os(iOS)
import Foundation
import UIKit

/// The values we need off a `UITouch`, lifted on the main thread so the rest of the
/// pipeline never touches UIKit state.
struct TouchEventData {
    var phase: UITouch.Phase
    var location: CGPoint
    var hash: Int
    /// Wall-clock milliseconds, converted from `UITouch.timestamp`.
    var timestamp: Int64
}

/// Translates the window's raw `UIEvent` stream into rrweb touch events.
///
/// A gesture becomes `TOUCH_START` → zero or more `TOUCH_MOVE` position batches →
/// `TOUCH_END` (or `TOUCH_CANCEL`). Only the primary pointer is tracked, matching
/// rrweb-web; secondary pointers going down or up mid-gesture are ignored.
///
/// Nothing here is deferred: batches drain on the next sampled move or when the gesture
/// ends, so no position is held behind a timer and every event carries the timestamp of
/// the `UITouch` that produced it.
struct TouchEventTracker {
    /// Identifies the one pointer we follow. `nil` means no gesture is in flight.
    private static var primaryTouchHash: Int?
    private static var pendingSamples: [TouchSample] = []
    private static var lastSampledTimestamp: Int64 = 0

    static func processEvent(_ event: UIEvent) {
        guard MPSessionReplay.getInstance()?.isRecording == true else {
            return
        }
        guard event.type == .touches else {
            return
        }
        guard let window = ViewUtils.getCurrentWindow() else {
            return
        }

        // As UITouch can be accessed on the main thread, grab the required values from the touch
        // and do the rest processing with that data on the background thread
        let touchEventsData: [TouchEventData] = touches(for: event, in: window)

        DispatchQueue.main.async {
            handleTouches(touchEventsData)
        }
    }

    private static func touches(for event: UIEvent, in window: UIWindow) -> [TouchEventData] {
        // Get the touch events only for the current window
        guard let touches = event.touches(for: window) else { return [] }
        return touches.map { touch in
            TouchEventData(
                phase: touch.phase,
                location: touch.location(in: window),
                hash: ObjectIdentifier(touch).hashValue,
                timestamp: TimestampUtils.convertTouchTimestamp(touch.timestamp))
        }
    }

    /// Drives the gesture state machine. Split out from `processEvent(_:)` so it can be
    /// exercised without synthesizing a `UIEvent`, which UIKit offers no way to build.
    /// Must run on the main thread — it mutates the static gesture state.
    static func handleTouches(_ touches: [TouchEventData]) {
        for touch in touches {
            switch touch.phase {
                case .began:
                    gestureBegan(touch)
                case .moved:
                    gestureMoved(touch)
                case .ended:
                    gestureEnded(touch, interaction: MouseInteraction.touchEnd)
                case .cancelled:
                    gestureEnded(touch, interaction: MouseInteraction.touchCancel)
                default:
                    break
            }
        }
    }

    private static func gestureBegan(_ touch: TouchEventData) {
        // Only the primary pointer is tracked; a second finger landing mid-gesture would
        // otherwise interleave a second start/end pair into the same path.
        guard primaryTouchHash == nil else { return }

        resetGesture()
        primaryTouchHash = touch.hash
        lastSampledTimestamp = touch.timestamp

        MPSessionReplay.getInstance()?.debugMaskOverlayManager?.enableTransitioningState()
        publishInteraction(MouseInteraction.touchStart, touch)
        MPSessionReplay.getInstance()?.record(touch.timestamp)
    }

    private static func gestureMoved(_ touch: TouchEventData) {
        // A move from a pointer we never saw go down means either a secondary finger or a
        // recording that started mid-gesture; wait for the next clean gesture rather than
        // emitting a path with no start.
        guard touch.hash == primaryTouchHash else { return }
        guard touch.timestamp - lastSampledTimestamp >= TouchSampling.moveSampleIntervalMs else {
            return
        }

        lastSampledTimestamp = touch.timestamp
        pendingSamples.append(TouchSample(point: touch.location, timestamp: touch.timestamp))

        guard let first = pendingSamples.first, let last = pendingSamples.last else { return }
        if last.timestamp - first.timestamp >= TouchSampling.moveBatchIntervalMs
            || pendingSamples.count >= TouchSampling.maxPositionsPerBatch
        {
            flushSamples()
        }
    }

    private static func gestureEnded(_ touch: TouchEventData, interaction: Int) {
        guard touch.hash == primaryTouchHash else { return }

        // Drain the path before the boundary event so the stream stays chronological.
        flushSamples()
        publishInteraction(interaction, touch)
        resetGesture()
        MPSessionReplay.getInstance()?.record(touch.timestamp)
    }

    private static func flushSamples() {
        guard !pendingSamples.isEmpty else { return }
        EventPublisher.shared.publishTouchEvent(.move(samples: pendingSamples))
        pendingSamples.removeAll()
    }

    private static func publishInteraction(_ type: Int, _ touch: TouchEventData) {
        EventPublisher.shared.publishTouchEvent(
            .interaction(type: type, point: touch.location, timestamp: touch.timestamp))
    }

    /// Clears all in-flight gesture state. Also the reset hook for tests, since the state
    /// is static and would otherwise leak between cases.
    static func resetGesture() {
        pendingSamples.removeAll()
        primaryTouchHash = nil
        lastSampledTimestamp = 0
    }
}
#endif
