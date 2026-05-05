//
//  EventServiceTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

class EventServiceTests: XCTestCase {

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

    func testEnqueueScreenshotEvent() {
        let eventService = EventService(queueSizeLimit: 5)
        eventService.enqueueEvent(screenshotEvent)

        // Allow async operation to complete
        let expectation = self.expectation(description: "Event enqueued")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)

        XCTAssertEqual(eventService.eventsCount, 1)
        XCTAssertFalse(eventService.isEventsEmpty)
    }

    func testEnqueueTouchEvent() {
        let eventService = EventService(queueSizeLimit: 5)
        eventService.enqueueEvent(touchEvent)

        // Allow async operation to complete
        let expectation = self.expectation(description: "Event enqueued")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)

        XCTAssertEqual(eventService.eventsCount, 1)
        XCTAssertFalse(eventService.isEventsEmpty)
    }

    func testEnqueueOverTheQueueSizeLimit() {
        let eventService = EventService(queueSizeLimit: 5)
        eventService.enqueueEvent(touchEvent)
        eventService.enqueueEvent(touchEvent)
        eventService.enqueueEvent(touchEvent)
        eventService.enqueueEvent(touchEvent)
        eventService.enqueueEvent(touchEvent)
        eventService.enqueueEvent(touchEvent)

        // Allow async operation to complete
        let expectation = self.expectation(description: "Event enqueued")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2, handler: nil)

        XCTAssertEqual(eventService.eventsCount, 5)
        XCTAssertFalse(eventService.isEventsEmpty)
    }

    func testDequeueOneEvent() {
        let eventService = EventService(queueSizeLimit: 5)
        eventService.enqueueEvent(screenshotEvent)
        eventService.enqueueEvent(touchEvent)
        // Allow async operations to complete
        let expectation = self.expectation(description: "Events enqueued")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)

        let dequeuedEvents = eventService.dequeueEvents(1)
        XCTAssertEqual(dequeuedEvents.count, 1)
        XCTAssertEqual(eventService.eventsCount, 1)
    }

    func testDequeueEvents() {
        let eventService = EventService(queueSizeLimit: 5)
        eventService.enqueueEvent(mainScreenshotEvent)
        eventService.enqueueEvent(screenshotEvent)
        eventService.enqueueEvent(touchEvent)

        // Allow async operations to complete
        let expectation = self.expectation(description: "Events enqueued")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2, handler: nil)

        let dequeuedEvents = eventService.dequeueEvents(2)
        let expectation1 = self.expectation(description: "Events enqueued")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation1.fulfill()
        }
        waitForExpectations(timeout: 2, handler: nil)
        XCTAssertEqual(dequeuedEvents.count, 2)
        XCTAssertEqual(eventService.eventsCount, 1)
    }

    func testDequeueEventsLargerThanQueueSize() {
        let eventService = EventService(queueSizeLimit: 5)
        eventService.enqueueEvent(mainScreenshotEvent)
        eventService.enqueueEvent(screenshotEvent)
        eventService.enqueueEvent(touchEvent)

        // Allow async operations to complete
        let expectation = self.expectation(description: "Events enqueued")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2, handler: nil)

        let dequeuedEvents = eventService.dequeueEvents(5)
        XCTAssertEqual(dequeuedEvents.count, 3)
        XCTAssertEqual(eventService.eventsCount, 0)
    }

    func testPrependEvents() {
        let eventService = EventService(queueSizeLimit: 5)
        eventService.enqueueEvent(mainScreenshotEvent)
        eventService.enqueueEvent(screenshotEvent)
        eventService.enqueueEvent(touchEvent)
        // Allow async operations to complete
        let expectation = self.expectation(description: "Events enqueued")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2, handler: nil)

        let dequeuedEvents = eventService.dequeueEvents(3)
        XCTAssertEqual(dequeuedEvents.count, 3)
        XCTAssertEqual(eventService.eventsCount, 0)
        eventService.prependEvents(dequeuedEvents)
        XCTAssertEqual(eventService.eventsCount, 3)
    }

    func testClearEvents() {
        let eventService = EventService(queueSizeLimit: 5)
        eventService.enqueueEvent(mainScreenshotEvent)
        eventService.enqueueEvent(screenshotEvent)
        eventService.enqueueEvent(touchEvent)

        // Allow async operation to complete
        let expectation = self.expectation(description: "Event enqueued")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2, handler: nil)

        eventService.clearEvents()
        XCTAssertEqual(eventService.eventsCount, 0)
        XCTAssertTrue(eventService.isEventsEmpty)
    }

    func testEvictionWithoutFullSnapshot() {
        let eventService = EventService(queueSizeLimit: 5)
        // Enqueue 5 events
        for _ in 1...5 {
            eventService.enqueueEvent(screenshotEvent)
        }
        let expectation = self.expectation(description: "Events enqueued")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2, handler: nil)

        XCTAssertEqual(eventService.eventsCount, 5)

        // Enqueue 1 more event to trigger eviction
        eventService.enqueueEvent(screenshotEvent)

        let expectation2 = self.expectation(description: "Events enqueued")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation2.fulfill()
        }
        waitForExpectations(timeout: 2, handler: nil)

        // Verify eviction rule: the oldest event should be evicted
        XCTAssertEqual(eventService.eventsCount, 5)
    }

    func testEvictionWithFullSnapshotWithEnqueue() {
        let eventService = EventService(queueSizeLimit: 5)
        eventService.enqueueEvent(mainScreenshotEvent)
        eventService.enqueueEvent(screenshotEvent)
        eventService.enqueueEvent(screenshotEvent)
        eventService.enqueueEvent(screenshotEvent)

        // Enqueue a full snapshot event
        eventService.enqueueEvent(mainScreenshotEvent)

        let expectation1 = self.expectation(description: "Events enqueued")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation1.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
        XCTAssertEqual(eventService.eventsCount, 5)

        // Enqueue 1 more event to trigger eviction
        eventService.enqueueEvent(screenshotEvent)

        let expectation2 = self.expectation(description: "Events enqueued")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation2.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)

        // Verify eviction rule: all events before the full snapshot should be evicted
        XCTAssertEqual(eventService.eventsCount, 2)
    }

    func testEvictionWithFullSnapshotWithPrepend() {
        let eventService = EventService(queueSizeLimit: 5)
        eventService.enqueueEvent(mainScreenshotEvent)
        eventService.enqueueEvent(screenshotEvent)
        eventService.enqueueEvent(screenshotEvent)

        let expectation0 = self.expectation(description: "Events enqueued")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation0.fulfill()
        }
        waitForExpectations(timeout: 2, handler: nil)
        XCTAssertEqual(eventService.eventsCount, 3)

        let eventsToFlush = eventService.dequeueEvents(3)

        let expectation3 = self.expectation(description: "Events enqueued")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation3.fulfill()
        }
        waitForExpectations(timeout: 2, handler: nil)
        XCTAssertEqual(eventService.eventsCount, 0)

        // more events are coming in
        eventService.enqueueEvent(mainScreenshotEvent)
        eventService.enqueueEvent(screenshotEvent)
        eventService.enqueueEvent(screenshotEvent)
        eventService.enqueueEvent(screenshotEvent)
        eventService.enqueueEvent(mainScreenshotEvent)

        let expectation1 = self.expectation(description: "Events enqueued")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation1.fulfill()
        }
        waitForExpectations(timeout: 2, handler: nil)
        XCTAssertEqual(eventService.eventsCount, 5)

        // prepend the previous dequeued events(flush failed) to trigger eviction
        eventService.prependEvents(eventsToFlush)

        let expectation2 = self.expectation(description: "Events enqueued")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation2.fulfill()
        }
        waitForExpectations(timeout: 2, handler: nil)

        // Verify eviction rule: all events before the full snapshot should be evicted
        // no.1 + no.2 + no.3 + no.8 (4,5,6 evicted and 7 should also be evicted
        // because 7 is losing its head)
        XCTAssertEqual(eventService.eventsCount, 4)
    }
}
