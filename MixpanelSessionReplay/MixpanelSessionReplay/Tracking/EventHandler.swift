//
//  EventListener.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation

protocol EventListener: AnyObject {
    func receivedTouchEvent(_ rawEvent: RawTouchEvent)
    func receivedScreenshotEvent(_ rawEvent: RawScreenshotEvent)
    func receivedCustomEvent(_ event: SessionEvent)
}

extension EventListener {
    func receivedCustomEvent(_ event: SessionEvent) {}
}

class EventHandler: EventListener {
    private weak var eventService: EventService?
    private var eventSerialQueue: DispatchQueue

    init(eventService: EventService) {
        self.eventService = eventService
        eventSerialQueue = DispatchQueue(
            label: "com.mixpanel.session.replay", qos: .utility, autoreleaseFrequency: .workItem)
        EventPublisher.shared.subscribe(self)
    }

    func shutdown() {
        EventPublisher.shared.unsubscribe(self)
    }

    func receivedTouchEvent(_ rawEvent: RawTouchEvent) {
        eventSerialQueue.async {
            let touchEvent: SessionEvent
            switch rawEvent {
                case .interaction(let type, let point, let timestamp):
                    touchEvent = SessionEvent(
                        type: EventType.incrementalSnapshot,
                        data: .detailedData(
                            EventDataDetail(
                                source: IncrementalSource.mouseInteraction,
                                type: type,
                                id: PayloadObjectID.mainSnapshot,
                                x: Int(point.x),
                                y: Int(point.y)
                            )
                        ),
                        timestamp: timestamp
                    )
                case .move(let samples):
                    let batchTimestamp = rawEvent.timestamp
                    touchEvent = SessionEvent(
                        type: EventType.incrementalSnapshot,
                        data: .positionData(
                            SessionPositionData(
                                source: IncrementalSource.touchMove,
                                positions: samples.map { sample in
                                    SessionPosition(
                                        x: Double(sample.point.x),
                                        y: Double(sample.point.y),
                                        id: PayloadObjectID.mainSnapshot,
                                        // rrweb replays a sample at `event.timestamp + timeOffset`,
                                        // so offsets are <= 0 against the batch's final sample.
                                        timeOffset: Int(sample.timestamp - batchTimestamp)
                                    )
                                }
                            )
                        ),
                        timestamp: batchTimestamp
                    )
            }
            self.eventService?.enqueueEvent(touchEvent)
        }
    }

    func receivedScreenshotEvent(_ rawEvent: RawScreenshotEvent) {
        eventSerialQueue.async {
            if let event = rawEvent.isInitial
                ? MPSessionReplayEncoder.mainSessionEvent(
                    image: rawEvent.data, timestamp: rawEvent.timestamp)
                : MPSessionReplayEncoder.incrementalSessionEvent(
                    image: rawEvent.data, timestamp: rawEvent.timestamp)
            {
                self.eventService?.enqueueEvent(event)
            }
        }
    }

    func receivedCustomEvent(_ event: SessionEvent) {
        eventSerialQueue.async {
            self.eventService?.enqueueEvent(event)
        }
    }
}
