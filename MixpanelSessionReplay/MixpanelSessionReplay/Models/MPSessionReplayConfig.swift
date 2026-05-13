//
//  MPSessionReplayConfig.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation

/// Defines an enum of views that Mixpanel Session Replay can automatically mask.
public enum MPAutoMaskedViews: String, Codable {
    case image, text, web, map
}

/// Defines how remote configuration settings influence SDK initialization.
///
/// Remote settings enable server-side control over session replay parameters such as
/// sampling rate. This enum determines the SDK's behavior when fetching these
/// settings and how failures are handled.
///
/// | Mode | Remote Fetch | On Failure | Dashboard Disabled |
/// |------|--------------|------------|-------------------|
/// | `disabled` | Yes | N/A | N/A |
/// | `strict` | Yes | SDK won't initialize | SDK won't initialize |
/// | `fallback` | Yes | Uses cache or local config | local config |
///
public enum RemoteSettingsMode: String, Codable {
    /// Ignores remote SDK config settings entirely.
    /// The settings are still fetched to check if the session replay recording is enabled for the account.
    ///
    /// The SDK initializes using only the app-provided configuration.
    ///
    /// Use this mode when you want full local control over session replay configuration.
    case disabled

    /// Requires successful remote SDK config settings fetch for SDK initialization.
    ///
    /// The SDK fetches configuration from Mixpanel servers and uses it for initialization.
    /// If any of the following occur, the SDK **will not initialize** and no sessions are recorded:
    /// - Network request fails or times out
    /// - Server returns an error response
    /// - Remote settings are disabled in the Mixpanel dashboard
    ///
    /// Use this mode when centralized control is critical and you prefer
    /// no recording with potentially outdated settings.
    case strict

    /// Attempts remote fetch with graceful degradation on failure.
    ///
    /// The SDK attempts to fetch SDK configuration from Mixpanel servers. If successful,
    /// remote settings are applied and cached locally. For any configuration parameters
    /// not present in the remote response, the SDK uses the app-provided values.
    ///
    /// If the fetch fails or times out, the SDK initializes using the following priority:
    /// 1. Previously cached remote settings (from last successful fetch)
    /// 2. App-provided configuration
    ///
    /// Use this mode for a balance between remote control and reliability,
    /// ensuring session replay functions even with intermittent connectivity.
    case fallback
}

public struct MPSessionReplayConfig: Codable {

    /// Determines whether replay events will only be flushed to the server when the device has a WiFi connection.
    ///
    /// - When set to `true`, replay events will only be flushed to the server when the device has a WiFi connection.
    ///   If there is no WiFi, flushes are skipped and the events remain in the in-memory queue until WiFi is restored (or until the queue reaches its limit and the oldest events are evicted to make room for newer events).
    /// - When set to `false`, replay events will be flushed with any network connection, including cellular.
    /// - Default: `true`
    public var wifiOnly: Bool = true

    /// Controls the sampling rate for automatically started recording session replays.
    ///
    /// This value (between 0.0 and 100.0) defines the percentage of sessions that will automatically start recording when a new session begins.
    ///
    /// - At 0.0, no sessions will be auto-recorded.
    /// - At 100.0, all sessions will be auto-recorded.
    /// - Default: 100
    /// - This setting is not used when invoking `startRecording()` manually.
    public var recordingSessionsPercent: Double = 100

    /// Determines whether or not the SDK will automatically start recording session replays upon initialization.
    ///
    /// - When set to `true`, the SDK will automatically start recording session replays when the instance is initialized. The recording will
    /// be stopped and started automatically whenever the app goes to background and comes to foreground.
    /// For each new automatically started session, the SDK uses `recordingSessionsPercent`
    /// to determine whether recording should begin for that session.
    ///
    /// - When set to `false`, the SDK will not start recording until explicitly invoked by calling `startRecording()`.
    /// - Default: `true`
    @available(
        *, deprecated,
        message:
            "Use `recordingSessionsPercent` instead. Setting `recordingSessionsPercent` to 0 disables auto-start recording, while any value greater than 0 enables it. This property will be removed in a future release."
    )
    public var autoStartRecording: Bool = true

