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
            let touchEvent = SessionEvent(
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
                timestamp: rawEvent.timestamp
            )
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
}
