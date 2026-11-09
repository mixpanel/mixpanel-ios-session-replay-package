//
//  MPSessionReplayInstanceTests.swift
//  MixpanelSessionReplayTests
//
//  Created by Ketan on 27/02/25.
//  Copyright © 2025 Mixpanel. All rights reserved.
//

import MixpanelSwiftCommon
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
        wait(for: [expectation], timeout: 30.0)

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

    func testIdentifyWithIdentityUpdatesDistinctIdAndIdentity() {
        let identity = MixpanelIdentity(userId: "user_123", companyId: "acme", deviceId: "device-1")
        let finished = expectation(description: "identify completion")

        instance.identify(identity: identity) {
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)

        XCTAssertTrue(mockFlushService.flushEventsForAllCalled)
        XCTAssertEqual(
            instance.flushService.getIdentifiers(), ReplayIdentifiers(distinctId: "user_123", identity: identity))
    }

    func testIdentifyWithDeviceOnlyIdentityUsesDeviceDistinctId() {
        let identity = MixpanelIdentity(userId: nil, companyId: nil, deviceId: "device-1")
        let finished = expectation(description: "identify completion")

        instance.identify(identity: identity) {
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)

        XCTAssertEqual(instance.flushService.getDistinctId(), "$device:device-1")
        XCTAssertEqual(instance.flushService.getIdentifiers().identity, identity)
    }

    func testIdentifyWithDistinctIdClearsIdentity() {
        let identified = expectation(description: "identify identity completion")
        instance.identify(identity: MixpanelIdentity(userId: "user_123", companyId: "acme")) {
            identified.fulfill()
        }
        wait(for: [identified], timeout: 2)

        let finished = expectation(description: "identify distinct id completion")
        instance.identify(distinctId: "plain-distinct-id") {
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)

        XCTAssertEqual(
            instance.flushService.getIdentifiers(), ReplayIdentifiers(distinctId: "plain-distinct-id", identity: nil))
    }

    func testIdentifyWithSameDistinctIdClearsIdentity() {
        let identified = expectation(description: "identify identity completion")
        instance.identify(identity: MixpanelIdentity(userId: "user_123", companyId: "acme", deviceId: "device-1")) {
            identified.fulfill()
        }
        wait(for: [identified], timeout: 2)

        let finished = expectation(description: "identify distinct id completion")
        instance.identify(distinctId: "user_123") {
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)

        XCTAssertEqual(
            instance.flushService.getIdentifiers(), ReplayIdentifiers(distinctId: "user_123", identity: nil))
        startRecording()
        XCTAssertEqual(
            instance.getSessionReplayURL(),
            "https://mixpanel.com/projects/replay-redirect?replay_id=\(SessionManager.shared.replayId)"
                + "&distinct_id=user_123&token=test-token")
    }

    func testIdentityChangesWaitForRunningFlush() {
        let identity = MixpanelIdentity(userId: "user_123", companyId: "acme", deviceId: "device-1")
        let identified = expectation(description: "identify identity completion")
        instance.identify(identity: identity) {
            identified.fulfill()
        }
        wait(for: [identified], timeout: 2)

        // Hold the flush queue as a running flush would
        let flushStarted = DispatchSemaphore(value: 0)
        let releaseFlush = DispatchSemaphore(value: 0)
        instance.flushService.flushSerialQueue.async {
            flushStarted.signal()
            releaseFlush.wait()
        }
        flushStarted.wait()

        let cleared = expectation(description: "identify same distinct id completion")
        instance.identify(distinctId: "user_123") {
            cleared.fulfill()
        }
        let otherIdentity = MixpanelIdentity(userId: "user_456", companyId: "acme", deviceId: "device-1")
        let reidentified = expectation(description: "identify other identity completion")
        instance.identify(identity: otherIdentity) {
            reidentified.fulfill()
        }
        XCTAssertEqual(
            instance.flushService.getIdentifiers(), ReplayIdentifiers(distinctId: "user_123", identity: identity),
            "identity changes must not touch the flush request while a flush is running")

        releaseFlush.signal()
        wait(for: [cleared, reidentified], timeout: 2, enforceOrder: true)
        XCTAssertEqual(
            instance.flushService.getIdentifiers(),
            ReplayIdentifiers(distinctId: "user_456", identity: otherIdentity))
    }

    func testLastIdentifyWinsWhileFlushQueueIsBusy() {
        for wifiOnlySkipsUpload in [false, true] {
            let identityA = MixpanelIdentity(userId: "user_a", companyId: "acme", deviceId: "device-1")
            let identityB = MixpanelIdentity(userId: "user_b", companyId: "acme", deviceId: "device-1")
            let networkMonitor = MockNetworkMonitor()
            networkMonitor.isUsingWiFiOverride = !wifiOnlySkipsUpload
            let eventService = EventService()
            eventService.eventHandler?.shutdown()
            let flushService = FlushService(
                token: "test-token", distinctId: "user_a", identity: identityA, eventService: eventService,
                wifiOnly: wifiOnlySkipsUpload, flushRequest: nil, networkMonitor: networkMonitor,
                flushInterval: ReplaySettings.flushInterval)
            instance.eventService = eventService
            instance.flushService = flushService

            // Hold the flush queue as a running flush would
            let flushStarted = DispatchSemaphore(value: 0)
            let releaseFlush = DispatchSemaphore(value: 0)
            flushService.flushSerialQueue.async {
                flushStarted.signal()
                releaseFlush.wait()
            }
            flushStarted.wait()

            let identifiedB = expectation(description: "identify B completion")
            instance.identify(identity: identityB) { identifiedB.fulfill() }
            let identifiedA = expectation(description: "identify A completion")
            instance.identify(identity: identityA) { identifiedA.fulfill() }
            let plainId = expectation(description: "identify plain distinct id completion")
            instance.identify(distinctId: "user_a") { plainId.fulfill() }
            let identifiedAAgain = expectation(description: "identify A again completion")
            instance.identify(identity: identityA) { identifiedAAgain.fulfill() }

            releaseFlush.signal()
            wait(for: [identifiedB, identifiedA, plainId, identifiedAAgain], timeout: 2, enforceOrder: true)
            XCTAssertEqual(
                flushService.getIdentifiers(), ReplayIdentifiers(distinctId: "user_a", identity: identityA),
                "the last identify must win (wifiOnly skipping upload: \(wifiOnlySkipsUpload))")

            // An unchanged identity is a no-op that still completes
            let unchanged = expectation(description: "identify unchanged completion")
            instance.identify(identity: identityA) { unchanged.fulfill() }
            wait(for: [unchanged], timeout: 2)
            XCTAssertFalse(flushService.hasPendingIdentityChanges)
            XCTAssertEqual(
                flushService.getIdentifiers(), ReplayIdentifiers(distinctId: "user_a", identity: identityA))
        }
    }

    func testConcurrentIdentifyDuringFlushesKeepsIdentifiersConsistent() {
        let companyA = MixpanelIdentity(userId: "user_123", companyId: "company-a", deviceId: "device-1")
        let companyB = MixpanelIdentity(userId: "user_123", companyId: "company-b", deviceId: "device-1")
        let eventService = EventService()
        eventService.eventHandler?.shutdown()
        let flushService = FlushService(
            token: "test-token", distinctId: "user_123", identity: companyA, eventService: eventService,
            wifiOnly: false, flushRequest: nil, flushInterval: ReplaySettings.flushInterval)
        instance.eventService = eventService
        instance.flushService = flushService

        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil), Data(), nil)
        }
        let replayStartTime = SessionManager.shared.replayStartTime
        defer {
            URLProtocol.unregisterClass(MockURLProtocol.self)
            MockURLProtocol.requestHandler = nil
            SessionManager.shared.replayStartTime = replayStartTime
        }
        SessionManager.shared.replayStartTime = Date().timeIntervalSince1970 - 10

        let iterations = 200
        let group = DispatchGroup()
        let instance = self.instance!
        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            group.enter()
            switch index % 4 {
            case 0:
                eventService.enqueueEvent(
                    SessionEvent(type: EventType.incrementalSnapshot, data: nil, timestamp: TimestampUtils.timestamp()))
                flushService.flushEvents(forAll: true) { group.leave() }
            case 1:
                instance.identify(identity: companyA) { group.leave() }
            case 2:
                instance.identify(identity: companyB) { group.leave() }
            default:
                instance.identify(distinctId: "user_123") { group.leave() }
            }
        }
        let finished = expectation(description: "all calls complete")
        group.notify(queue: .main) { finished.fulfill() }
        wait(for: [finished], timeout: 30)

        let cleared = expectation(description: "final identify completion")
        instance.identify(distinctId: "user_123") { cleared.fulfill() }
        wait(for: [cleared], timeout: 5)
        XCTAssertEqual(flushService.getIdentifiers(), ReplayIdentifiers(distinctId: "user_123", identity: nil))
    }

    func testQueuedEventsUploadWithIdentityTheyWereCapturedWith() {
        let companyA = MixpanelIdentity(userId: "user_123", companyId: "company-a", deviceId: "device-1")
        let companyB = MixpanelIdentity(userId: "user_123", companyId: "company-b", deviceId: "device-1")

        // Real services, with uploads deferred until Wi-Fi is back
        let eventService = EventService()
        eventService.eventHandler?.shutdown()
        let networkMonitor = MockNetworkMonitor()
        networkMonitor.isUsingWiFiOverride = false
        instance.eventService = eventService
        instance.flushService = FlushService(
            token: "test-token", distinctId: "user_123", identity: companyA, eventService: eventService,
            wifiOnly: true, networkMonitor: networkMonitor, flushInterval: ReplaySettings.flushInterval)

        let sentLock = NSLock()
        var sent: [[URLQueryItem]] = []
        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.requestHandler = { request in
            let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
            sentLock.lock()
            sent.append(items ?? [])
            sentLock.unlock()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil), Data(), nil)
        }
        let replayStartTime = SessionManager.shared.replayStartTime
        defer {
            URLProtocol.unregisterClass(MockURLProtocol.self)
            MockURLProtocol.requestHandler = nil
            SessionManager.shared.replayStartTime = replayStartTime
        }
        SessionManager.shared.replayStartTime = Date().timeIntervalSince1970 - 10

        func event() -> SessionEvent {
            SessionEvent(type: EventType.incrementalSnapshot, data: nil, timestamp: TimestampUtils.timestamp())
        }

        eventService.enqueueEvent(event())
        eventService.enqueueEvent(event())

        let identified = expectation(description: "identify completion")
        instance.identify(identity: companyB) {
            identified.fulfill()
        }
        wait(for: [identified], timeout: 2)
        XCTAssertEqual(eventService.eventsCount, 2, "the upload is deferred, so company A's events are still queued")

        eventService.enqueueEvent(event())

        networkMonitor.isUsingWiFiOverride = true
        let flushed = expectation(description: "flush completion")
        instance.flushService.flushEvents(forAll: true) {
            flushed.fulfill()
        }
        wait(for: [flushed], timeout: 10)

        sentLock.lock()
        let batches = sent
        sentLock.unlock()
        func identityItems(_ items: [URLQueryItem]) -> [URLQueryItem] {
            items.filter { ["distinct_id", "$user_id", "$company_id", "$device_id"].contains($0.name) }
        }
        XCTAssertEqual(
            batches.map(identityItems),
            [
                [
                    URLQueryItem(name: "distinct_id", value: "user_123"),
                    URLQueryItem(name: "$user_id", value: "user_123"),
                    URLQueryItem(name: "$company_id", value: "company-a"),
                    URLQueryItem(name: "$device_id", value: "device-1"),
                ],
                [
                    URLQueryItem(name: "distinct_id", value: "user_123"),
                    URLQueryItem(name: "$user_id", value: "user_123"),
                    URLQueryItem(name: "$company_id", value: "company-b"),
                    URLQueryItem(name: "$device_id", value: "device-1"),
                ],
            ])
        XCTAssertTrue(eventService.isEventsEmpty)
    }

    func testIdentifyWithInvalidIdentityIsIgnored() {
        let finished = expectation(description: "identify completion")

        instance.identify(identity: MixpanelIdentity(userId: "", companyId: "acme", deviceId: nil)) {
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)

        XCTAssertFalse(mockFlushService.flushEventsForAllCalled)
        XCTAssertEqual(
            instance.flushService.getIdentifiers(), ReplayIdentifiers(distinctId: "test-distinct-id", identity: nil))
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

    private func replayURLQueryItems(identity: MixpanelIdentity) -> [URLQueryItem]? {
        let config = MPSessionReplayConfig(wifiOnly: false, autoStartRecording: false, enableLogging: false)
        let testInstance = MPSessionReplayInstance(
            token: "test-token", distinctId: ReplayIdentity.distinctId(identity) ?? "", identity: identity,
            config: config)
        testInstance.startRecording(sessionsPercent: 100)
        defer { testInstance.stopRecording() }
        guard let urlString = testInstance.getSessionReplayURL() else { return nil }
        return URLComponents(string: urlString)?.queryItems
    }

    func testGetSessionReplayUrl_AppendsUserAndCompanyForHierarchicalGroupsIdentity() {
        let identity = MixpanelIdentity(userId: "user+1", companyId: "acme", deviceId: "device-1")

        XCTAssertEqual(
            replayURLQueryItems(identity: identity),
            [
                URLQueryItem(name: "replay_id", value: SessionManager.shared.replayId),
                URLQueryItem(name: "distinct_id", value: "user+1"),
                URLQueryItem(name: "token", value: "test-token"),
                URLQueryItem(name: "$user_id", value: "user+1"),
                URLQueryItem(name: "$company_id", value: "acme"),
            ])
    }

    func testGetSessionReplayUrl_UnchangedWithoutCompany() {
        let identity = MixpanelIdentity(userId: "user_123", companyId: "", deviceId: "device-1")

        XCTAssertEqual(
            replayURLQueryItems(identity: identity),
            [
                URLQueryItem(name: "replay_id", value: SessionManager.shared.replayId),
                URLQueryItem(name: "distinct_id", value: "user_123"),
                URLQueryItem(name: "token", value: "test-token"),
            ])
    }

    func testGetSessionReplayUrl_UnchangedForDistinctId() {
        startRecording()
        let urlString = instance.getSessionReplayURL()

        XCTAssertEqual(
            urlString,
            "https://mixpanel.com/projects/replay-redirect?replay_id=\(SessionManager.shared.replayId)"
                + "&distinct_id=test-distinct-id&token=test-token")
    }
}
