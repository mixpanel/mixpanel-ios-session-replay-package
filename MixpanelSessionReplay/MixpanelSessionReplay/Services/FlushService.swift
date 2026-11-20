//
//  FlushService.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation
internal import MixpanelSwiftCommon

class FlushService {
    public var wifiOnly: Bool

    private let token: String
    private let serverURL: String
    var flushTimer: Timer?
    var flushSerialQueue: DispatchQueue
    private var eventService: EventService
    /// Written only on `flushSerialQueue`; the lock lets other threads read it safely.
    private var flushRequest: FlushRequest {
        get {
            flushRequestLock.lock()
            defer { flushRequestLock.unlock() }
            return storedFlushRequest
        }
        set {
            flushRequestLock.lock()
            storedFlushRequest = newValue
            flushRequestLock.unlock()
            stampNewEvents()
        }
    }
    private var storedFlushRequest: FlushRequest
    private let flushRequestLock = NSLock()
    private let networkMonitor: NetworkMonitoring
    private var flushInterval: TimeInterval = ReplaySettings.flushInterval
    private let flushQueueKey = DispatchSpecificKey<Void>()

    convenience init(
        token: String, distinctId: String, eventService: EventService,
        wifiOnly: Bool,
        flushRequest: FlushRequest? = nil, networkMonitor: NetworkMonitoring = NetworkMonitor.shared,
        flushInterval: TimeInterval, serverURL: String = DataResidency.us
    ) {
        self.init(
            token: token, identifiers: ReplayIdentifiers(distinctId: distinctId), eventService: eventService,
            wifiOnly: wifiOnly, flushRequest: flushRequest, networkMonitor: networkMonitor,
            flushInterval: flushInterval, serverURL: serverURL)
    }

    init(
        token: String, identifiers: ReplayIdentifiers, eventService: EventService,
        wifiOnly: Bool,
        flushRequest: FlushRequest? = nil, networkMonitor: NetworkMonitoring = NetworkMonitor.shared,
        flushInterval: TimeInterval, serverURL: String = DataResidency.us
    ) {
        self.token = token
        self.serverURL = serverURL
        self.eventService = eventService
        self.wifiOnly = wifiOnly
        self.storedFlushRequest =
            flushRequest
            ?? FlushRequest(token: token, identifiers: identifiers, serverURL: serverURL)
        self.networkMonitor = networkMonitor
        self.flushInterval = flushInterval
        flushSerialQueue = DispatchQueue(
            label: "com.mixpanel.\(token).tracking", qos: .utility, autoreleaseFrequency: .workItem)
        flushSerialQueue.setSpecific(key: flushQueueKey, value: ())
        stampNewEvents()
    }

    /// Events queued while identified with a `MixpanelIdentity` keep it until they upload, even if the
    /// identity changes before then. Events queued under a plain distinct id carry no stamp and upload
    /// with the distinct id current at flush time.
    private func stampNewEvents() {
        let identifiers = flushRequest.identifiers
        eventService.setIdentifiersForNewEvents(identifiers.identity == nil ? nil : identifiers)
    }

    func start() {
        // Timer requires to be initialised on a thread with run loop like main thread
        // else it will not work
        ThreadUtils.runOnMainThread { [weak self] in
            if let self = self {
                self.flushTimer?.invalidate()
                self.flushTimer = nil
                self.flushTimer = Timer.scheduledTimer(
                    timeInterval: flushInterval, target: self, selector: #selector(self.flushEventsFromTimer),
                    userInfo: nil, repeats: true)
            }
        }
    }

    func stop() {
        // Invalidate the timer on same thread where it was initialised.
        ThreadUtils.runOnMainThread { [weak self] in
            if let self = self {
                self.flushTimer?.invalidate()
                self.flushTimer = nil
            }
        }
    }

    @objc private func flushEventsFromTimer() {
        flushEvents()
    }

    func flushEvents(forAll: Bool = false, completionHandler: @escaping () -> Void = {}) {
        if wifiOnly && !networkMonitor.isUsingWiFi {
            Logger.warn(message: "Device is not using Wi-Fi, skipping flush request")
            completionHandler()
            return
        }
        flushSerialQueue.async {
            self.flushBatch(forAll: forAll)
            completionHandler()
        }
    }

    func getDistinctId() -> String {
        return flushRequest.distinctId
    }

    func updateDistinctId(_ distinctId: String) {
        self.flushRequest = FlushRequest(token: token, distinctId: distinctId, serverURL: serverURL)
        Logger.info(message: "Updated distinct id successfully.")
    }

    /// The current distinct id and identity, read together from one `FlushRequest`.
    func getIdentifiers() -> ReplayIdentifiers {
        return flushRequest.identifiers
    }

