//
//  SessionManager.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation

class SessionManager {
    internal private(set) static var shared: SessionManager = SessionManager()

    var seqId: Int
    var replayId: String
    var replayStartTime: TimeInterval
    var batchStartTime: TimeInterval

    private init() {
        seqId = 0
        replayId = UUID().uuidString
        replayStartTime = Date().timeIntervalSince1970
        batchStartTime = replayStartTime
    }

    static func reset() {
        SessionManager.shared = SessionManager()
    }

    func increaseSeqId() {
        seqId += 1
    }

    func generateNewSession() {
        seqId = 0
        replayId = UUID().uuidString
        replayStartTime = Date().timeIntervalSince1970
        batchStartTime = replayStartTime
    }
}
