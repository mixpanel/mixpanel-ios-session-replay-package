//
//  TouchEventTrackerTests.swift
//  MixpanelSessionReplayTests
//
//  Created by Ketan on 03/03/25.
//  Copyright © 2025 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

final class TouchEventTrackerTests: BaseTests {

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    func testSwipe() throws {
        var direction = TouchEventTracker.detectSwipeDirection(
            from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 10))
        XCTAssertEqual(direction, "right")

        direction = TouchEventTracker.detectSwipeDirection(
            from: CGPoint(x: 0, y: 0), to: CGPoint(x: -100, y: 10))
        XCTAssertEqual(direction, "left")

        direction = TouchEventTracker.detectSwipeDirection(
            from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 100))
        XCTAssertEqual(direction, "down")

        direction = TouchEventTracker.detectSwipeDirection(
            from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: -100))
        XCTAssertEqual(direction, "up")
    }

    func testPublishTouchEvent() throws {
        // Create expectation before triggering async operation
        let expectation = expectation(description: "EventService.enqueueEvent called")
        mockEventService.enqueueEventExpectation = expectation

        let rawEvent = RawTouchEvent(
            start: CGPoint(x: 100, y: 100),
            end: CGPoint(x: 100, y: 150),
            isSwipe: false,
            direction: "left",
            timestamp: TimestampUtils.timestamp()
        )
        EventPublisher.shared.publishTouchEvent(rawEvent)

        // Wait for async chain to complete
        wait(for: [expectation], timeout: 10.0)

        XCTAssertTrue(mockEventService.enqueueEventCalled)
    }

    func testDistanceTo_SamePoint() {
        let pointA = CGPoint(x: 10, y: 20)
        let distance = pointA.distance(to: pointA)
        XCTAssertEqual(distance, 0)
    }

    func testDistanceTo_Horizontal() {
        let pointA = CGPoint(x: 10, y: 20)
        let pointB = CGPoint(x: 20, y: 20)
        let expectedDistance = CGFloat(10)  // 20 - 10
        let distance = pointA.distance(to: pointB)
        XCTAssertEqual(distance, expectedDistance)
    }

    func testDistanceTo_Vertical() {
        let pointA = CGPoint(x: 15, y: 30)
        let pointB = CGPoint(x: 15, y: 50)
        let expectedDistance = CGFloat(20)  // 50 - 30
        let distance = pointA.distance(to: pointB)
        XCTAssertEqual(distance, expectedDistance)
    }

    func testDistanceTo_Diagonal() {
        let pointA = CGPoint(x: 0, y: 0)
        let pointB = CGPoint(x: 3, y: 4)
        let expectedDistance = CGFloat(5)  // √(3² + 4²) = 5
        let distance = pointA.distance(to: pointB)
        XCTAssertEqual(distance, expectedDistance, accuracy: 0.0001)
    }
}
