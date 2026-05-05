//
//  SettingsResponse.swift
//  MixpanelSessionReplay
//

import Foundation

struct SettingsResponse: Codable {
    let sdkConfig: SDKConfigWrapper?

    // Recording field to enable/disable recording remotely
    let recording: RecordingSettings?

    private enum CodingKeys: String, CodingKey {
        case sdkConfig = "sdk_config"
        case recording
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

extension RecordingSettings {
    static var `default`: RecordingSettings {
        RecordingSettings(isEnabled: true, error: nil)
    }
}

extension SettingsResponse {
    static var `default`: SettingsResponse {
        SettingsResponse(
            sdkConfig: nil,
            recording: .default
        )
    }
}
