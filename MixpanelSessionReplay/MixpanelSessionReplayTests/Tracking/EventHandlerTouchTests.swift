//
//  EventHandlerTouchTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//
//  Pins the rrweb wire encoding of touch events. The numbers here are rrweb's, not
//  ours, and they are the contract the player and the server-side summarizer both
//  read — a wrong `source` or `type` produces a well-formed event that silently
//  means something else. Values match Android's `Constants.kt` and Flutter's
//  `rrweb_types.dart`.
//

import XCTest

@testable import MixpanelSessionReplay

final class EventHandlerTouchTests: BaseTests {

    private var handler: EventHandler!

    override func setUpWithError() throws {
        try super.setUpWithError()
        handler = EventHandler(eventService: mockEventService)
    }

    override func tearDownWithError() throws {
        handler.shutdown()
        handler = nil
        try super.tearDownWithError()
    }

    /// `EventHandler` enqueues from its own serial queue; wait for the event to land.
    private func encode(_ rawEvent: RawTouchEvent) -> SessionEvent {
        let expectation = expectation(description: "enqueueEvent called")
        mockEventService.enqueueEventExpectation = expectation
        handler.receivedTouchEvent(rawEvent)
        wait(for: [expectation], timeout: 5.0)
        return mockEventService.capturedEvents.last!
    }

    // MARK: - rrweb constants

    func testConstants_matchRRWebTaxonomy() {
        // rrweb's IncrementalSource: 1 is MouseMove (which we never emit) and 6 is
        // TouchMove. Getting these two confused is silent — both encode cleanly.
        XCTAssertEqual(IncrementalSource.mutation, 0)
        XCTAssertEqual(IncrementalSource.mouseInteraction, 2)
        XCTAssertEqual(IncrementalSource.touchMove, 6)

        XCTAssertEqual(MouseInteraction.touchStart, 7)
        XCTAssertEqual(MouseInteraction.touchEnd, 9)
        XCTAssertEqual(MouseInteraction.touchCancel, 10)
    }

    // MARK: - Interactions

    func testInteraction_encodesAsMouseInteractionWithItsOwnType() {
        for type in [
            MouseInteraction.touchStart, MouseInteraction.touchEnd, MouseInteraction.touchCancel,
        ] {
            let event = encode(
                .interaction(type: type, point: CGPoint(x: 12.7, y: 34.2), timestamp: 5_000))

            XCTAssertEqual(event.type, EventType.incrementalSnapshot)
            guard case .detailedData(let detail) = event.data else {
                return XCTFail("expected detailedData for interaction type \(type)")
            }
            XCTAssertEqual(detail.source, IncrementalSource.mouseInteraction)
            XCTAssertEqual(detail.type, type)
            XCTAssertEqual(detail.id, PayloadObjectID.mainSnapshot)
            XCTAssertEqual(detail.x, 12, "coordinates truncate toward zero")
            XCTAssertEqual(detail.y, 34)
            XCTAssertEqual(event.timestamp, 5_000)
        }
    }

    // MARK: - Move batches

    func testMoveBatch_encodesAsTouchMovePositions() {
        let event = encode(
            .move(samples: [
                TouchSample(point: CGPoint(x: 1, y: 2), timestamp: 1_000),
                TouchSample(point: CGPoint(x: 3, y: 4), timestamp: 1_060),
                TouchSample(point: CGPoint(x: 5, y: 6), timestamp: 1_120),
            ]))

        XCTAssertEqual(event.type, EventType.incrementalSnapshot)
        guard case .positionData(let data) = event.data else {
            return XCTFail("expected positionData for a move batch")
        }
        XCTAssertEqual(data.source, IncrementalSource.touchMove)
        XCTAssertEqual(data.positions.map(\.x), [1, 3, 5])
        XCTAssertEqual(data.positions.map(\.y), [2, 4, 6])
        XCTAssertEqual(data.positions.map(\.id), Array(repeating: PayloadObjectID.mainSnapshot, count: 3))

        // The batch is stamped with its final sample, and rrweb replays each position at
        // `event.timestamp + timeOffset`, so every offset is <= 0.
        XCTAssertEqual(event.timestamp, 1_120)
        XCTAssertEqual(data.positions.map(\.timeOffset), [-120, -60, 0])
    }

    func testMoveBatch_singleSampleHasZeroOffset() {
        let event = encode(.move(samples: [TouchSample(point: .zero, timestamp: 777)]))

        guard case .positionData(let data) = event.data else {
            return XCTFail("expected positionData")
        }
        XCTAssertEqual(event.timestamp, 777)
        XCTAssertEqual(data.positions.map(\.timeOffset), [0])
    }

    // MARK: - Serialization

    func testInteraction_serializesTheRRWebKeys() throws {
        let event = encode(
            .interaction(type: MouseInteraction.touchEnd, point: CGPoint(x: 8, y: 9), timestamp: 42))

        let json =
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as! [String: Any]
        let data = json["data"] as! [String: Any]
        XCTAssertEqual(json["type"] as? Int, 3)
        XCTAssertEqual(data["source"] as? Int, 2)
        XCTAssertEqual(data["type"] as? Int, 9)
        XCTAssertEqual(data["x"] as? Int, 8)
        XCTAssertEqual(data["y"] as? Int, 9)
    }

    func testMoveBatch_serializesTheRRWebKeys() throws {
        let event = encode(
            .move(samples: [
                TouchSample(point: CGPoint(x: 1, y: 2), timestamp: 900),
                TouchSample(point: CGPoint(x: 3, y: 4), timestamp: 1_000),
            ]))

        let json =
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as! [String: Any]
        let data = json["data"] as! [String: Any]
        XCTAssertEqual(data["source"] as? Int, 6)
        let positions = data["positions"] as! [[String: Any]]
        XCTAssertEqual(positions.count, 2)
        XCTAssertEqual(positions[0]["timeOffset"] as? Int, -100)
        XCTAssertEqual(positions[1]["timeOffset"] as? Int, 0)
        XCTAssertNil(data["x"], "a move batch carries positions, never a single point")
    }
}
