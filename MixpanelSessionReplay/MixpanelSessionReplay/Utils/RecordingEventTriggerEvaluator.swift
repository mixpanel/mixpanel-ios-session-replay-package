//
//  RecordingEventTriggerEvaluator.swift
//  MixpanelSessionReplay
//
//  Created by Mixpanel on 2026-03-03.
//

import Foundation
internal import MixpanelSwiftCommon

/// Evaluates whether an event matches trigger conditions for session replay recording.
///
/// This evaluator checks if incoming events meet the criteria specified in remote settings
/// to determine when to start a session replay recording. Evaluation happens in two stages:
///
/// 1. **Event Name Matching**: Check if the event has a registered trigger
/// 2. **Property Filtering** (optional): Evaluate JSONLogic expressions against event properties
///
/// ## Evaluation Order
/// - First checks for exact event name match in triggers dictionary
/// - Then evaluates property filters (if present) using JSONLogic
/// - Returns sampling percentage only if all conditions pass
/// - Returns nil if event doesn't match or filters fail
///
/// ## Thread Safety
/// This class is thread-safe for concurrent read access to triggers, but should be
/// initialized before use in multi-threaded contexts.
final class RecordingEventTriggerEvaluator {

    // MARK: - Properties

    private let triggers: [String: RecordingEventTrigger]
    private let jsonLogicEvaluator: JSONLogicEvaluator

    // MARK: - Initialization

    /// Initialize evaluator with trigger configuration.
    ///
    /// - Parameter triggers: Dictionary mapping event names to trigger configurations.
    ///                      Each trigger contains a sampling percentage and optional
    ///                      JSONLogic property filter expressions.
    public init(triggers: [String: RecordingEventTrigger]) {
        self.triggers = triggers
        self.jsonLogicEvaluator = JSONLogicEvaluator()
    }

    // MARK: - Public API

    /// Evaluate if an event should start recording based on trigger conditions.
    ///
    /// This method performs a two-stage evaluation:
    /// 1. Checks if the event name has a registered trigger
    /// 2. If trigger has property filters, evaluates the JSONLogic expression
    ///
    /// - Parameters:
    ///   - eventName: The name of the event to evaluate
    ///   - properties: Event properties to use for filter evaluation
    ///
    /// - Returns: The trigger's sampling percentage (0-100) if all conditions pass, `nil` otherwise.
    ///
    /// - Note: Sampling is not performed here - the percentage is returned to the caller
    ///        who decides whether to actually start recording based on random sampling.
    public func shouldStartRecording(
        for eventName: String,
        properties: [String: Any]
    ) -> Double? {
        // 1. Check if event has a registered trigger
        guard let trigger = triggers[eventName] else {
            return nil
        }

        // 2. Check property filters (if present)
        if let filters = trigger.propertyFilters {
            guard passesPropertyFilters(filters, properties: properties) else {
                return nil
            }
        }

        // Return percentage - sampling will be handled by startRecording()
        return trigger.percentage
    }

    // MARK: - Private Helpers

    /// Evaluate JSONLogic expression against properties
    private func passesPropertyFilters(
        _ filters: [String: Any],
        properties: [String: Any]
    ) -> Bool {
        do {
            return try jsonLogicEvaluator.evaluate(filters, data: properties)
        } catch {
            // Log error and fail closed (don't start recording on filter errors)
            Logger.error(message: "JSONLogic evaluation error: \(error)")
            return false
        }
    }
}