    /// Whether an identity change is still waiting to run on `flushSerialQueue`. While one is, the
    /// current identifiers are not final, so callers must not skip a change because it matches them.
    var hasPendingIdentityChanges: Bool {
        pendingIdentityChangesLock.lock()
        defer { pendingIdentityChangesLock.unlock() }
        return pendingIdentityChanges > 0
    }
    private var pendingIdentityChanges = 0
    private let pendingIdentityChangesLock = NSLock()

    /// Replaces the distinct id and identity on `flushSerialQueue`, so it never races a flush reading
    /// `flushRequest`. Runs inline when already on the queue, such as from a flush completion handler.
    ///
    /// The comparison with the current identifiers happens on the queue when the change applies, so
    /// changes apply in call order and the last call wins. Identifiers that already match change
    /// nothing. Dropping the identity while keeping the distinct id needs no flush: events already
    /// queued keep the identity they were captured with. Any other change first flushes all queued
    /// events, unless `wifiOnly` skips uploads off Wi-Fi.
    func changeIdentifiers(to identifiers: ReplayIdentifiers, completion: @escaping () -> Void = {}) {
        pendingIdentityChangesLock.lock()
        pendingIdentityChanges += 1
        pendingIdentityChangesLock.unlock()
        performOnFlushQueue {
            let current = self.flushRequest.identifiers
            if current != identifiers {
                let dropsIdentityOnly = identifiers.identity == nil && identifiers.distinctId == current.distinctId
                if !dropsIdentityOnly {
                    self.flushAllBeforeIdentityChange()
                }
                self.flushRequest = FlushRequest(
                    token: self.token, identifiers: identifiers, serverURL: self.serverURL)
                Logger.info(message: "Updated identity successfully.")
            }
            self.pendingIdentityChangesLock.lock()
            self.pendingIdentityChanges -= 1
            self.pendingIdentityChangesLock.unlock()
            completion()
        }
    }

    /// Uploads all queued events under the current identifiers. Runs on `flushSerialQueue`.
    func flushAllBeforeIdentityChange() {
        if wifiOnly && !networkMonitor.isUsingWiFi {
            Logger.warn(message: "Device is not using Wi-Fi, skipping flush request")
            return
        }
        flushBatch(forAll: true)
    }

    private func performOnFlushQueue(_ work: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: flushQueueKey) != nil {
            work()
        } else {
            flushSerialQueue.async(execute: work)
        }
    }

    private func flushBatch(forAll: Bool) {
        repeat {
            // Check if we're in exponential backoff before attempting to flush
            if flushRequest.requestNotAllowed() {
                break
            }

            let events = eventService.dequeueEvents(ReplaySettings.queueBatchSize)
            guard !events.isEmpty else {
                return
            }

            let replayEndTime = TimeInterval(events[events.count - 1].timestamp) / 1000.0
            var batchStartTime: TimeInterval
            if SessionManager.shared.seqId == 0 {
                batchStartTime = SessionManager.shared.replayStartTime
            } else {
                batchStartTime = TimeInterval(events[0].timestamp) / 1000.0
            }
            let replayLengthMs = TimestampUtils.timeIntervalToMs(
                replayEndTime - SessionManager.shared.replayStartTime)
            if replayLengthMs < 0 {
                // Clean up the corrupted events
                eventService.clearEvents()
                return
            }
            let payloadInfo = PayloadInfo(
                sessionEvents: events,
                batchStartTime: batchStartTime,
                seq: SessionManager.shared.seqId,
                replayId: SessionManager.shared.replayId,
                replayLengthMs: replayLengthMs,
                replayStartTime: SessionManager.shared.replayStartTime,
                identifiers: events[0].identifiers)

            let success = flushRequest.sendRequest(payloadInfo: payloadInfo)
            Logger.info(
                message: """
                    Distinct ID: \(payloadInfo.identifiers?.distinctId ?? getDistinctId());
                    Batch Start Time: \(payloadInfo.batchStartTime);
                    Sequence ID: \(payloadInfo.seq);
                    Replay ID: \(payloadInfo.replayId);
                    Replay Length (ms): \(payloadInfo.replayLengthMs);
                    Replay Start Time: \(payloadInfo.replayStartTime)
                    """)

            if success {
                Logger.info(
                    message: """
                        \(payloadInfo.sessionEvents.count) replay events have been successfully flushed to the server.
                        """)
                SessionManager.shared.increaseSeqId()
            } else {
                Logger.warn(message: "Failed to flush events to the server.")
                eventService.prependEvents(events)
                break
            }
        } while forAll && !eventService.isEventsEmpty
    }
}
