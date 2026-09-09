//
//  MPSessionReplayInstanceTests.swift
//  MixpanelSessionReplayTests
//
//  Created by Ketan on 27/02/25.
//  Copyright © 2025 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

class MPSessionReplayInstanceTests: BaseTests {
    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    func testInitialization() {
        var config = MPSessionReplayConfig()
        config.wifiOnly = true
        config.recordingSessionsPercent = 0
        config.autoMaskedViews = [.text, .image]
        let instance = MPSessionReplayInstance(
            token: "test-token",
            distinctId: "test-distinct-id",
            config: config
        )
        instance.loggingEnabled = false

        // verify config properties
        XCTAssertEqual(instance.token, "test-token")
        XCTAssertEqual(instance.wifiOnly, true)
        XCTAssertFalse(instance.shouldRecordSession)
        XCTAssertFalse(instance.loggingEnabled)

        // verify the masking set
        XCTAssertTrue(SensitiveViewManager.shared.maskAllText)
        XCTAssertTrue(SensitiveViewManager.shared.maskAllImages)
        XCTAssertFalse(SensitiveViewManager.shared.maskAllWebViews)
    }

    func testStartRecording_WhenRecordingDisabled() {
        let oldReplayId = SessionManager.shared.replayId
        let config = MPSessionReplayConfig(autoStartRecording: false)
        let instance = MPSessionReplayInstance(token: "test-token", distinctId: "test-distinct-id", config: config)

        instance.startRecording(sessionsPercent: 0)

        let newReplayId = SessionManager.shared.replayId

        XCTAssertFalse(instance.shouldRecordSession)
        XCTAssertFalse(instance.isRecording)
        XCTAssertEqual(
            oldReplayId,
            newReplayId,
            "Old replay id and new replay id should be equal, As recording is disabled, no new replay id should be generated"
        )
    }

    func testStartRecording_WhenRecordingEnabled() {
        MPSessionReplayInstance.isSwizzled = false
        let oldReplayId = SessionManager.shared.replayId
        startRecording()
        let newReplayId = SessionManager.shared.replayId

        XCTAssertTrue(instance.shouldRecordSession)
        XCTAssertTrue(instance.isRecording)
        XCTAssertTrue(mockEventService.clearEventsCalled)
        XCTAssertTrue(mockFlushService.startCalled)
        XCTAssertTrue(MPSessionReplayInstance.isSwizzled)
        XCTAssertNotEqual(
            oldReplayId,
            newReplayId,
            "Old replay id should not be equal to new replay id, recording session should have started with a new replay id"
        )
    }

    func testAutoStartRecording() {
        let oldReplayId = SessionManager.shared.replayId
        let config = MPSessionReplayConfig()
        let instance = MPSessionReplayInstance(
            token: "test-token", distinctId: "test-distinct-id", config: config)

        let newReplayId = SessionManager.shared.replayId

        XCTAssertTrue(instance.shouldRecordSession)
        XCTAssertTrue(instance.isRecording)
        XCTAssertNotEqual(
            oldReplayId, newReplayId,
            "Old replay id should not be equal to new replay id, recording session should have started with a new replay id"
        )
    }

    func testStartRecording_WhenRecordingIsAlreadyStarted() {
        startRecording()

        let oldReplayId = SessionManager.shared.replayId

        instance.startRecording()
        let newReplayId = SessionManager.shared.replayId

        XCTAssertEqual(
            oldReplayId,
            newReplayId,
            "Old replay id and new replay id should be equal, As recording is already started, no new replay id should be generated"
        )
    }

    func testCaptureScreenshot() {
        startRecording()
        let lastRecord = MPSessionReplayInstance.lastRecordTimestamp
        sleep(1)
        instance.captureScreenshot()
        XCTAssertNotEqual(
            lastRecord,
            MPSessionReplayInstance.lastRecordTimestamp,
            "The lastRecordTimestamp value should be changed after calling captureScreenshot method"
        )
    }

