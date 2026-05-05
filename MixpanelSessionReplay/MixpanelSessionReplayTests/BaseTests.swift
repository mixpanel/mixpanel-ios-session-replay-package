//
//  Base.swift
//  MixpanelSessionReplay
//
//  Created by Ketan on 03/03/25.
//  Copyright © 2025 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

class BaseTests: XCTestCase {
    var mockFlushService: MockFlushService!
    var mockEventService: MockEventService!
    var instance: MPSessionReplayInstance!

    override func setUpWithError() throws {
        // Reset EventPublisher subscribers to clean slate
        EventPublisher.shared.resetSubscribers()

        // Create mock services
        mockEventService = MockEventService()
        mockFlushService = MockFlushService(
            token: "test-token",
            distinctId: "test-distinct-id",
            eventService: mockEventService,
            wifiOnly: false,
            flushRequest: FlushRequest(
                token: "test-token",
                distinctId: "test-distinct-id"
            ),
            flushInterval: ReplaySettings.flushInterval
        )

        // Create instance
        let config = MPSessionReplayConfig(wifiOnly: false, autoStartRecording: false, enableLogging: true)
        instance = MPSessionReplayInstance(
            token: "test-token", distinctId: "test-distinct-id", config: config)

        // Unsubscribe the real EventHandler to avoid conflicts
        instance.eventService.eventHandler?.shutdown()

        // Replace the instance's services with our mocks
        instance.flushService = mockFlushService
        instance.eventService = mockEventService
    }

    override func tearDownWithError() throws {
        instance.flushService.stop()
        mockEventService.eventHandler?.shutdown()
        mockFlushService = nil
        mockEventService = nil
        Swizzler.shared.unswizzle()
        EventPublisher.shared.resetSubscribers()
        instance = nil
    }

    func startRecording() {
        instance.startRecording(sessionsPercent: 100)
    }
}
