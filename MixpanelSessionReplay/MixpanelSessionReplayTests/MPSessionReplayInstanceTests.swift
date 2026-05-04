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
}