    /// Returns the set of views that are automatically masked by the SDK.
    /// By default, image, text, web(WKWebView) and map(MKMapView) views are masked.
    /// This default behavior can be overridden through the configuration.
    public var autoMaskedViews: Set<MPAutoMaskedViews> = [.image, .text, .web, .map]

    /// Specifies how the SDK should handle remote configuration fetched from Mixpanel servers.
    ///
    /// Remote settings allow you to dynamically control session replay behavior from the Mixpanel dashboard
    /// without requiring an app update. This property determines whether remote settings are used
    /// and how the SDK behaves when fetching fails.
    ///
    /// - Note: Remote settings are fetched once during SDK initialization.
    ///
    /// ## Example
    /// ```swift
    /// var config = MPSessionReplayConfig()
    /// config.remoteSettingsMode = .fallback
    /// ```
    ///
    /// - SeeAlso: ``RemoteSettingsMode``
    public var remoteSettingsMode: RemoteSettingsMode = .disabled

    /// Specifies the flush interval in seconds. The default is 10 seconds.
    /// Screenshots are collected and sent to Mixpanel in batches of 10.
    /// One batch is sent after each flush interval.
    /// You can adjust the flush interval to delay or expedite the sending of screenshots.
    public var flushInterval: TimeInterval = ReplaySettings.flushInterval

    /// Enables debug-level logging for the SDK.
    ///
    /// - When set to `true`, the SDK will print verbose debug logs to the console to assist with development and troubleshooting.
    ///   These logs may include internal events, configuration status, and lifecycle hooks relevant to session replay.
    ///
    /// - When set to `false`, logging is suppressed except for critical errors or warnings.
    ///
    /// - Default: `false`
    public var enableLogging: Bool = false

    /// Forces Session Replay to be enabled on iOS 26 and later, bypassing compatibility checks.
    ///
    /// ## Overview
    /// Apple's iOS 26 introduces "Liquid Glass" rendering changes that affect automasking
    /// in Session Replay for SwiftUI apps. This is an industry-wide issue impacting all
    /// session replay vendors. By default, Session Replay is now disabled for apps built with
    /// Xcode 26+ and running on iOS 26+ as precautionary measure.
    /// Do not rely solely on automasking. Instead, manually mark sensitive views using 'mpReplaySensitive(true)'
    /// and test thoroughly to ensure masking works as expected.
    ///
    /// Set this flag to `true` during SDK initialization if you want to force-enable
    /// Session Replay despite potential masking limitations.
    ///
    /// ## Important: Testing Required
    /// Before turning on Session Replay for production, confirm that your masking configuration
    /// works as expected by reviewing captured replays in test builds. You are responsible
    /// for ensuring that no sensitive data is recorded.
    ///
    /// > Warning: If you detect missing or incorrect masking of sensitive content,
    /// > do not proceed with a production rollout until the problem is fixed.
    ///
    /// - Default: `false`
    public var enableSessionReplayOniOS26AndLater: Bool = false

    /// Debug feature configuration. When not nil, debug features are enabled.
    ///
    /// Only works in debug builds to prevent accidental exposure in production.
    ///
    /// - Default: `nil` (disabled)
    /// - SeeAlso: ``DebugOptions``, ``DebugOverlayColors``
    public var debugOptions: DebugOptions?

    /// Specifies the data residency base URL for sending session replay data.
    ///
    /// Use the predefined data residency constants:
    /// - `MPSessionReplayAPI.usDataResidency` - US data residency (default): "https://api-js.mixpanel.com"
    /// - `MPSessionReplayAPI.euDataResidency` - EU data residency: "https://api-eu.mixpanel.com"
    /// - `MPSessionReplayAPI.inDataResidency` - India data residency: "https://api-in.mixpanel.com"
    ///
    /// Example:
    /// ```swift
    /// let config = MPSessionReplayConfig(serverURL: MPSessionReplayAPI.euDataResidency)
    /// ```
    ///
    /// - Note: The URL is trimmed and validated when SDK is getting initialized. If url validation fails, SDK will not be initialized.
    ///
    /// - Default: `MPSessionReplayAPI.usDataResidency` (US data residency)
    public var serverURL: String = MPSessionReplayAPI.usDataResidency {
        didSet {
            serverURL = getTrimmedServerURL(urlString: serverURL)
        }
    }

