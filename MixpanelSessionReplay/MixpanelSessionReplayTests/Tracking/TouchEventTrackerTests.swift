//
//  TouchEventTrackerTests.swift
//  MixpanelSessionReplayTests
//
//  Created by Ketan on 03/03/25.
//  Copyright © 2025 Mixpanel. All rights reserved.
//
//  Gesture-lifecycle coverage for the rrweb touch stream, mirroring Android's
//  `TouchEventRecorderTest.kt`. A gesture must produce TOUCH_START → zero or more
//  TOUCH_MOVE batches → TOUCH_END (or TOUCH_CANCEL); the server's after-frame
//  sampling is armed by TOUCH_END, so a missing boundary event silently degrades
//  summaries rather than breaking anything visible on device.
//
//  These drive `TouchEventTracker.handleTouches(_:)` directly — UIKit offers no way
//  to synthesize a `UIEvent`, and the state machine is the part worth testing.
//

import UIKit
import XCTest

@testable import MixpanelSessionReplay

/// Captures everything published to `EventPublisher` so a test can assert on the
/// exact `RawTouchEvent` sequence a gesture produced.
private final class CapturingTouchListener: EventListener {
    var events: [RawTouchEvent] = []

    func receivedTouchEvent(_ rawEvent: RawTouchEvent) {
        events.append(rawEvent)
    }

    func receivedScreenshotEvent(_ rawEvent: RawScreenshotEvent) {}
}

final class TouchEventTrackerTests: BaseTests {

    private var listener: CapturingTouchListener!

    override func setUpWithError() throws {
        try super.setUpWithError()
        TouchEventTracker.resetGesture()
        listener = CapturingTouchListener()
        EventPublisher.shared.subscribe(listener)
        drainPublisher()
    }

