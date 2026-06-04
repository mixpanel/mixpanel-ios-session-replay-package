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
                "enableSessionReplayOniOS26AndLater": true,
                "serverURL": "https://api.mixpanel.com"
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
        XCTAssertEqual(decodedConfig.serverURL, "https://api.mixpanel.com")
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

    // MARK: - Data Center Configuration Tests

    func testDefaultServerUrlIsUSDataResidency() {
        let config = MPSessionReplayConfig()
        XCTAssertEqual(
            config.serverURL,
            DataResidency.us,
            "Default serverURL should be US data residency"
        )
    }

    func testCustomServerUrlUSDataResidency() {
        let config = MPSessionReplayConfig(serverURL: DataResidency.us)
        XCTAssertEqual(config.serverURL, DataResidency.us)
    }

    func testCustomServerUrlEUDataResidency() {
        let config = MPSessionReplayConfig(serverURL: DataResidency.eu)
        XCTAssertEqual(
            config.serverURL,
            DataResidency.eu,
            "Should accept EU data residency URL"
        )
    }

    func testCustomServerUrlIndiaDataResidency() {
        let config = MPSessionReplayConfig(serverURL: DataResidency.in)
        XCTAssertEqual(
            config.serverURL,
            DataResidency.in,
            "Should accept India data residency URL"
        )
    }

    func testCustomServerUrlWithCustomURL() {
        let customURL = "https://custom.mixpanel.com"
        let config = MPSessionReplayConfig(serverURL: customURL)
        XCTAssertEqual(
            config.serverURL,
            customURL,
            "Should accept custom data residency URL"
        )
    }

    func testServerUrlEncodingDecoding() throws {
        let originalConfig = MPSessionReplayConfig(serverURL: DataResidency.eu)
        let jsonData = try originalConfig.toJSON()
        let decodedConfig = try MPSessionReplayConfig.from(json: jsonData)

        XCTAssertEqual(
            originalConfig.serverURL,
            decodedConfig.serverURL,
            "serverURL should match after encoding and decoding"
        )
    }

    func testServerUrlInJSONDecoding() throws {
        let jsonString = """
            {
                "wifiOnly": true,
                "recordingSessionsPercent": 100.0,
                "autoMaskedViews": ["image", "text"],
                "autoStartRecording": true,
                "remoteSettingsMode": "disabled",
                "enableLogging": false,
                "flushInterval": 10.0,
                "enableSessionReplayOniOS26AndLater": false,
                "serverURL": "https://api-eu.mixpanel.com"
            }
            """
        let jsonData = jsonString.data(using: .utf8)!
        let decodedConfig = try MPSessionReplayConfig.from(json: jsonData)

        XCTAssertEqual(
            decodedConfig.serverURL,
            "https://api-eu.mixpanel.com",
            "Should correctly decode serverURL from JSON"
        )
    }

    // MARK: - Server URL Validation Tests

    func testValidateServerUrlWithUSDataResidency() {
        let config = MPSessionReplayConfig(serverURL: DataResidency.us)
        let isValid = config.validateServerURL()
        XCTAssertTrue(isValid, "US data residency URL should be valid")
    }

    func testValidateServerUrlWithEUDataResidency() {
        let config = MPSessionReplayConfig(serverURL: DataResidency.eu)
        let isValid = config.validateServerURL()
        XCTAssertTrue(isValid, "EU data residency URL should be valid")
    }

    func testValidateServerUrlWithIndiaDataResidency() {
        let config = MPSessionReplayConfig(serverURL: DataResidency.in)
        let isValid = config.validateServerURL()
        XCTAssertTrue(isValid, "India data residency URL should be valid")
    }

    func testValidateServerUrlWithCustomValidUrl() {
        let customURL = "https://custom.mixpanel.com"
        let config = MPSessionReplayConfig(serverURL: customURL)
        let isValid = config.validateServerURL()
        XCTAssertTrue(isValid, "Custom HTTPS URL should be valid")
    }

    func testValidateServerUrlWithInvalidFormat() {
        let invalidURL = "not-a-url-at-all"
        let config = MPSessionReplayConfig(serverURL: invalidURL)
        let isValid = config.validateServerURL()
        XCTAssertFalse(isValid, "Malformed URL should be invalid")
    }

    func testValidateServerUrlWithHTTP() {
        let insecureURL = "http://insecure.mixpanel.com"
        let config = MPSessionReplayConfig(serverURL: insecureURL)
        let isValid = config.validateServerURL()
        XCTAssertFalse(isValid, "HTTP URL should be invalid (requires HTTPS)")
    }

    func testValidateServerUrlWithoutHost() {
        let urlWithoutHost = "https://"
        let config = MPSessionReplayConfig(serverURL: urlWithoutHost)
        let isValid = config.validateServerURL()
        XCTAssertFalse(isValid, "URL without host should be invalid")
    }

    func testValidateServerUrlWithEmptyString() {
        let emptyURL = ""
        let config = MPSessionReplayConfig(serverURL: emptyURL)
        let isValid = config.validateServerURL()
        XCTAssertFalse(isValid, "Empty URL should be invalid")
    }

    func testValidateServerUrlWithPath() {
        let urlWithPath = "https://api.mixpanel.com/some/path"
        let config = MPSessionReplayConfig(serverURL: urlWithPath)
        let isValid = config.validateServerURL()
        XCTAssertFalse(isValid, "HTTPS URL with path should be invalid")
    }

    func testValidateServerUrlWithFTPScheme() {
        let ftpURL = "ftp://ftp.mixpanel.com"
        let config = MPSessionReplayConfig(serverURL: ftpURL)
        let isValid = config.validateServerURL()
        XCTAssertFalse(isValid, "FTP URL should be invalid (requires HTTPS)")
    }

    func testValidateServerUrlWithOnlyPath() {
        let onlyPath = "/just/a/path"
        let config = MPSessionReplayConfig(serverURL: onlyPath)
        let isValid = config.validateServerURL()
        XCTAssertFalse(isValid, "Path-only string should be invalid")
    }

    func testConfigInitializationWithInvalidUrlStillStoresIt() {
        // Even with invalid URL, config should initialize and store it
        let invalidURL = "not-a-url"
        let config = MPSessionReplayConfig(serverURL: invalidURL)

        XCTAssertEqual(
            config.serverURL,
            invalidURL,
            "Config should store invalid URL (validation logs error but doesn't prevent storage)"
        )
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
                "serverURL": "https://api.mixpanel.com",
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
                "serverURL": "https://api.mixpanel.com",
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
                "serverURL": "https://api.mixpanel.com",
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
