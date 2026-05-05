//
//  EventBridge.swift
//  MixpanelSessionReplay
//
//  Created by Ketan on 09/03/26.
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import Foundation
internal import MixpanelSwiftCommon  // Prevents ABI exposure; silences library evolution warning

/// AsyncStream-based bridge to connect Session Replay with the main Mixpanel SDK.
///
/// This bridge uses Swift Concurrency (AsyncStream) to consume events from mixpanel-swift's
/// MixpanelEventBridge.
///
/// ## Usage
/// ```swift
/// let handler = EventBridgeHandler(triggers: eventTriggers)
/// EventBridge.startConsuming(handler: handler)
/// // Later...
/// EventBridge.stopConsuming()
/// ```
internal struct EventBridge {

    // MARK: - Properties

    /// Active consumption task
    private static var consumptionTask: Task<Void, Never>?

    /// Retained reference to handler
    internal static var eventBridgeHandler: EventBridgeHandler?

    // MARK: - Stream Consumption

    /// Start consuming events from MixpanelBridge AsyncStream.
    ///
    /// Creates a detached Task that consumes events from `MixpanelBridge.shared.eventStream()`
    /// and forwards them to the handler. Automatically stops any existing consumption first.
    ///
    /// - Parameter handler: The handler that will process each MixpanelEvent instance
    ///
    /// - Note: Requires iOS 13.0+. Safe to call multiple times. Handler is retained until
    ///         `stopConsuming()` is called.
    internal static func startConsuming(handler: EventBridgeHandler) {
        // Check runtime availability
        guard #available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *) else {
            Logger.warn(message: "AsyncStream requires iOS 13+. Event triggers unavailable.")
            return
        }

        // Clean up any existing consumption
        stopConsuming()

        // Store handler reference
        eventBridgeHandler = handler

        // Start consuming stream in detached task
        consumptionTask = Task.detached(priority: .high) {
            let stream = MixpanelEventBridge.shared.eventStream()

            for await event in stream {
                // Check for cancellation
                guard !Task.isCancelled else {
                    Logger.debug(message: "Event consumption task cancelled")
                    break
                }

                // Forward to handler
                handler.processEvent(
                    name: event.eventName,
                    properties: event.properties
                )
            }

            Logger.debug(message: "Event stream terminated")
        }

        Logger.info(message: "Started consuming MixpanelBridge stream")
    }

    /// Stop consuming events and clean up resources.
    ///
    /// Cancels the active consumption Task and releases the handler reference.
    /// Safe to call even if no consumption is active.
    internal static func stopConsuming() {
        consumptionTask?.cancel()
        consumptionTask = nil
        eventBridgeHandler = nil

        Logger.info(message: "Stopped consuming MixpanelBridge stream")
    }
}
