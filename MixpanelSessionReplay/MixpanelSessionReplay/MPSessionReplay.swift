//
//  MPSessionReplay.swift
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation
import UIKit

public enum MPSessionReplayError: Error {
    case failedToInitialize
    case disabledByRemoteSetting(message: String)
    case custom(message: String)
}

open class MPSessionReplay {
    /// Initializes the Mixpanel Session Replay system with the provided configuration.
    ///
    /// This method first checks device compatibility, then verifies remote configuration to determine
    /// if session recording is enabled before creating a new `MPSessionReplayInstance`. If a previous
    /// instance exists, it will be deinitialized first.
    ///
    /// - Parameters:
    ///   - token: The Mixpanel project token used to identify the project.
    ///   - distinctId: A unique identifier for the current user.
    ///   - config: The configuration object used to customize session replay behavior. Defaults to `MPSessionReplayConfig()`.
    ///   - completion: A closure called on the main thread after initialization completes. Defaults to a no-op closure.
    ///                 Returns a `Result` where:
    ///                 - `.success(instance)`: Indicates initialization was successful and recording is enabled from remote settings.
    ///                 - `.failure(error)`: Indicates initialization failed due to one of the following:
    ///                   - Device incompatibility (e.g., iOS 26+ without `enableSessionReplayOniOS26AndLater` set to `true`)
    ///                   - Recording disabled via remote settings
    ///                   - Other setup errors
    ///
    /// - Note: On iOS 26 and later, Session Replay is disabled by default due to SwiftUI architectural changes.
    ///         Set `config.enableSessionReplayOniOS26AndLater = true` to explicitly enable it on these versions.
    /// - Note: The `completion` handler is always invoked on the main thread to ensure thread-safety when interacting with UI-related code.
    open class func initialize(
        token: String, distinctId: String, config: MPSessionReplayConfig = MPSessionReplayConfig(),
        completion: @escaping (Result<MPSessionReplayInstance?, Error>) -> Void = { _ in }
    ) {
        let isCompatible = SessionReplayCompatibilityChecker.isCompatible()
        if isCompatible == .compatible || config.enableSessionReplayOniOS26AndLater {
            if isCompatible != .compatible {
                debugPrint(
                    "[Mixpanel Session Replay - MPSessionReplay.swift - func \(#function)] (warning) - Session Replay is being force enabled on an iOS 26+ device. Ensure you have tested thoroughly as iOS 26 Liquid Glass UI changes may impact sensitive content masking."
                )
            }

            MPSessionReplayManager.sharedInstance.initialize(
                token: token, distinctId: distinctId, config: config, completion: completion)
        } else {
            completion(.failure(MPSessionReplayError.custom(message: isCompatible.description)))
        }
    }

    open class func getInstance() -> MPSessionReplayInstance? {
        return MPSessionReplayManager.sharedInstance.getInstance()
    }

    ///Get session replay id of the current recording session
    open class func getReplayId() -> String? {
        if MPSessionReplay.getInstance()?.isRecording == true {
            return SessionManager.shared.replayId
        }
        return nil
    }

    /// Returns the URL to view the current session replay in the Mixpanel dashboard.
    ///
    /// - Returns: The session replay URL if recording is active, or `nil` if not recording.
    open class func getSessionReplayURL() -> String? {
        return MPSessionReplay.getInstance()?.getSessionReplayURL()
    }
}

final class MPSessionReplayManager {
    static let sharedInstance = MPSessionReplayManager()
    private var instance: MPSessionReplayInstance?

    // MARK: - Test Hooks
    /// Test hook to override the default SettingsService with a mock implementation.
    /// Used for integration testing to inject dependencies.
    var testOverride_settingsService: SettingsService?

    private init() {
        Logger.addLogging(PrintLogging.shared)
    }

    func updateLoggingEnabled(_ enabled: Bool) {
        if enabled {
            Logger.enableLevel(.debug)
            Logger.enableLevel(.info)
            Logger.enableLevel(.warning)
            Logger.enableLevel(.error)
            Logger.info(message: "Logging Enabled")
        } else {
            Logger.info(message: "Logging Disabled")
            Logger.disableLevel(.debug)
            Logger.disableLevel(.info)
            Logger.disableLevel(.warning)
            Logger.disableLevel(.error)
        }
    }

