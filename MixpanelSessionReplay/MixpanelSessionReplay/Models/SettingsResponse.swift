//
//  SettingsResponse.swift
//  MixpanelSessionReplay
//

import Foundation

struct SettingsResponse: Codable {
    let sdkConfig: SDKConfigWrapper?

    // Recording field to enable/disable recording remotely
    let recording: RecordingSettings?

    // Wireframe field to enable/disable wireframe capture remotely. Only present in the
    // response when the SDK asked for it (`wireframe=1`), which it only does when
    // `MPSessionReplayConfig.wireframesOptions` is non-nil.
    let wireframe: WireframeSettings?

    private enum CodingKeys: String, CodingKey {
        case sdkConfig = "sdk_config"
        case recording
        case wireframe
    }

    /// Explicit init so existing call sites that predate `wireframe` keep compiling.
    init(sdkConfig: SDKConfigWrapper?, recording: RecordingSettings?, wireframe: WireframeSettings? = nil) {
        self.sdkConfig = sdkConfig
        self.recording = recording
        self.wireframe = wireframe
    }
}

struct SDKConfigWrapper: Codable {
    let config: SDKConfig?
    let error: String?
}

struct SDKConfig: Codable {
    let recordSessionsPercent: Double?
    let recordingEventTriggers: [String: RecordingEventTrigger]?

    private enum CodingKeys: String, CodingKey {
        case recordSessionsPercent = "record_sessions_percent"
        case recordingEventTriggers = "recording_event_triggers"
    }
}

struct RecordingSettings: Codable {
    let isEnabled: Bool
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case error
    }

    init(isEnabled: Bool, error: String?) {
        self.isEnabled = isEnabled
        self.error = error
    }
}

/// Remote kill switch for wireframe capture, independent of the `recording` switch:
/// replay keeps recording, only the wireframe payload is dropped.
struct WireframeSettings: Codable {
    let isEnabled: Bool
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case error
    }

    init(isEnabled: Bool, error: String?) {
        self.isEnabled = isEnabled
        self.error = error
    }
}

extension RecordingSettings {
    static var `default`: RecordingSettings {
        RecordingSettings(isEnabled: true, error: nil)
    }
}

extension WireframeSettings {
    static var `default`: WireframeSettings {
        WireframeSettings(isEnabled: true, error: nil)
    }
}

extension SettingsResponse {
    static var `default`: SettingsResponse {
        SettingsResponse(
            sdkConfig: nil,
            recording: .default,
            wireframe: .default
        )
    }
}
