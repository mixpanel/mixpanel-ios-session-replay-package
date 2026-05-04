//
//  MPSessionReplayConfigTests.swift
//  MixpanelSessionReplay
//
//  Created by Ketan on 03/03/25.
//  Copyright © 2025 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

class MPSessionReplayConfigTests: XCTestCase {
    func testDefaultInitialization() {
        let config = MPSessionReplayConfig()

        XCTAssertTrue(config.wifiOnly, "Default wifiOnly should be true")
        XCTAssertTrue(config.autoStartRecording, "Default autoStartRecording should be true")
        XCTAssertEqual(config.recordingSessionsPercent, 100, "Default recordingSessionsPercent should be 100")
        XCTAssertEqual(
            config.autoMaskedViews, [.image, .text, .web, .map],
            "Default autoMaskedViews should contain image, text, web, and map")
        XCTAssertEqual(config.enableLogging, false, "Default enableLogging should be false")
        XCTAssertEqual(
            config.flushInterval, ReplaySettings.flushInterval,
            "Default flushInterval should be equal to specified constant")
        XCTAssertNil(config.debugOptions, "Default debugOptions should be nil")
    }

    func testCustomInitialization() {
        let config = MPSessionReplayConfig(
            wifiOnly: false, autoMaskedViews: [.image, .web],
            autoStartRecording: false, recordingSessionsPercent: 75.0, enableLogging: true, flushInterval: 1.0,
            debugOptions: DebugOptions())

        XCTAssertFalse(config.wifiOnly)
        XCTAssertFalse(config.autoStartRecording)
        XCTAssertEqual(config.recordingSessionsPercent, 75.0)
        XCTAssertEqual(config.autoMaskedViews, [.image, .web])
        XCTAssertTrue(config.enableLogging)
        XCTAssertEqual(config.flushInterval, 1.0)
        XCTAssertNotNil(config.debugOptions)
    }

    func testEncodingToJSON() throws {
        let config = MPSessionReplayConfig(
            wifiOnly: false, autoMaskedViews: [.text], recordingSessionsPercent: 50.0, flushInterval: 1.0)

        let jsonData = try config.toJSON()
        XCTAssertNotNil(jsonData)

        let jsonString = String(data: jsonData, encoding: .utf8)
        XCTAssertNotNil(jsonString)
    }

    func testDecodingFromJSON() throws {
        let jsonString = """
            {
                "wifiOnly": false,
                "recordingSessionsPercent": 50.0,
                "autoMaskedViews": ["text", "map"],
                "autoStartRecording": false,
                "remoteSettingsMode": "disabled",
                "enableLogging": true,
                "flushInterval": 10.0,
                "enableSessionReplayOniOS26AndLater": true
            }
            """
        let jsonData = jsonString.data(using: .utf8)!
        let decodedConfig = try MPSessionReplayConfig.from(json: jsonData)

        XCTAssertFalse(decodedConfig.wifiOnly)
        XCTAssertFalse(decodedConfig.autoStartRecording)
        XCTAssertEqual(decodedConfig.recordingSessionsPercent, 50.0)
        XCTAssertEqual(decodedConfig.autoMaskedViews, [.text, .map])
        XCTAssertTrue(decodedConfig.enableLogging)
        XCTAssertEqual(decodedConfig.flushInterval, 10.0)
        XCTAssertEqual(decodedConfig.enableSessionReplayOniOS26AndLater, true)
        XCTAssertNil(decodedConfig.debugOptions)
    }

    func testEncodingAndDecoding() throws {
        let originalConfig = MPSessionReplayConfig(
            wifiOnly: true, autoMaskedViews: [.web], recordingSessionsPercent: 30.0, flushInterval: 1.0)

        let jsonData = try originalConfig.toJSON()
        let decodedConfig = try MPSessionReplayConfig.from(json: jsonData)

        XCTAssertEqual(
            originalConfig.wifiOnly, decodedConfig.wifiOnly,
            "wifiOnly should match after encoding and decoding")
        XCTAssertEqual(
            originalConfig.recordingSessionsPercent, decodedConfig.recordingSessionsPercent,
            "recordSessionsPercent should match after encoding and decoding")
        XCTAssertEqual(
            originalConfig.autoMaskedViews, decodedConfig.autoMaskedViews,
            "autoMaskedViews should match after encoding and decoding")
        XCTAssertEqual(originalConfig.autoStartRecording, decodedConfig.autoStartRecording)
        XCTAssertEqual(originalConfig.enableLogging, decodedConfig.enableLogging)
        XCTAssertEqual(
            originalConfig.flushInterval, decodedConfig.flushInterval,
            "flushInterval should match after encoding and decoding")
        XCTAssertNil(decodedConfig.debugOptions, "debugOptions should be nil after decoding (excluded from Codable)")
    }