    /// Initializes a new `MPSessionReplayConfig` with the provided settings.
    ///
    /// - Parameters:
    ///   - wifiOnly: Determines whether replay events will only be flushed on WiFi connections.
    ///   - autoMaskedViews: Defines the views (from the `MPAutoMaskedViews` enum) that should be automatically masked in the replay.
    ///   This parameter is optional, with a default value of `[.image, .text, .web, .map]`.
    ///   To disable masking completely, explicitly pass an empty set `[]`.
    ///   - autoStartRecording: **Deprec ated**, use `recordingSessionsPercent` instead. This property will be removed in a future release.
    ///   - recordingSessionsPercent: The sampling rate for automatically started recording session replays.
    ///   - remoteSettingsMode: Controls how remote configuration settings are fetched.
    ///   - enableLogging: Enables debug-level logging for the SDK.
    ///   - flushInterval: Specifies the flush interval in seconds.
    ///   - enableSessionReplayOniOS26AndLater: Forces Session Replay to be enabled on iOS 26 and later.
    ///   - debugOptions: Debug feature configuration. When not nil, enables debug features (debug builds only).
    ///   - serverURL: The data residency base URL. Use `MPSessionReplayAPI.usDataResidency` (default), `MPSessionReplayAPI.euDataResidency`, `MPSessionReplayAPI.inDataResidency`, or a custom URL.
    public init(
        wifiOnly: Bool = true,
        autoMaskedViews: Set<MPAutoMaskedViews> = [.image, .text, .web, .map],
        autoStartRecording: Bool = true,
        recordingSessionsPercent: Double = 100,
        remoteSettingsMode: RemoteSettingsMode = .disabled,
        enableLogging: Bool = false,
        flushInterval: TimeInterval = 10,
        enableSessionReplayOniOS26AndLater: Bool = false,
        debugOptions: DebugOptions? = nil,
        serverURL: String = MPSessionReplayAPI.usDataResidency,
    ) {
        self.wifiOnly = wifiOnly
        self.autoMaskedViews = autoMaskedViews
        self.autoStartRecording = autoStartRecording
        self.recordingSessionsPercent = recordingSessionsPercent
        self.remoteSettingsMode = remoteSettingsMode
        self.enableLogging = enableLogging
        self.flushInterval = flushInterval
        self.enableSessionReplayOniOS26AndLater = enableSessionReplayOniOS26AndLater
        self.debugOptions = debugOptions
        self.serverURL = getTrimmedServerURL(urlString: serverURL)
    }

    /// Validates the serverURL and logs errors if invalid
    public func validateServerURL() -> Bool {
        // Check if URL can be constructed
        guard let url = URL(string: serverURL) else {
            PrintLogging.shared.log(
                .error,
                "Invalid serverURL provided: '\(serverURL)'. This is not a valid URL format. Session replay data will fail to send. Please provide a valid HTTPS URL."
            )
            return false
        }

        // Check if using HTTPS
        guard url.scheme == "https" else {
            let scheme = url.scheme ?? "unknown"
            PrintLogging.shared.log(
                .error,
                "Insecure serverURL provided: '\(serverURL)'. The URL uses '\(scheme)' instead of 'https'. Session replay data transmission requires HTTPS for security. Please use a valid HTTPS URL."
            )
            return false
        }

        // Check if host exists and is not empty
        guard let host = url.host, !host.isEmpty else {
            PrintLogging.shared.log(
                .error,
                "Invalid serverURL provided: '\(serverURL)'. The URL has no valid host. Session replay data will fail to send. Please provide a complete URL with a valid host."
            )
            return false
        }

        // Check if URL contains a path (should be base URL only)
        if !url.path.isEmpty && url.path != "/" {
            PrintLogging.shared.log(
                .error,
                "Invalid serverURL provided: '\(serverURL)'. The URL should not contain a path. Please provide only the base URL (e.g., 'https://api.mixpanel.com' not 'https://api.mixpanel.com/path"
            )
            return false
        }

        return true
    }

    private func getTrimmedServerURL(urlString: String) -> String {
        return urlString.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "/")))
    }

    // Initialize from JSON
    public static func from(json: Data) throws -> MPSessionReplayConfig {
        let decoder = JSONDecoder()
        return try decoder.decode(MPSessionReplayConfig.self, from: json)
    }

    // Convert to JSON
    func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
}
