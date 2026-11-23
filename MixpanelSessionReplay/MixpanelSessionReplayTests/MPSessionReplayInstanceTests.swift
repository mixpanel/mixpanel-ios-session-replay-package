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
            identifiers: ReplayIdentifiers(distinctId: "test-distinct-id"),
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
        let instance = MPSessionReplayInstance(
            token: "test-token", identifiers: ReplayIdentifiers(distinctId: "test-distinct-id"), config: config)

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
            token: "test-token", identifiers: ReplayIdentifiers(distinctId: "test-distinct-id"), config: config)

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

    func testIdentifyWithIdentitySetsIdentityWithoutFlushing() {
        let identity = MixpanelIdentity(userId: "user_123", companyId: "acme", deviceId: "device-1")
        let finished = expectation(description: "identify completion")

        instance.identify(identity: identity) {
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)

        // Queued events keep the stamp they were captured with, so nothing has to upload first
        XCTAssertFalse(mockFlushService.flushEventsForAllCalled)
        XCTAssertEqual(instance.currentIdentifiers, ReplayIdentifiers(identity: identity)!)
        XCTAssertEqual(instance.flushService.getDistinctId(), "test-distinct-id")
    }

    func testIdentifyWithDeviceOnlyIdentityUsesDeviceDistinctId() {
        let identity = MixpanelIdentity(userId: nil, companyId: nil, deviceId: "device-1")
        let finished = expectation(description: "identify completion")

        instance.identify(identity: identity) {
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)

        XCTAssertEqual(instance.currentIdentifiers.distinctId, "$device:device-1")
        XCTAssertEqual(instance.currentIdentifiers.identity, identity)
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
            instance.currentIdentifiers, ReplayIdentifiers(distinctId: "plain-distinct-id"))
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
            instance.currentIdentifiers, ReplayIdentifiers(distinctId: "user_123"))
        startRecording()
        XCTAssertEqual(
            instance.getSessionReplayURL(),
            "https://mixpanel.com/projects/replay-redirect?replay_id=\(SessionManager.shared.replayId)"
                + "&distinct_id=user_123&token=test-token")
    }

    func testIdentityChangeDoesNotWaitForRunningFlush() {
        let identity = MixpanelIdentity(userId: "user_123", companyId: "acme", deviceId: "device-1")
        let otherIdentity = MixpanelIdentity(userId: "user_456", companyId: "acme", deviceId: "device-1")
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
        defer { releaseFlush.signal() }

        let reidentified = expectation(description: "identify other identity completion")
        instance.identify(identity: otherIdentity) {
            reidentified.fulfill()
        }
        wait(for: [reidentified], timeout: 2)
        XCTAssertEqual(instance.currentIdentifiers, ReplayIdentifiers(identity: otherIdentity)!)
    }

    func testLastIdentifyWinsWhileFlushQueueIsBusy() {
        let identityA = MixpanelIdentity(userId: "user_a", companyId: "acme", deviceId: "device-1")
        let identityB = MixpanelIdentity(userId: "user_b", companyId: "acme", deviceId: "device-1")

        // Hold the flush queue as a running flush would
        let flushStarted = DispatchSemaphore(value: 0)
        let releaseFlush = DispatchSemaphore(value: 0)
        instance.flushService.flushSerialQueue.async {
            flushStarted.signal()
            releaseFlush.wait()
        }
        flushStarted.wait()
        defer { releaseFlush.signal() }

        let identifiedB = expectation(description: "identify B completion")
        instance.identify(identity: identityB) { identifiedB.fulfill() }
        let identifiedA = expectation(description: "identify A completion")
        instance.identify(identity: identityA) { identifiedA.fulfill() }
        wait(for: [identifiedB, identifiedA], timeout: 2, enforceOrder: true)
        XCTAssertEqual(instance.currentIdentifiers, ReplayIdentifiers(identity: identityA)!)

        // An unchanged identity is a no-op that still completes
        let unchanged = expectation(description: "identify unchanged completion")
        instance.identify(identity: identityA) { unchanged.fulfill() }
        wait(for: [unchanged], timeout: 2)
        XCTAssertEqual(instance.currentIdentifiers, ReplayIdentifiers(identity: identityA)!)
    }

    func testConcurrentIdentifyDuringFlushesKeepsIdentifiersConsistent() {
        // Identities that share no value, so a request mixing two of them matches neither
        let identityA = MixpanelIdentity(userId: "user_a", companyId: "company-a", deviceId: "device-a")
        let identityB = MixpanelIdentity(userId: "user_b", companyId: "company-b", deviceId: "device-b")
        let anonymous = MixpanelIdentity(userId: nil, companyId: nil, deviceId: "device-c")
        let plainDistinctId = "plain_user"
        // The identity keys each of them sends, and nothing else
        let expectedIdentityParams: [[String: String]] = [
            ["$user_id": "user_a", "$company_id": "company-a", "$device_id": "device-a"],
            ["$user_id": "user_b", "$company_id": "company-b", "$device_id": "device-b"],
            ["distinct_id": "$device:device-c", "$device_id": "device-c"],
            ["distinct_id": plainDistinctId],
        ]
        let identityKeys: Set<String> = ["distinct_id", "$user_id", "$company_id", "$device_id"]

        // Wi-Fi drops on every other check, so some identity changes skip their upload and leave
        // events captured under an earlier identity queued behind a later one.
        let networkMonitor = AlternatingNetworkMonitor()
        let eventService = EventService()
        eventService.eventHandler?.shutdown()
        eventService.identifiers = ReplayIdentifiers(identity: identityA)!
        let flushService = FlushService(
            token: "test-token", distinctId: "user_a", eventService: eventService,
            wifiOnly: true, flushRequest: nil, networkMonitor: networkMonitor,
            flushInterval: ReplaySettings.flushInterval)
        instance.eventService = eventService
        instance.flushService = flushService

        let sentLock = NSLock()
        var sent: [[URLQueryItem]] = []
        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.requestHandler = { request in
            let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
            sentLock.lock()
            sent.append(items ?? [])
            sentLock.unlock()
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil), Data(), nil
            )
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

        let instance = self.instance!

        // Seed one completed upload per identity, in order and with Wi-Fi on, so every identity is
        // covered whatever the concurrent phase below happens to upload.
        networkMonitor.alwaysOnWiFi = true
        let seedSteps: [(String, (@escaping () -> Void) -> Void)] = [
            ("identity A", { instance.identify(identity: identityA, completion: $0) }),
            ("identity B", { instance.identify(identity: identityB, completion: $0) }),
            ("anonymous identity", { instance.identify(identity: anonymous, completion: $0) }),
            ("plain distinct id", { instance.identify(distinctId: plainDistinctId, completion: $0) }),
        ]
        for (name, identify) in seedSteps {
            let identified = expectation(description: "seed identify \(name)")
            identify { identified.fulfill() }
            wait(for: [identified], timeout: 10)
            eventService.enqueueEvent(event())
            let flushed = expectation(description: "seed flush \(name)")
            flushService.flushEvents(forAll: true) { flushed.fulfill() }
            wait(for: [flushed], timeout: 10)
            XCTAssertTrue(eventService.isEventsEmpty, "the seed event for \(name) must upload")
        }
        networkMonitor.alwaysOnWiFi = false

        // Flushes and identity changes race; every call must complete (no crash or deadlock). Rounds
        // of concurrent calls, with events captured before each call and from its completion, so
        // events are captured under every identity, not only the first.
        let rounds = 30
        let callsPerRound = 8
        for round in 0..<rounds {
            let group = DispatchGroup()
            DispatchQueue.concurrentPerform(iterations: callsPerRound) { index in
                group.enter()
                eventService.enqueueEvent(event())
                let done = {
                    eventService.enqueueEvent(event())
                    group.leave()
                }
                switch (round + index) % 6 {
                    case 0, 3:
                        flushService.flushEvents(forAll: true, completionHandler: done)
                    case 1:
                        instance.identify(identity: identityA, completion: done)
                    case 2:
                        instance.identify(identity: identityB, completion: done)
                    case 4:
                        instance.identify(identity: anonymous, completion: done)
                    default:
                        instance.identify(distinctId: plainDistinctId, completion: done)
                }
            }
            let finished = expectation(description: "round \(round) calls complete")
            group.notify(queue: .main) { finished.fulfill() }
            wait(for: [finished], timeout: 10)
        }

        // Upload whatever is still queued, whichever identity it was captured under
        networkMonitor.alwaysOnWiFi = true
        let drained = expectation(description: "final flush completion")
        flushService.flushEvents(forAll: true) { drained.fulfill() }
        wait(for: [drained], timeout: 10)
        XCTAssertTrue(eventService.isEventsEmpty, "every queued event must upload")

        sentLock.lock()
        let requests = sent
        sentLock.unlock()
        XCTAssertFalse(requests.isEmpty, "the flushes must upload")

        var identitiesSeen = Set<Int>()
        for (index, items) in requests.enumerated() {
            let names = items.map(\.name)
            XCTAssertEqual(names.count, Set(names).count, "request \(index) repeats a key: \(items)")
            var identityParams: [String: String] = [:]
            for item in items where identityKeys.contains(item.name) {
                identityParams[item.name] = item.value
            }
            if let match = expectedIdentityParams.firstIndex(of: identityParams) {
                identitiesSeen.insert(match)
            } else {
                XCTFail("request \(index) mixes identities or sends partial identifiers: \(identityParams)")
            }
        }
        XCTAssertEqual(
            identitiesSeen, Set(expectedIdentityParams.indices), "the seeded uploads cover every identity")
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
        eventService.identifiers = ReplayIdentifiers(identity: companyA)!
        instance.flushService = FlushService(
            token: "test-token", distinctId: "user_123", eventService: eventService,
            wifiOnly: true, networkMonitor: networkMonitor, flushInterval: ReplaySettings.flushInterval)

        let sentLock = NSLock()
        var sent: [[URLQueryItem]] = []
        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.requestHandler = { request in
            let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
            sentLock.lock()
            sent.append(items ?? [])
            sentLock.unlock()
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil), Data(), nil
            )
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
        XCTAssertEqual(eventService.eventsCount, 2, "company A's events are still queued")

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
                    URLQueryItem(name: "$user_id", value: "user_123"),
                    URLQueryItem(name: "$company_id", value: "company-a"),
                    URLQueryItem(name: "$device_id", value: "device-1"),
                ],
                [
                    URLQueryItem(name: "$user_id", value: "user_123"),
                    URLQueryItem(name: "$company_id", value: "company-b"),
                    URLQueryItem(name: "$device_id", value: "device-1"),
                ],
            ])
        XCTAssertTrue(eventService.isEventsEmpty)
    }

    func testEventsQueuedBeforeIdentifyUploadUnderTheDistinctId() {
        let identity = MixpanelIdentity(userId: "user_123", companyId: "acme", deviceId: "device-1")

        // Real services, started from a plain distinct id, with uploads deferred until Wi-Fi is back
        let eventService = EventService()
        eventService.eventHandler?.shutdown()
        let networkMonitor = MockNetworkMonitor()
        networkMonitor.isUsingWiFiOverride = false
        instance.eventService = eventService
        instance.flushService = FlushService(
            token: "test-token", distinctId: "$device:device-1", eventService: eventService,
            wifiOnly: true, networkMonitor: networkMonitor, flushInterval: ReplaySettings.flushInterval)

        let sentLock = NSLock()
        var sent: [[URLQueryItem]] = []
        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.requestHandler = { request in
            let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
            sentLock.lock()
            sent.append(items ?? [])
            sentLock.unlock()
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil), Data(), nil
            )
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
        let identified = expectation(description: "identify completion")
        instance.identify(identity: identity) {
            identified.fulfill()
        }
        wait(for: [identified], timeout: 2)
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
                [URLQueryItem(name: "distinct_id", value: "$device:device-1")],
                [
                    URLQueryItem(name: "$user_id", value: "user_123"),
                    URLQueryItem(name: "$company_id", value: "acme"),
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
            instance.currentIdentifiers, ReplayIdentifiers(distinctId: "test-distinct-id"))
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
            identifiers: ReplayIdentifiers(distinctId: specialDistinctId),
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
            token: "test-token", identifiers: ReplayIdentifiers(identity: identity)!,
            config: config)
        testInstance.startRecording(sessionsPercent: 100)
        defer { testInstance.stopRecording() }
        guard let urlString = testInstance.getSessionReplayURL() else { return nil }
        return URLComponents(string: urlString)?.queryItems
    }

    func testGetSessionReplayUrl_SendsUserAndCompanyInsteadOfDistinctIdForHierarchicalGroupsIdentity() {
        let identity = MixpanelIdentity(userId: "user+1", companyId: "acme", deviceId: "device-1")

        XCTAssertEqual(
            replayURLQueryItems(identity: identity),
            [
                URLQueryItem(name: "replay_id", value: SessionManager.shared.replayId),
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

/// Reports Wi-Fi on every other check, unless `alwaysOnWiFi` is set. Safe to read from any thread.
private final class AlternatingNetworkMonitor: NetworkMonitoring {
    private let lock = NSLock()
    private var checks = 0
    private var storedAlwaysOnWiFi = false

    var alwaysOnWiFi: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedAlwaysOnWiFi
        }
        set {
            lock.lock()
            storedAlwaysOnWiFi = newValue
            lock.unlock()
        }
    }

    var isUsingWiFi: Bool {
        lock.lock()
        defer { lock.unlock() }
        checks += 1
        return storedAlwaysOnWiFi || checks % 2 == 0
    }
}
