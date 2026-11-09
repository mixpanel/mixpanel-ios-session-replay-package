//
//  EventService.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation

class EventService {
    private(set) var events: [SessionEvent] = []
    private let readWriteLock: ReadWriteLock
    private var queueSizeLimit: Int
    /// Stamped on each queued event; nil unless Session Replay is identified with a `MixpanelIdentity`.
    private var identifiersForNewEvents: ReplayIdentifiers?
    var eventHandler: EventHandler?

    init(queueSizeLimit: Int = ReplaySettings.queueSizeLimit) {
        readWriteLock = ReadWriteLock(label: "com.mixpanel.sessionrelay.events.lock")
        self.queueSizeLimit = queueSizeLimit
        self.eventHandler = EventHandler(eventService: self)
    }

    private func firstFullSnapshotIndex(_ events: [SessionEvent]) -> Int {
        for (index, event) in events.enumerated() {
            if event.type == EventType.fullSnapshot {
                return index
            }
        }
        return -1
    }

    private func containsFullSnapshot(_ events: [SessionEvent]) -> Bool {
        return firstFullSnapshotIndex(events) >= 0
    }

    // Evict the oldest events. If a full snapshot is evicted,
    // all other normal events must also be removed, as remaining
    // events without a full snapshot are not playable.
    private func evictEvents(_ numsOfEvents: Int = 1) {
        var currentEvents: [SessionEvent] = []
        readWriteLock.read {
            currentEvents = events
        }
        var numsOfEventsToEvict = min(numsOfEvents, currentEvents.count)
        let candidateEventsToEvict = Array(currentEvents[0...numsOfEventsToEvict - 1])
        let candidateEventsRemain = Array(currentEvents[numsOfEventsToEvict...currentEvents.count - 1])

        let numsOfEventsBeforeNextFullSnapshot = firstFullSnapshotIndex(candidateEventsRemain)

        if containsFullSnapshot(candidateEventsToEvict) && numsOfEventsBeforeNextFullSnapshot >= 0 {
            numsOfEventsToEvict += numsOfEventsBeforeNextFullSnapshot
        }
        readWriteLock.write {
            events.removeFirst(numsOfEventsToEvict)
        }
    }

    /// Sets the identifiers stamped on events queued from now on.
    func setIdentifiersForNewEvents(_ identifiers: ReplayIdentifiers?) {
        readWriteLock.write {
            identifiersForNewEvents = identifiers
        }
    }

    func enqueueEvent(_ event: SessionEvent) {
        var event = event
        var currentEvents: [SessionEvent] = []
        readWriteLock.read {
            currentEvents = events
            event.identifiers = identifiersForNewEvents
        }
        if currentEvents.count >= queueSizeLimit {
            evictEvents()
        }
        readWriteLock.write {
            events.append(event)
        }
    }

    var eventsCount: Int {
        var currentEvents: [SessionEvent] = []
        readWriteLock.read {
            currentEvents = events
        }
        return currentEvents.count
    }

    var isEventsEmpty: Bool {
        var currentEvents: [SessionEvent] = []
        readWriteLock.read {
            currentEvents = events
        }
        return currentEvents.isEmpty
    }

    func dequeueEvents(_ numsOfEvents: Int) -> [SessionEvent] {
        var currentEvents: [SessionEvent] = []
        readWriteLock.read {
            currentEvents = events
        }
        var dequeuedEvents: [SessionEvent] = []
        if !currentEvents.isEmpty {
            dequeuedEvents = Array(currentEvents[0...min(currentEvents.count, numsOfEvents) - 1])
            // A batch uploads with one identity, so end it where the queued identity changes
            let identifiers = dequeuedEvents[0].identifiers
            if let end = dequeuedEvents.firstIndex(where: { $0.identifiers != identifiers }) {
                dequeuedEvents = Array(dequeuedEvents[..<end])
            }
        }
        readWriteLock.write {
            events = Array(currentEvents.dropFirst(dequeuedEvents.count))
        }

        return dequeuedEvents
    }

    func prependEvents(_ newEvents: [SessionEvent]) {
        var currentEvents: [SessionEvent] = []
        readWriteLock.read {
            currentEvents = events
        }

        if currentEvents.count + newEvents.count > queueSizeLimit {
            evictEvents(newEvents.count)
        }

        readWriteLock.read {
            currentEvents = events
        }
        readWriteLock.write {
            events = Array(newEvents + currentEvents)
        }
    }

    func clearEvents() {
        readWriteLock.write {
            events = []
        }
    }

}