    /// Initializes the Session Replay system by creating a new `MPSessionReplayInstance`,
    /// only if remote settings allow recording.
    ///
    /// This method first deinitializes any existing session replay instance. It then checks
    /// the remote configuration to determine whether recording is enabled. If recording is
    /// enabled, it creates and stores a new instance of `MPSessionReplayInstance`. The entire
    /// initialization process is asynchronous and the result is returned via the completion handler.
    ///
    /// - Parameters:
    ///   - token: The Mixpanel project token used for identifying the project.
    ///   - distinctId: A unique identifier for the current user.
    ///   - config: Configuration object used to customize session replay behavior.
    ///   - completion: A closure called on the main thread after initialization completes.
    ///                 Returns a `Result` where:
    ///                 - `.success(instance)`: Indicates initialization was successful and recording is enabled from remote settings.
    ///                 - `.failure(error)`: Indicates initialization failed. The error will specify whether the failure
    ///                   was due to the initialization error, recording being disabled via remote settings, or other setup errors.
    ///
    /// - Thread Safety: The completion block is always executed on the main thread. This avoids
    ///   threading issues when working with UI components or observers that may be initialized inside the instance.
    func initialize(
        token: String, distinctId: String, config: MPSessionReplayConfig,
        completion: @escaping (Result<MPSessionReplayInstance?, Error>) -> Void
    ) {
        deinitializeInstance()

        updateLoggingEnabled(config.enableLogging)

        // Check settings before creating instance
        let settingsService =
            testOverride_settingsService
            ?? SettingsService(
                version: APIConstants.currentLibVersion,
                mpLib: APIConstants.currentMpLib
            )
        settingsService.getRemoteConfiguration(
            token: token,
            mode: config.remoteSettingsMode,
            originalConfig: config
        ) { [weak self] settings, updatedConfig in
            guard let self = self else {
                completion(.failure(MPSessionReplayError.failedToInitialize))
                return
            }

            // Strict mode: If settings fetch failed (settings is nil) or settings are disabled from dashboard (config is nil), do not initialize SDK
            if config.remoteSettingsMode == .strict && settings?.sdkConfig?.config == nil {
                let reason =
                    settings == nil
                    ? "Remote settings fetch failed or timed out"
                    : settings?.sdkConfig?.error ?? "Remote SDK config disabled on dashboard"
                PrintLogging.shared.log(
                    .error, "SDK will not initialize: \(reason). Remote settings mode is set to strict.")
                completion(
                    .failure(
                        MPSessionReplayError.custom(
                            message: "Strict mode requires remote settings. SDK initialization failed: \(reason)")))
                return
            }

            // Check recording setting(remote enablement switch) to initialize the SDK
            if let recording = settings?.recording, !recording.isEnabled {
                PrintLogging.shared.log(.warning, "Session Replay is disabled via remote settings.")
                let errorMessage = recording.error ?? "Recording is disabled by remote config setting."
                completion(.failure(MPSessionReplayError.disabledByRemoteSetting(message: errorMessage)))
                return
            }

            ThreadUtils.runOnMainThread {
                // Use the updated config that may have been merged with remote settings
                self.instance = MPSessionReplayInstance(token: token, distinctId: distinctId, config: updatedConfig)
                self.setupEventTriggers(
                    token: token, recordingEventTriggers: settings?.sdkConfig?.config?.recordingEventTriggers)
                completion(.success(self.instance))
            }
        }
    }

    /// Deinitializes the current `MPSessionReplayInstance`, cleaning up all related services and observers.
    ///
    /// - This method stops recording, flushes and clears event data, removes observers,
    ///   resets session managers, and unswizzles any UIKit methods swizzled during initialization.
    /// - Should be called before reinitializing the SDK or when shutting down session replay functionality.
    func deinitializeInstance() {
        ThreadUtils.runOnMainThread(async: false) { [weak self] in
            if let self = self, let instance = self.instance {
                // Shutdown event triggers first
                self.shutdownEventTriggers()

                instance.eventService.clearEvents()
                instance.eventService.eventHandler?.shutdown()
                instance.stopRecording()
                instance.removeObservers()
                instance.flushService.stop()
                EventPublisher.shared.resetSubscribers()
                SessionManager.reset()
                SensitiveViewManager.reset()
                Swizzler.shared.unswizzle()
                self.instance = nil
            }
        }
    }

    func getInstance() -> MPSessionReplayInstance? {
        return instance
    }

    // MARK: - Event Trigger Setup

    /// Set up event triggers by fetching settings and registering with bridge
    private func setupEventTriggers(token: String, recordingEventTriggers: [String: RecordingEventTrigger]?) {
        guard let triggers = recordingEventTriggers, !triggers.isEmpty else {
            Logger.info(message: "No event triggers configured. Event-based recording disabled.")
            return
        }

        // Reset event triggers flag to enabled when setting up new triggers
        MPSessionReplay.getInstance()?.enableEventTriggers()

        Logger.info(message: "Configuring \(triggers.count) event trigger(s)")

        let handler = EventBridgeHandler(
            triggers: triggers
        )
        EventBridge.startConsuming(handler: handler)
    }

    /// Shutdown event triggers and stop stream consumption
    func shutdownEventTriggers() {
        // Stop stream consumption and clean up task
        EventBridge.stopConsuming()
    }
}

// Integrates Session Replay data with regular Mixpanel event tracking.
class MPSessionReplaySender {
    static let shared = MPSessionReplaySender()

    static let registerNotificationName = Notification.Name("com.mixpanel.properties.register")
    static let unregisterNotificationName = Notification.Name("com.mixpanel.properties.unregister")

    func register(data: [AnyHashable: Any]? = nil) {
        NotificationCenter.default.post(
            name: MPSessionReplaySender.registerNotificationName, object: nil, userInfo: data)
    }

    func unregister(_ key: String) {
        NotificationCenter.default.post(
            name: MPSessionReplaySender.unregisterNotificationName, object: nil, userInfo: [key: ""])
    }
}
