//
//  EventBridgeHandler.swift
//  MixpanelSessionReplay
//
//  Created by Mixpanel on 2026-03-03.
//

import Foundation

/// Handles events from mixpanel-swift SDK to trigger session replay recording.
///
/// This handler evaluates event triggers and starts recording when conditions are met.
/// Receives events via AsyncStream from EventBridge and processes them in the Task context.
///
/// ## Event Flow
/// 1. Receives MixpanelEvent from EventBridge's AsyncStream consumption
/// 2. Checks if event triggers are enabled
/// 3. Evaluates trigger conditions (event name + property filters)
/// 4. If matched, starts recording on main thread with specified percentage
final class EventBridgeHandler {

    // MARK: - Properties

    private let evaluator: RecordingEventTriggerEvaluator

    // MARK: - Initialization

    /// Initialize handler with event trigger configuration.
    ///
    /// - Parameter triggers: Dictionary mapping event names to trigger configurations.
    ///                      Each trigger specifies a sampling percentage and optional
    ///                      property filters (JSONLogic expressions).
    public init(
        triggers: [String: RecordingEventTrigger]
    ) {
        evaluator = RecordingEventTriggerEvaluator(triggers: triggers)
    }

    // MARK: - Event Processing

    /// Process an event received from the Mixpanel SDK via AsyncStream bridge.
    ///
    /// Evaluates the event against configured triggers and starts recording if conditions match.
    /// Called from EventBridge's Task context; recording initiation happens on main thread.
    ///
    /// - Parameters:
    ///   - name: The event name to evaluate
    ///   - properties: Event properties used for JSONLogic filter evaluation
    ///
    /// - Note: Returns early if event triggers are disabled. Only starts recording if not
    ///         already recording.
    internal func processEvent(name: String, properties: [String: Any]) {
        // Check if event triggers are enabled
        guard MPSessionReplay.getInstance()?.isEventTriggersEnabled == true else {
            Logger.debug(message: "Event triggers disabled, ignoring event: \(name)")
            return
        }

        // Evaluate trigger conditions (returns percentage if matched, nil otherwise)
        guard
            let percentage = evaluator.shouldStartRecording(
                for: name,
                properties: properties
            )
        else {
            return
        }

        Logger.info(message: "Event trigger matched: \(name), percentage: \(percentage)%. Starting recording.")

        // Start recording with trigger percentage
        MPSessionReplay.getInstance()?.startRecording(sessionsPercent: percentage)
    }
}