    override func tearDownWithError() throws {
        EventPublisher.shared.unsubscribe(listener)
        drainPublisher()
        listener = nil
        TouchEventTracker.resetGesture()
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// `EventPublisher` fans out on its own serial queue; block until it has.
    private func drainPublisher() {
        EventPublisher.shared.queue.sync {}
    }

    private func touch(
        _ phase: UITouch.Phase,
        x: CGFloat = 0,
        y: CGFloat = 0,
        at timestamp: Int64,
        pointer: Int = 1
    ) -> TouchEventData {
        TouchEventData(phase: phase, location: CGPoint(x: x, y: y), hash: pointer, timestamp: timestamp)
    }

    private func send(_ touches: TouchEventData...) {
        TouchEventTracker.handleTouches(touches)
        drainPublisher()
    }

    /// Flattens the captured stream to `(type, x, y, timestamp)` for interactions and
    /// `nil` type for move batches, so a test can assert order in one line.
    private var interactionTypes: [Int] {
        listener.events.compactMap {
            if case .interaction(let type, _, _) = $0 { return type }
            return nil
        }
    }

    private var moveBatches: [[TouchSample]] {
        listener.events.compactMap {
            if case .move(let samples) = $0 { return samples }
            return nil
        }
    }

    // MARK: - Gesture boundaries

    func testTap_emitsTouchStartThenTouchEnd() {
        send(touch(.began, x: 10, y: 20, at: 1_000))
        send(touch(.ended, x: 11, y: 21, at: 1_050))

        XCTAssertEqual(interactionTypes, [MouseInteraction.touchStart, MouseInteraction.touchEnd])
        XCTAssertTrue(moveBatches.isEmpty)

        guard case .interaction(_, let startPoint, let startTime) = listener.events[0] else {
            return XCTFail("expected an interaction")
        }
        XCTAssertEqual(startPoint, CGPoint(x: 10, y: 20))
        XCTAssertEqual(startTime, 1_000)

        guard case .interaction(_, let endPoint, let endTime) = listener.events[1] else {
            return XCTFail("expected an interaction")
        }
        XCTAssertEqual(endPoint, CGPoint(x: 11, y: 21))
        XCTAssertEqual(endTime, 1_050)
    }

    /// The bug this suite exists for: before the lifecycle fix a gesture emitted a lone
    /// TOUCH_START, so the server never learned a tap had completed.
    func testTouchStart_isNotTheOnlyEventAGestureProduces() {
        send(touch(.began, at: 1_000))
        XCTAssertEqual(interactionTypes, [MouseInteraction.touchStart])

        send(touch(.ended, at: 1_100))
        XCTAssertEqual(interactionTypes.last, MouseInteraction.touchEnd)
    }

    func testCancel_emitsTouchCancelAndEndsGesture() {
        send(touch(.began, at: 1_000))
        send(touch(.cancelled, at: 1_080))

        XCTAssertEqual(interactionTypes, [MouseInteraction.touchStart, MouseInteraction.touchCancel])

        // The gesture is over: a fresh down starts a new one rather than being swallowed.
        send(touch(.began, at: 2_000))
        XCTAssertEqual(interactionTypes.last, MouseInteraction.touchStart)
    }

    func testLongPress_stillEndsGesture() {
        send(touch(.began, x: 5, y: 5, at: 1_000))
        send(touch(.ended, x: 5, y: 5, at: 4_000))

        XCTAssertEqual(interactionTypes, [MouseInteraction.touchStart, MouseInteraction.touchEnd])
        XCTAssertTrue(moveBatches.isEmpty, "a stationary press has no path to report")
    }

    func testMoveWithoutDown_isIgnored() {
        // Recording started mid-gesture: a path with no start is worse than no path.
        send(touch(.moved, x: 30, y: 30, at: 1_000))
        send(touch(.moved, x: 40, y: 40, at: 1_100))
        send(touch(.ended, x: 50, y: 50, at: 1_200))

        XCTAssertTrue(listener.events.isEmpty)
    }

    func testSecondaryPointer_isIgnored() {
        send(touch(.began, x: 10, y: 10, at: 1_000, pointer: 1))
        // Second finger lands mid-gesture; it must not open a second start/end pair.
        send(touch(.began, x: 90, y: 90, at: 1_020, pointer: 2))
        send(touch(.moved, x: 95, y: 95, at: 1_200, pointer: 2))
        send(touch(.ended, x: 95, y: 95, at: 1_300, pointer: 2))
        send(touch(.ended, x: 12, y: 12, at: 1_400, pointer: 1))

        XCTAssertEqual(interactionTypes, [MouseInteraction.touchStart, MouseInteraction.touchEnd])
        XCTAssertTrue(moveBatches.isEmpty, "the ignored pointer's path must not be sampled")
    }

    // MARK: - Move sampling

    func testSwipe_emitsMoveBatchBeforeTouchEnd() {
        send(touch(.began, x: 0, y: 0, at: 1_000))
        send(touch(.moved, x: 10, y: 0, at: 1_060))
        send(touch(.moved, x: 20, y: 0, at: 1_120))
        send(touch(.ended, x: 30, y: 0, at: 1_180))

        // Order matters: the path drains before the boundary event.
        XCTAssertEqual(listener.events.count, 3)
        guard case .interaction(let first, _, _) = listener.events[0], first == MouseInteraction.touchStart
        else { return XCTFail("expected TOUCH_START first") }
        guard case .move(let samples) = listener.events[1] else {
            return XCTFail("expected the move batch before TOUCH_END")
        }
        guard case .interaction(let last, _, _) = listener.events[2], last == MouseInteraction.touchEnd
        else { return XCTFail("expected TOUCH_END last") }

        XCTAssertEqual(samples.map(\.point), [CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 0)])
        XCTAssertEqual(samples.map(\.timestamp), [1_060, 1_120])
    }

    func testMoves_closerThanSampleIntervalAreDropped() {
        send(touch(.began, x: 0, y: 0, at: 1_000))
        // The floor is measured against the last *sampled* point, which starts at the
        // down — so 20ms and 40ms in are both under it.
        send(touch(.moved, x: 1, y: 0, at: 1_020))
        send(touch(.moved, x: 2, y: 0, at: 1_040))
        // 100ms clear of the down: this one lands and becomes the new reference.
        send(touch(.moved, x: 3, y: 0, at: 1_100))
        // 20ms after that reference, so dropped again.
        send(touch(.moved, x: 4, y: 0, at: 1_120))
        send(touch(.ended, x: 4, y: 0, at: 1_200))

        XCTAssertEqual(moveBatches.count, 1)
        XCTAssertEqual(moveBatches[0].map(\.point), [CGPoint(x: 3, y: 0)])
    }

