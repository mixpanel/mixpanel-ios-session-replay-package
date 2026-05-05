//
//  FlushServiceTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

class FlushServiceTests: XCTestCase {

    var touchEvent: SessionEvent {
        let currentTimestamp = TimestampUtils.timestamp()
        let rawEvent = RawTouchEvent(
            start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1.0, y: 1.0), isSwipe: false,
            timestamp: currentTimestamp)
        return SessionEvent(
            type: EventType.incrementalSnapshot,
            data: .detailedData(
                EventDataDetail(
                    source: IncrementalSource.touchInteraction,
                    type: TouchInteraction.start,
                    id: PayloadObjectID.mainSnapshot,
                    x: Int(rawEvent.start.x),
                    y: Int(rawEvent.start.y)
                )
            ),
            timestamp: currentTimestamp
        )
    }

    var mainScreenshotEvent: SessionEvent {
        let timestamp = TimestampUtils.timestamp()
        let rawEvent = RawScreenshotEvent(data: Data(), isInitial: true, timestamp: timestamp)
        return rawEvent.isInitial
            ? MPSessionReplayEncoder.mainSessionEvent(image: rawEvent.data, timestamp: timestamp)!
            : MPSessionReplayEncoder.incrementalSessionEvent(image: rawEvent.data, timestamp: timestamp)!
    }

    var screenshotEvent: SessionEvent {
        sleep(1)
        let timestamp = TimestampUtils.timestamp()
        let rawEvent = RawScreenshotEvent(data: Data(), isInitial: false, timestamp: timestamp)
        return rawEvent.isInitial
            ? MPSessionReplayEncoder.mainSessionEvent(image: rawEvent.data, timestamp: timestamp)!
            : MPSessionReplayEncoder.incrementalSessionEvent(image: rawEvent.data, timestamp: timestamp)!
    }

    override func setUp() {
        super.setUp()

    }

    override func tearDown() {
        super.tearDown()
    }

    func testStartFlushService() {
        let eventService = EventService(queueSizeLimit: 10)
        let mockFlushRequest = MockFlushRequest(token: "testToken", distinctId: "testDistinctId")
        mockFlushRequest.sendRequestSuccess = true
        let flushService = FlushService(
            token: "testToken", distinctId: "testDistinctId", eventService: eventService, wifiOnly: false,
            flushRequest: mockFlushRequest, flushInterval: ReplaySettings.flushInterval)

        flushService.start()

        let expectation = XCTestExpectation(description: "FlushService started")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            XCTAssertNotNil(flushService.flushTimer)  // UUID length
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testWifiOnlyFlushService() {
        let eventService = EventService(queueSizeLimit: 10)
        let mockFlushRequest = MockFlushRequest(token: "testToken", distinctId: "testDistinctId")
        mockFlushRequest.sendRequestSuccess = true

        // Test wifiOnly = true, isUsingWiFi = True
        let isUsingWifi = MockNetworkMonitor()
        let wifiOnlyTrueUsingWifiTrue = FlushService(
            token: "testToken", distinctId: "testDistinctId", eventService: eventService, wifiOnly: true,
            flushRequest: mockFlushRequest, networkMonitor: isUsingWifi, flushInterval: ReplaySettings.flushInterval)
        eventService.enqueueEvent(mainScreenshotEvent)
        wifiOnlyTrueUsingWifiTrue.flushEvents(forAll: false)
        wifiOnlyTrueUsingWifiTrue.flushSerialQueue.sync {
            return
        }
        XCTAssertTrue(mockFlushRequest.sendRequestCalled)

        // Test wifiOnly = true, isUsingWiFi = False
        mockFlushRequest.sendRequestCalled = false
        let isNotUsingWifi = MockNetworkMonitor()
        isNotUsingWifi.isUsingWiFiOverride = false
        let wifiOnlyTrueUsingWifiFalse = FlushService(
            token: "testToken", distinctId: "testDistinctId", eventService: eventService, wifiOnly: true,
            flushRequest: mockFlushRequest, networkMonitor: isNotUsingWifi, flushInterval: ReplaySettings.flushInterval)
        eventService.enqueueEvent(mainScreenshotEvent)
        wifiOnlyTrueUsingWifiFalse.flushEvents(forAll: false)
        wifiOnlyTrueUsingWifiFalse.flushSerialQueue.sync {
            return
        }
        XCTAssertFalse(mockFlushRequest.sendRequestCalled)

        // Test wifiOnly = false, isUsingWiFi = True
        let wifiOnlyFalseUsingWifiTrue = FlushService(
            token: "testToken", distinctId: "testDistinctId", eventService: eventService, wifiOnly: false,
            flushRequest: mockFlushRequest, networkMonitor: isUsingWifi, flushInterval: ReplaySettings.flushInterval)
        wifiOnlyFalseUsingWifiTrue.flushEvents(forAll: false)
        wifiOnlyFalseUsingWifiTrue.flushSerialQueue.sync {
            return
        }
        XCTAssertTrue(mockFlushRequest.sendRequestCalled)

        // Test wifiOnly = false, isUsingWifi = False
        mockFlushRequest.sendRequestCalled = false
        let wifiOnlyFalseUsingWifiFalse = FlushService(
            token: "testToken", distinctId: "testDistinctId", eventService: eventService, wifiOnly: false,
            flushRequest: mockFlushRequest, networkMonitor: isNotUsingWifi, flushInterval: ReplaySettings.flushInterval)
        eventService.enqueueEvent(mainScreenshotEvent)
        wifiOnlyFalseUsingWifiFalse.flushEvents(forAll: false)
        wifiOnlyFalseUsingWifiFalse.flushSerialQueue.sync {
            return
        }
        XCTAssertTrue(mockFlushRequest.sendRequestCalled)
    }

    func testStopFlushService() {
        let eventService = EventService(queueSizeLimit: 10)
        let mockFlushRequest = MockFlushRequest(token: "testToken", distinctId: "testDistinctId")
        mockFlushRequest.sendRequestSuccess = true
        let flushService = FlushService(
            token: "testToken", distinctId: "testDistinctId", eventService: eventService, wifiOnly: false,
            flushRequest: mockFlushRequest, flushInterval: ReplaySettings.flushInterval)

        flushService.start()
        flushService.stop()
        XCTAssertNil(flushService.flushTimer)
    }

    func testFlushEventsWithoutForcingAll() {
        let eventService = EventService(queueSizeLimit: 10)
        let mockFlushRequest = MockFlushRequest(token: "testToken", distinctId: "testDistinctId")
        mockFlushRequest.sendRequestSuccess = true
        let flushService = FlushService(
            token: "testToken", distinctId: "testDistinctId", eventService: eventService, wifiOnly: false,
            flushRequest: mockFlushRequest, flushInterval: ReplaySettings.flushInterval)

        eventService.enqueueEvent(mainScreenshotEvent)
        flushService.flushEvents(forAll: false)

        // Allow async operation to complete
        flushService.flushSerialQueue.sync {
            return
        }

        XCTAssertTrue(mockFlushRequest.sendRequestCalled)
        XCTAssertTrue(eventService.events.isEmpty)
    }

    func testFlushEventsForcingAll() {
        SessionManager.shared.generateNewSession()
        let eventService = EventService(queueSizeLimit: 10)
        let mockFlushRequest = MockFlushRequest(token: "testToken", distinctId: "testDistinctId")
        mockFlushRequest.sendRequestSuccess = true

        let flushService = FlushService(
            token: "testToken", distinctId: "testDistinctId", eventService: eventService, wifiOnly: false,
            flushRequest: mockFlushRequest, flushInterval: ReplaySettings.flushInterval)

        eventService.enqueueEvent(screenshotEvent)
        eventService.enqueueEvent(screenshotEvent)
        eventService.enqueueEvent(screenshotEvent)

        flushService.flushEvents(forAll: true)

        // Allow async operation to complete
        flushService.flushSerialQueue.sync {
            return
        }

        XCTAssertTrue(mockFlushRequest.sendRequestCalled)
        XCTAssertTrue(eventService.events.isEmpty)
    }

    func testFlushEventsFailure() {
        SessionManager.shared.generateNewSession()
        let eventService = EventService(queueSizeLimit: 10)
        let mockFlushRequest = MockFlushRequest(token: "testToken", distinctId: "testDistinctId")

        eventService.enqueueEvent(screenshotEvent)
        eventService.enqueueEvent(screenshotEvent)
        mockFlushRequest.sendRequestSuccess = false

        let flushService = FlushService(
            token: "testToken", distinctId: "testDistinctId", eventService: eventService, wifiOnly: false,
            flushRequest: mockFlushRequest, flushInterval: ReplaySettings.flushInterval)

        flushService.flushEvents(forAll: false)

        // Allow async operation to complete
        flushService.flushSerialQueue.sync {
            return
        }

        XCTAssertTrue(mockFlushRequest.sendRequestCalled)
        XCTAssertEqual(eventService.eventsCount, 2)  // Events should be prepended back
    }
}
