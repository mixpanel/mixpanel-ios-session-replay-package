//
//  FlushService.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation

class FlushService {
    public var wifiOnly: Bool

    private let token: String
    private let serverURL: String
    var flushTimer: Timer?
    var flushSerialQueue: DispatchQueue
    private var eventService: EventService
    private var flushRequest: FlushRequest
    private let networkMonitor: NetworkMonitoring
    private var flushInterval: TimeInterval = ReplaySettings.flushInterval

    init(
        token: String, distinctId: String, eventService: EventService, wifiOnly: Bool,
        flushRequest: FlushRequest? = nil, networkMonitor: NetworkMonitoring = NetworkMonitor.shared,
        flushInterval: TimeInterval, serverURL: String = DataResidency.us
    ) {
        self.token = token
        self.serverURL = serverURL
        self.eventService = eventService
        self.wifiOnly = wifiOnly
        self.flushRequest = flushRequest ?? FlushRequest(token: token, distinctId: distinctId, serverURL: serverURL)
        self.networkMonitor = networkMonitor
        self.flushInterval = flushInterval
        flushSerialQueue = DispatchQueue(
            label: "com.mixpanel.\(token).tracking", qos: .utility, autoreleaseFrequency: .workItem)
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

    private func flushBatch(forAll: Bool) {
        repeat {
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
                replayStartTime: SessionManager.shared.replayStartTime)

            let success = flushRequest.sendRequest(payloadInfo: payloadInfo)
            Logger.info(
                message: """
                    Distinct ID: \(getDistinctId());
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
