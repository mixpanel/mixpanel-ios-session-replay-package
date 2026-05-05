//
//  EventPubSub.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation

class EventPublisher {
    static let shared = EventPublisher()
    let queue = DispatchQueue(label: "com.mixpanel.eventpublisher.queue")

    private init() {}

    private var subscribers = [EventListener]()

    func resetSubscribers() {
        queue.async { [weak self] in
            self?.subscribers.removeAll()
        }
    }

    func subscribe(_ subscriber: EventListener) {
        queue.async { [weak self] in
            self?.subscribers.append(subscriber)
        }
    }

    func unsubscribe(_ subscriber: EventListener) {
        queue.async { [weak self] in
            guard let self else { return }
            self.subscribers = self.subscribers.filter { $0 !== subscriber }
        }
    }

    func publishTouchEvent(_ event: RawTouchEvent) {
        queue.async { [weak self] in
            self?.subscribers.forEach { $0.receivedTouchEvent(event) }
        }
    }

    func publishSessionEvent(_ event: RawScreenshotEvent) {
        queue.async { [weak self] in
            self?.subscribers.forEach { $0.receivedScreenshotEvent(event) }
        }
    }
}