    /// A new recording session must clear wireframe dedup state.
    ///
    /// The emitter is built once per SDK lifetime and survives a stop/start cycle, so
    /// without an explicit reset the new replay's first frame is compared against the
    /// previous replay's last one. Backgrounding and foregrounding onto an unchanged
    /// screen then dedups the opening `mp_wireframe` away, leaving a screenshot with
    /// nothing to describe it — the one frame an AI summary most needs.
    ///
    /// Asserted at the `startRecording` call site on purpose: a test that calls
    /// `resetDedup()` directly still passes if the call site is deleted.
    func testStartRecording_ResetsWireframeDedupState() throws {
        let emitter = WireframeEmitter(options: MPWireframesOptions())
        ScreenRecorder.shared.wireframeEmitter = emitter
        defer { ScreenRecorder.shared.wireframeEmitter = nil }

        // Prime dedup state the way a previous session's last frame would.
        emitter.emit(
            elements: [
                WireframeElement.from(
                    role: .text, text: "unchanged",
                    rect: CGRect(x: 0, y: 0, width: 10, height: 10),
                    decision: .none)
            ],
            viewport: (100, 100), maskBounds: [])

        // Wait on the condition, not on a guessed interval. The emitter hands the payload
        // to its own queue, and a fixed 0.2s delay is a bet on how quickly a machine gets
        // round to it — one this lost intermittently on CI, failing the precondition below
        // rather than the behaviour under test. Polling the real state is faster in the
        // common case and does not have to be re-tuned for slower hardware.
        let primed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in emitter.lastPayloadHash != nil },
            object: nil)
        wait(for: [primed], timeout: 10.0)

        instance.startRecording()

        XCTAssertNil(
            emitter.lastPayloadHash,
            "startRecording must reset dedup so the new session's first frame publishes")
    }

    func testStopRecording() {
        var observer: NSObjectProtocol?
        let expectation = expectation(description: "Unregister notification received")

        observer = NotificationCenter.default.addObserver(
            forName: MPSessionReplaySender.unregisterNotificationName,
            object: nil,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }

        instance.startRecording()
        XCTAssertTrue(instance.shouldRecordSession)
        XCTAssertTrue(instance.isRecording)

        instance.stopRecording()

        wait(for: [expectation], timeout: 2.0)

        XCTAssertFalse(instance.shouldRecordSession)
        XCTAssertTrue(mockFlushService.stopCalled)
        XCTAssertFalse(instance.isRecording)
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func testStopRecording_ClearsSensitiveViewCache() {
        // Add some views to the cache
        let label = UILabel()
        SensitiveViewManager.shared.knownSensitiveViews.insert(label)

        instance.startRecording()
        XCTAssertTrue(instance.isRecording)

        instance.stopRecording()

        // Verify cache was cleared
        XCTAssertFalse(
            SensitiveViewManager.shared.knownSensitiveViews.contains(label),
            "Sensitive view cache should be cleared when recording stops"
        )
    }

    func testFlush() {
        instance.flush()
        sleep(2)

        XCTAssertTrue(mockFlushService.flushEventsForAllCalled)
    }

    func testAppDidEnterBackground() {
        startRecording()
        instance.appDidEnterBackground()

        XCTAssertFalse(instance.shouldRecordSession)
        XCTAssertFalse(instance.isRecording)
        XCTAssertTrue(mockFlushService.stopCalled)
    }

    func testMarkScreenDirty() {
        instance.markScreenDirty()
        XCTAssertTrue(instance.isScreenDirty())
    }

    func testProcessScreeshot() {
        // Create expectation before triggering async operation
        let expectation = expectation(description: "EventService.enqueueEvent called")
        mockEventService.enqueueEventExpectation = expectation

        instance.markScreenDirty()
        instance.processScreenshot(
            Data(),
            timestamp: TimestampUtils.timestamp()
        )

        // Wait for async chain to complete (timeout provides headroom for CI)
        wait(for: [expectation], timeout: 10.0)

        // Assertions now run after enqueueEvent completes
        XCTAssertFalse(instance.isScreenDirty())
        XCTAssertTrue(mockEventService.enqueueEventCalled)
    }

    func testAddRemoveSensitiveClass() {
        instance.addSensitiveClass(NSString.self as AnyClass)
        XCTAssertTrue(SensitiveViewManager.shared.sensitiveClasses.count == 1)

        instance.removeSensitiveClass(NSString.self as AnyClass)
        XCTAssertTrue(SensitiveViewManager.shared.sensitiveClasses.count == 0)
    }

    func testIdentifyUpdatesFlushServiceWithNewDistinctId() {
        let newDistinctId = "test-distinct-id-2"
        let finished = expectation(description: "identify completion")

        instance.identify(distinctId: newDistinctId) {
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)

        XCTAssertEqual(instance.flushService.getDistinctId(), newDistinctId)
    }

    // MARK: - getSessionReplayURL Tests

    func testGetSessionReplayUrl_ReturnsNilWhenNotRecording() {
        XCTAssertFalse(instance.isRecording)
        XCTAssertNil(instance.getSessionReplayURL())
    }

    func testGetSessionReplayUrl_ReturnsCorrectURLWhenRecording() {
        startRecording()
        XCTAssertTrue(instance.isRecording)

        let url = instance.getSessionReplayURL()
        XCTAssertNotNil(url)

        let replayId = SessionManager.shared.replayId
        let distinctId = instance.flushService.getDistinctId()
        let token = instance.token

        XCTAssertTrue(url!.contains("https://mixpanel.com/projects/replay-redirect"))
        XCTAssertTrue(url!.contains("replay_id=\(replayId)"))
        XCTAssertTrue(url!.contains("distinct_id=\(distinctId)"))
        XCTAssertTrue(url!.contains("token=\(token)"))
    }

    func testGetSessionReplayUrl_ReturnsValidURLWithSpecialCharacters() {
        // Create instance with special characters that require encoding
        let specialDistinctId = "user+test&param=value"
        let config = MPSessionReplayConfig(
            wifiOnly: false, autoStartRecording: false, enableLogging: false)
        let testInstance = MPSessionReplayInstance(
            token: "test-token",
            distinctId: specialDistinctId,
            config: config
        )

        testInstance.startRecording(sessionsPercent: 100)
        XCTAssertTrue(testInstance.isRecording)

        let urlString = testInstance.getSessionReplayURL()
        XCTAssertNotNil(urlString)

        // Verify it's a valid URL that can be parsed
        let url = URL(string: urlString!)
        XCTAssertNotNil(url, "getSessionReplayURL must return a valid URL")

        // Verify all query parameters can be correctly extracted
        let components = URLComponents(string: urlString!)
        XCTAssertNotNil(components)

        let distinctIdItem = components?.queryItems?.first { $0.name == "distinct_id" }
        XCTAssertEqual(
            distinctIdItem?.value, specialDistinctId,
            "distinctId should be properly encoded and decodable")
        let encodedQuery = components?.percentEncodedQuery
        XCTAssertTrue(encodedQuery?.contains("distinct_id=user%2Btest%26param%3Dvalue") == true)
        XCTAssertFalse(encodedQuery?.contains("distinct_id=user+test") == true)

        testInstance.stopRecording()
    }
}