    func testLongDrag_flushesBatchOnceItSpansTheBatchInterval() {
        send(touch(.began, x: 0, y: 0, at: 0))
        // Sample every 50ms; the batch spans 500ms at the 11th sample.
        for step in 1...11 {
            send(touch(.moved, x: CGFloat(step), y: 0, at: Int64(step) * 50))
        }

        XCTAssertEqual(moveBatches.count, 1, "batch should flush mid-gesture, not wait for the lift")
        let batch = moveBatches[0]
        XCTAssertEqual(batch.first?.timestamp, 50)
        XCTAssertEqual(batch.last?.timestamp, 550)
        XCTAssertEqual(
            batch.last!.timestamp - batch.first!.timestamp, TouchSampling.moveBatchIntervalMs)

        send(touch(.ended, x: 12, y: 0, at: 600))
        XCTAssertEqual(moveBatches.count, 1, "the flushed samples must not be re-sent on lift")
    }

    /// A sustained drag stays bounded. In practice the 500ms span check always fires
    /// first — at the 50ms sampling floor a batch would have to run ~5s to reach 100
    /// positions — so `maxPositionsPerBatch` is a backstop against a pathological
    /// timestamp stream rather than something a real gesture hits.
    func testSustainedDrag_keepsEveryBatchWithinTheCap() {
        send(touch(.began, x: 0, y: 0, at: 0))
        for step in 1...TouchSampling.maxPositionsPerBatch {
            send(touch(.moved, x: CGFloat(step), y: 0, at: Int64(step) * 50))
        }

        XCTAssertFalse(moveBatches.isEmpty)
        for batch in moveBatches {
            XCTAssertLessThanOrEqual(batch.count, TouchSampling.maxPositionsPerBatch)
        }
        // Nothing is dropped: every sampled position reaches some batch, and one
        // partial batch is still pending behind the not-yet-delivered lift.
        let flushed = moveBatches.reduce(0) { $0 + $1.count }
        send(touch(.ended, x: 999, y: 0, at: 100 * 50 + 50))
        XCTAssertEqual(moveBatches.reduce(0) { $0 + $1.count }, TouchSampling.maxPositionsPerBatch)
        XCTAssertGreaterThan(TouchSampling.maxPositionsPerBatch, flushed)
    }

    func testGesture_doesNotLeakSamplesIntoTheNextGesture() {
        // First gesture ends before its single sample ever spans a batch interval.
        send(touch(.began, x: 0, y: 0, at: 1_000))
        send(touch(.moved, x: 5, y: 0, at: 1_060))
        send(touch(.ended, x: 5, y: 0, at: 1_100))

        XCTAssertEqual(moveBatches.count, 1)
        XCTAssertEqual(moveBatches[0].map(\.point), [CGPoint(x: 5, y: 0)])

        // Second gesture must report only its own path.
        send(touch(.began, x: 80, y: 80, at: 2_000))
        send(touch(.moved, x: 85, y: 80, at: 2_060))
        send(touch(.ended, x: 85, y: 80, at: 2_100))

        XCTAssertEqual(moveBatches.count, 2)
        XCTAssertEqual(moveBatches[1].map(\.point), [CGPoint(x: 85, y: 80)])
    }

    func testTimestamps_comeFromTheTouchNotTheClock() {
        // Timestamps are lifted off UITouch, so a gesture replayed from the past keeps
        // its own times rather than being stamped with "now".
        send(touch(.began, at: 42))
        send(touch(.ended, at: 99))

        XCTAssertEqual(listener.events.map(\.timestamp), [42, 99])
    }

    func testMoveBatchTimestamp_isItsFinalSample() {
        send(touch(.began, x: 0, y: 0, at: 1_000))
        send(touch(.moved, x: 1, y: 0, at: 1_060))
        send(touch(.moved, x: 2, y: 0, at: 1_120))
        send(touch(.ended, x: 2, y: 0, at: 1_180))

        guard case .move(let samples) = listener.events[1] else { return XCTFail("expected a batch") }
        XCTAssertEqual(listener.events[1].timestamp, samples.last?.timestamp)
        XCTAssertEqual(listener.events[1].timestamp, 1_120)
    }
}