    func testEmptyAutoMaskedViews() {
        let config = MPSessionReplayConfig(autoMaskedViews: [])
        XCTAssertTrue(config.autoMaskedViews.isEmpty)
    }

    // MARK: - RemoteSettingsMode Tests

    func testDefaultRemoteSettingsMode() {
        let config = MPSessionReplayConfig()
        XCTAssertEqual(config.remoteSettingsMode, .disabled, "Default remoteSettingsMode should be .disabled")
    }

    func testRemoteSettingsModeInitialization() {
        let configDisabled = MPSessionReplayConfig(remoteSettingsMode: .disabled)
        XCTAssertEqual(configDisabled.remoteSettingsMode, .disabled)

        let configStrict = MPSessionReplayConfig(remoteSettingsMode: .strict)
        XCTAssertEqual(configStrict.remoteSettingsMode, .strict)

        let configFallback = MPSessionReplayConfig(remoteSettingsMode: .fallback)
        XCTAssertEqual(configFallback.remoteSettingsMode, .fallback)
    }

    func testRemoteSettingsModeEncodingDecoding() throws {
        // Test disabled mode
        let configDisabled = MPSessionReplayConfig(remoteSettingsMode: .disabled)
        let jsonDataDisabled = try configDisabled.toJSON()
        let decodedConfigDisabled = try MPSessionReplayConfig.from(json: jsonDataDisabled)
        XCTAssertEqual(decodedConfigDisabled.remoteSettingsMode, .disabled)

        // Test strict mode
        let configStrict = MPSessionReplayConfig(remoteSettingsMode: .strict)
        let jsonDataStrict = try configStrict.toJSON()
        let decodedConfigStrict = try MPSessionReplayConfig.from(json: jsonDataStrict)
        XCTAssertEqual(decodedConfigStrict.remoteSettingsMode, .strict)

        // Test fallback mode
        let configFallback = MPSessionReplayConfig(remoteSettingsMode: .fallback)
        let jsonDataFallback = try configFallback.toJSON()
        let decodedConfigFallback = try MPSessionReplayConfig.from(json: jsonDataFallback)
        XCTAssertEqual(decodedConfigFallback.remoteSettingsMode, .fallback)
    }

    func testRemoteSettingsModeJSONDecoding() throws {
        let jsonStringDisabled = """
            {
                "wifiOnly": true,
                "recordingSessionsPercent": 100.0,
                "autoMaskedViews": ["text"],
                "autoStartRecording": true,
                "remoteSettingsMode": "disabled",
                "enableLogging": false,
                "flushInterval": 10.0,
                "enableSessionReplayOniOS26AndLater": false
            }
            """
        let jsonDataDisabled = jsonStringDisabled.data(using: .utf8)!
        let decodedConfigDisabled = try MPSessionReplayConfig.from(json: jsonDataDisabled)
        XCTAssertEqual(decodedConfigDisabled.remoteSettingsMode, .disabled)

        let jsonStringStrict = """
            {
                "wifiOnly": true,
                "recordingSessionsPercent": 100.0,
                "autoMaskedViews": ["text"],
                "autoStartRecording": true,
                "remoteSettingsMode": "strict",
                "enableLogging": false,
                "flushInterval": 10.0,
                "enableSessionReplayOniOS26AndLater": false
            }
            """
        let jsonDataStrict = jsonStringStrict.data(using: .utf8)!
        let decodedConfigStrict = try MPSessionReplayConfig.from(json: jsonDataStrict)
        XCTAssertEqual(decodedConfigStrict.remoteSettingsMode, .strict)

        let jsonStringFallback = """
            {
                "wifiOnly": true,
                "recordingSessionsPercent": 100.0,
                "autoMaskedViews": ["text"],
                "autoStartRecording": true,
                "remoteSettingsMode": "fallback",
                "enableLogging": false,
                "flushInterval": 10.0,
                "enableSessionReplayOniOS26AndLater": false
            }
            """
        let jsonDataFallback = jsonStringFallback.data(using: .utf8)!
        let decodedConfigFallback = try MPSessionReplayConfig.from(json: jsonDataFallback)
        XCTAssertEqual(decodedConfigFallback.remoteSettingsMode, .fallback)
    }
}
