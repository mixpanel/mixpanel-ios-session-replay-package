//  SettingsServiceTests.swift
//  MixpanelSessionReplayTests
//

import XCTest

@testable import MixpanelSessionReplay

class SettingsServiceTests: XCTestCase {
    var mockNetwork: MockNetwork!
    var mockDefaults: UserDefaults!
    var settingsService: SettingsService!
    var testSuiteName: String!
    let testToken = "testToken123"
    let version = APIConstants.currentLibVersion
    let mpLib = APIConstants.currentMpLib

    override func setUp() {
        super.setUp()

        // Create MockNetwork for testing
        mockNetwork = MockNetwork()

        // Create a fresh UserDefaults instance for testing
        testSuiteName = "com.mixpanel.test.\(UUID().uuidString)"
        mockDefaults = UserDefaults(suiteName: testSuiteName)
        mockDefaults.removePersistentDomain(forName: testSuiteName)

        // Initialize settingsService with MockNetwork
        settingsService = SettingsService(
            network: mockNetwork, version: version, mpLib: mpLib, userDefaults: mockDefaults!)
    }

    override func tearDown() {
        // Clean up mocks
        mockNetwork?.reset()
        mockNetwork = nil
        settingsService = nil

        // Clean up UserDefaults
        mockDefaults?.removePersistentDomain(forName: testSuiteName)
        mockDefaults = nil
        testSuiteName = nil

        super.tearDown()
    }

    // MARK: - Disabled Mode Behavior Tests

    func testDisabledMode_SuccessWithValidConfig_DoesNotMergeConfig() {
        // Disabled mode should fetch remote settings to check kill switch,
        // but should NOT merge remote SDK config with original config

        // Configure mock to return JSON response - tests full JSON decoding path
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {"is_enabled": true},
                "sdk_config": {
                    "config": {"record_sessions_percent": 25}
                }
            }
            """

        let originalConfig = MPSessionReplayConfig(
            wifiOnly: false,
            recordingSessionsPercent: 100,
            enableLogging: true
        )
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultSettings: SettingsResponse?
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .disabled,
            originalConfig: originalConfig
        ) { settings, updatedConfig in
            resultSettings = settings
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        // Settings should be fetched for kill switch check
        XCTAssertNotNil(resultSettings, "Settings should be fetched even in disabled mode")
        XCTAssertTrue(resultSettings?.recording?.isEnabled ?? false, "Recording should be enabled")
        XCTAssertNil(resultSettings?.sdkConfig, "Remote SDK config should not be returned.")

        // Config should NOT be merged - original config should be returned unchanged
        XCTAssertEqual(
            resultConfig?.recordingSessionsPercent, 100, "Original recordingSessionsPercent should be preserved")
        XCTAssertEqual(resultConfig?.wifiOnly, false, "Original wifiOnly should be preserved")
        XCTAssertEqual(resultConfig?.enableLogging, true, "Original enableLogging should be preserved")
    }

    func testDisabledMode_FailureWithCache_UsesCacheForKillSwitchButDoesNotMerge() {
        // Cache a successful response (using model object for caching is fine - we're testing cache retrieval)
        let cachedResponse = SettingsResponse(
            sdkConfig: SDKConfigWrapper(
                config: SDKConfig(recordSessionsPercent: 30.0, recordingEventTriggers: nil), error: nil),
            recording: RecordingSettings(isEnabled: true, error: nil)
        )
        settingsService.cacheSettingsState(settingConfig: cachedResponse, token: testToken)

        // Configure mock to return network failure
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        mockNetwork.sendRawRequestStub = { _ in
            return .failure(error)
        }

        let originalConfig = MPSessionReplayConfig(
            wifiOnly: true,
            recordingSessionsPercent: 100,
            enableLogging: false
        )
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultSettings: SettingsResponse?
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .disabled,
            originalConfig: originalConfig
        ) { settings, updatedConfig in
            resultSettings = settings
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        // Cached settings should be returned for kill switch check
        XCTAssertNotNil(resultSettings, "Cached settings should be returned")
        XCTAssertTrue(resultSettings?.recording?.isEnabled ?? false, "Cached recording should be enabled")

        // Original config should NOT be merged with cache
        XCTAssertEqual(resultConfig?.recordingSessionsPercent, 100, "Original config should be preserved")
        XCTAssertEqual(resultConfig?.wifiOnly, true, "Original config should be preserved")
        XCTAssertEqual(resultConfig?.enableLogging, false, "Original config should be preserved")
    }

    func testDisabledMode_FailureWithoutCache_UsesDefaultSettingsAndOriginalConfig() {
        // Configure mock to return failure (no cache available)
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        mockNetwork.sendRawRequestStub = { _ in
            return .failure(error)
        }

        let originalConfig = MPSessionReplayConfig(
            recordingSessionsPercent: 75,
            enableLogging: true
        )
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultSettings: SettingsResponse?
        var resultConfig: MPSessionReplayConfig?
        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .disabled,
            originalConfig: originalConfig
        ) { settings, updatedConfig in
            resultSettings = settings
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        // Default settings should be returned (recording enabled by default)
        XCTAssertNotNil(resultSettings, "Default settings should be returned")
        XCTAssertTrue(resultSettings?.recording?.isEnabled ?? false, "Default recording should be enabled")

        // Original config should be preserved
        XCTAssertEqual(resultConfig?.recordingSessionsPercent, 75, "Original config should be preserved")
        XCTAssertEqual(resultConfig?.enableLogging, true, "Original config should be preserved")
    }

    // MARK: - Strict Mode Behavior Tests

    func testStrictMode_SuccessWithValidConfig_MergesConfig() {
        // Strict mode with successful fetch should merge remote config

        // Configure mock to return JSON response - tests full JSON decoding path
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {"is_enabled": true},
                "sdk_config": {
                    "config": {"record_sessions_percent": 45}
                }
            }
            """

        let originalConfig = MPSessionReplayConfig(
            wifiOnly: false,
            recordingSessionsPercent: 100,
            enableLogging: true
        )
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultSettings: SettingsResponse?
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .strict,
            originalConfig: originalConfig
        ) { settings, updatedConfig in
            resultSettings = settings
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        // Settings should be returned
        XCTAssertNotNil(resultSettings, "Settings should be available")
        XCTAssertTrue(resultSettings?.recording?.isEnabled ?? false, "Recording should be enabled")

        // Config should be merged - remote recordingSessionsPercent applied, other fields preserved
        XCTAssertEqual(
            resultConfig?.recordingSessionsPercent, 45.0, "Remote recordingSessionsPercent should be applied")
        XCTAssertEqual(resultConfig?.wifiOnly, false, "Original wifiOnly should be preserved")
        XCTAssertEqual(resultConfig?.enableLogging, true, "Original enableLogging should be preserved")
    }

    func testStrictMode_SuccessWithPartialConfig_MergesOnlyAvailableFields() {
        // Test when SDK config is missing or null

        // Configure mock to return JSON response with error in sdkConfig (no config data)
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {"is_enabled": true},
                "sdk_config": {
                    "error": "No SDK settings found"
                }
            }
            """

        let originalConfig = MPSessionReplayConfig(
            recordingSessionsPercent: 90,
            enableLogging: false
        )
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultConfig: MPSessionReplayConfig?
        var apiSettings: SettingsResponse?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .strict,
            originalConfig: originalConfig
        ) { strictSettings, updatedConfig in
            resultConfig = updatedConfig
            apiSettings = strictSettings
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        // Original config should be preserved when no SDK config is provided
        XCTAssertEqual(
            resultConfig?.recordingSessionsPercent, 90, "Original config should be preserved when no remote SDK config")
        XCTAssertEqual(resultConfig?.enableLogging, false, "Original config should be preserved")
        XCTAssertNil(apiSettings?.sdkConfig?.config, "SDK config is disabled")
    }

    func testStrictMode_NetworkFailure_ReturnsNilSettings() {
        // Strict mode with network failure should return nil settings

        // Configure mock to return failure
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network timeout"])
        mockNetwork.sendRawRequestStub = { _ in
            return .failure(error)
        }

        let originalConfig = MPSessionReplayConfig(
            recordingSessionsPercent: 80,
            enableLogging: false
        )
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultSettings: SettingsResponse?
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .strict,
            originalConfig: originalConfig
        ) { settings, updatedConfig in
            resultSettings = settings
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        // Settings should be nil in strict mode on failure
        XCTAssertNil(resultSettings, "Settings should be nil in strict mode when API fails")

        // Original config should be returned unchanged
        XCTAssertEqual(resultConfig?.recordingSessionsPercent, 80, "Original config should be returned")
        XCTAssertEqual(resultConfig?.enableLogging, false, "Original config should be returned")
    }

    func testStrictMode_NetworkFailureWithCache_ReturnsNilSettings() {
        // Even with cache, strict mode should return nil on network failure
        let cachedResponse = SettingsResponse(
            sdkConfig: SDKConfigWrapper(
                config: SDKConfig(recordSessionsPercent: 20.0, recordingEventTriggers: nil), error: nil),
            recording: RecordingSettings(isEnabled: true, error: nil)
        )
        settingsService.cacheSettingsState(settingConfig: cachedResponse, token: testToken)

        // Configure mock to return failure
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        mockNetwork.sendRawRequestStub = { _ in
            return .failure(error)
        }

        let originalConfig = MPSessionReplayConfig(recordingSessionsPercent: 100)
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultSettings: SettingsResponse?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .strict,
            originalConfig: originalConfig
        ) { settings, updatedConfig in
            resultSettings = settings
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        // Strict mode should NOT use cache - settings should be nil
        XCTAssertNil(resultSettings, "Strict mode should return nil even with cache available")
    }

    // MARK: - Fallback Mode Behavior Tests

    func testFallbackMode_SuccessWithValidConfig_MergesConfig() {
        // Fallback mode with successful fetch should merge remote config

        // Configure mock to return JSON response - tests full JSON decoding path
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {"is_enabled": true},
                "sdk_config": {
                    "config": {"record_sessions_percent": 55}
                }
            }
            """

        let originalConfig = MPSessionReplayConfig(
            wifiOnly: true,
            recordingSessionsPercent: 100,
            enableLogging: false
        )
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultSettings: SettingsResponse?
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .fallback,
            originalConfig: originalConfig
        ) { settings, updatedConfig in
            resultSettings = settings
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        // Settings should be available
        XCTAssertNotNil(resultSettings, "Settings should be available")
        XCTAssertTrue(resultSettings?.recording?.isEnabled ?? false, "Recording should be enabled")

        // Config should be merged
        XCTAssertEqual(
            resultConfig?.recordingSessionsPercent, 55.0, "Remote recordingSessionsPercent should be applied")
        XCTAssertEqual(resultConfig?.wifiOnly, true, "Original wifiOnly should be preserved")
        XCTAssertEqual(resultConfig?.enableLogging, false, "Original enableLogging should be preserved")
    }

    func testFallbackMode_FailureWithCache_UsesCacheAndMergesConfig() {
        // Set up cached config
        let cachedResponse = SettingsResponse(
            sdkConfig: SDKConfigWrapper(
                config: SDKConfig(recordSessionsPercent: 35.0, recordingEventTriggers: nil), error: nil),
            recording: RecordingSettings(isEnabled: true, error: nil)
        )
        settingsService.cacheSettingsState(settingConfig: cachedResponse, token: testToken)

        // Configure mock to return failure
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        mockNetwork.sendRawRequestStub = { _ in
            return .failure(error)
        }

        let originalConfig = MPSessionReplayConfig(
            wifiOnly: false,
            recordingSessionsPercent: 100,
            enableLogging: true
        )
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultSettings: SettingsResponse?
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .fallback,
            originalConfig: originalConfig
        ) { settings, updatedConfig in
            resultSettings = settings
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        // Cached settings should be returned
        XCTAssertNotNil(resultSettings, "Cached settings should be available")
        XCTAssertTrue(resultSettings?.recording?.isEnabled ?? false, "Cached recording should be enabled")
        XCTAssertEqual(
            resultSettings?.sdkConfig?.config?.recordSessionsPercent, 35.0, "Cached config should be returned")

        // Config should be merged with cached remote config
        XCTAssertEqual(
            resultConfig?.recordingSessionsPercent, 35.0, "Cached remote recordingSessionsPercent should be applied")
        XCTAssertEqual(resultConfig?.wifiOnly, false, "Original wifiOnly should be preserved")
        XCTAssertEqual(resultConfig?.enableLogging, true, "Original enableLogging should be preserved")
    }

    func testFallbackMode_FailureWithCacheButNoSDKConfig_UsesOriginalConfig() {
        // Cache with recording settings but no SDK config
        let cachedResponse = SettingsResponse(
            sdkConfig: nil,
            recording: RecordingSettings(isEnabled: true, error: nil)
        )
        settingsService.cacheSettingsState(settingConfig: cachedResponse, token: testToken)

        // Configure mock to return failure
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        mockNetwork.sendRawRequestStub = { _ in
            return .failure(error)
        }

        let originalConfig = MPSessionReplayConfig(
            recordingSessionsPercent: 85,
            enableLogging: true
        )
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .fallback,
            originalConfig: originalConfig
        ) { settings, updatedConfig in
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        // Original config should be preserved when cache has no SDK config
        XCTAssertEqual(resultConfig?.recordingSessionsPercent, 85, "Original config should be preserved")
        XCTAssertEqual(resultConfig?.enableLogging, true, "Original config should be preserved")
    }

    func testFallbackMode_FailureWithoutCache_UsesOriginalConfig() {
        // No cache, network failure

        // Configure mock to return failure
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        mockNetwork.sendRawRequestStub = { _ in
            return .failure(error)
        }

        let originalConfig = MPSessionReplayConfig(
            wifiOnly: true,
            recordingSessionsPercent: 95,
            enableLogging: false
        )
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultSettings: SettingsResponse?
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .fallback,
            originalConfig: originalConfig
        ) { settings, updatedConfig in
            resultSettings = settings
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        // Default settings should be returned (recording enabled by default)
        XCTAssertNotNil(resultSettings, "Default settings should be available")
        XCTAssertTrue(resultSettings?.recording?.isEnabled ?? false, "Default recording should be enabled")

        // Original config should be preserved
        XCTAssertEqual(resultConfig?.recordingSessionsPercent, 95, "Original config should be preserved")
        XCTAssertEqual(resultConfig?.wifiOnly, true, "Original config should be preserved")
        XCTAssertEqual(resultConfig?.enableLogging, false, "Original config should be preserved")
    }

    // MARK: - Remote Settings Mode Tests

    func testRemoteSettingsModeDisabled() {
        // Mode: disabled still fetches remote settings to check the recording kill switch,
        // but does NOT merge SDK config with original config

        // Configure mock to return JSON response - tests full JSON decoding path
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {"is_enabled": true},
                "sdk_config": {
                    "config": {"record_sessions_percent": 50}
                }
            }
            """

        let config = MPSessionReplayConfig(
            recordingSessionsPercent: 100,
            remoteSettingsMode: .disabled
        )
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultConfig: MPSessionReplayConfig?
        var resultSettings: SettingsResponse?
        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .disabled,
            originalConfig: config
        ) { settings, updatedConfig in
            resultSettings = settings
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        XCTAssertNotNil(resultSettings, "Settings should be fetched to check recording kill switch")
        XCTAssertTrue(resultSettings?.recording?.isEnabled ?? false, "Recording should be enabled")
        XCTAssertEqual(
            resultConfig?.recordingSessionsPercent, 100,
            "Original config should be unchanged - no merging in disabled mode")
    }

    func testRemoteSettingsModeStrictSuccess() {
        // Mode: strict with successful fetch should apply remote config

        // Configure mock to return JSON response - tests full JSON decoding path
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {"is_enabled": true},
                "sdk_config": {
                    "config": {"record_sessions_percent": 50}
                }
            }
            """

        // Verify query parameters
        mockNetwork.sendRawRequestStub = { [weak self] apiRequest in
            guard let self = self else { fatalError("self is nil") }
            XCTAssertTrue(apiRequest.queryItems?.contains(URLQueryItem(name: "recording", value: "1")) ?? false)
            XCTAssertTrue(apiRequest.queryItems?.contains(URLQueryItem(name: "sdk_config", value: "1")) ?? false)
            XCTAssertTrue(apiRequest.queryItems?.contains(URLQueryItem(name: "mp_lib", value: "swift-sr")) ?? false)
            return .success((self.mockNetwork.responseJson!.data(using: .utf8)!, HTTPURLResponse()))
        }

        let config = MPSessionReplayConfig(remoteSettingsMode: .strict)
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .strict,
            originalConfig: config
        ) { settings, updatedConfig in
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        XCTAssertEqual(resultConfig?.recordingSessionsPercent, 50.0, "Remote config should be applied")
    }

    func testRemoteSettingsModeStrictFailure() {
        // Mode: strict with failed fetch should return nil settings (SDK will not initialize)

        // Configure mock to return failure
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        mockNetwork.sendRawRequestStub = { _ in
            return .failure(error)
        }

        let config = MPSessionReplayConfig(
            recordingSessionsPercent: 100.0,
            remoteSettingsMode: .strict
        )
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultSettings: SettingsResponse?
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .strict,
            originalConfig: config
        ) { settings, updatedConfig in
            resultSettings = settings
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        XCTAssertNil(
            resultSettings, "Settings should be nil in strict mode on failure, signaling SDK should not initialize")
        XCTAssertEqual(resultConfig?.autoStartRecording, true, "Original config should be returned unchanged")
    }

    func testRemoteSettingsModeFallbackSuccess() {
        // Mode: fallback with successful fetch should apply remote config

        // Configure mock to return JSON response - tests full JSON decoding path
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {"is_enabled": true},
                "sdk_config": {
                    "config": {"record_sessions_percent": 75}
                }
            }
            """

        let config = MPSessionReplayConfig(
            recordingSessionsPercent: 100,
            remoteSettingsMode: .fallback
        )
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .fallback,
            originalConfig: config
        ) { settings, updatedConfig in
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        XCTAssertEqual(resultConfig?.recordingSessionsPercent, 75.0, "Remote config should be applied")
    }

    func testRemoteSettingsModeFallbackFailureWithCache() {
        // Set up cached config with different value
        let cachedResponse = SettingsResponse(
            sdkConfig: SDKConfigWrapper(
                config: SDKConfig(recordSessionsPercent: 25.0, recordingEventTriggers: nil), error: nil),
            recording: RecordingSettings(isEnabled: true, error: nil)
        )
        settingsService.cacheSettingsState(settingConfig: cachedResponse, token: testToken)

        // Configure mock to return failure
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        mockNetwork.sendRawRequestStub = { _ in
            return .failure(error)
        }

        let config = MPSessionReplayConfig(
            recordingSessionsPercent: 100,
            remoteSettingsMode: .fallback
        )
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .fallback,
            originalConfig: config
        ) { settings, updatedConfig in
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        XCTAssertEqual(resultConfig?.recordingSessionsPercent, 25.0, "Cached config should be used")
        XCTAssertTrue(
            resultConfig?.autoStartRecording ?? false, "Auto-recording should remain enabled in fallback mode")
    }

    func testRemoteSettingsModeFallbackFailureNoCache() {
        // Mode: fallback with failed fetch and no cache should use original config

        // Configure mock to return failure
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        mockNetwork.sendRawRequestStub = { _ in
            return .failure(error)
        }

        let config = MPSessionReplayConfig(
            recordingSessionsPercent: 100,
            remoteSettingsMode: .fallback
        )
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .fallback,
            originalConfig: config
        ) { settings, updatedConfig in
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        XCTAssertEqual(resultConfig?.recordingSessionsPercent, 100, "Original config should be used when no cache")
        XCTAssertTrue(resultConfig?.autoStartRecording ?? false, "Auto-recording should remain enabled")
    }

    // MARK: - SDK Config Merging Tests

    func testSDKConfigMergingAppliesRecordSessionsPercent() {
        // Configure mock to return JSON response - tests full JSON decoding path
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {"is_enabled": true},
                "sdk_config": {
                    "config": {"record_sessions_percent": 33.5}
                }
            }
            """

        let config = MPSessionReplayConfig(recordingSessionsPercent: 100)
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .fallback,
            originalConfig: config
        ) { settings, updatedConfig in
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        XCTAssertEqual(resultConfig?.recordingSessionsPercent, 33.5)
    }

    func testSDKConfigMergingPreservesOtherSettings() {
        // Configure mock to return JSON response - tests full JSON decoding path
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {"is_enabled": true},
                "sdk_config": {
                    "config": {"record_sessions_percent": 50}
                }
            }
            """

        let config = MPSessionReplayConfig(
            wifiOnly: false,
            recordingSessionsPercent: 100.0,
            enableLogging: true
        )
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .fallback,
            originalConfig: config
        ) { settings, updatedConfig in
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        XCTAssertEqual(resultConfig?.wifiOnly, false, "wifiOnly should be preserved")
        XCTAssertEqual(resultConfig?.autoStartRecording, true, "autoStartRecording should be preserved")
        XCTAssertEqual(resultConfig?.enableLogging, true, "enableLogging should be preserved")
        XCTAssertEqual(resultConfig?.recordingSessionsPercent, 50.0, "recordingSessionsPercent should be updated")
    }

    // MARK: - Query Parameter Tests

    func testRequestIncludesAllRequiredQueryParameters() {
        // Configure mock to return JSON response - tests full JSON decoding path
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {"is_enabled": true}
            }
            """

        // Verify all required query parameters are present
        mockNetwork.sendRawRequestStub = { [weak self] apiRequest in
            guard let self = self else { fatalError("self is nil") }
            XCTAssertTrue(apiRequest.queryItems?.contains(URLQueryItem(name: "recording", value: "1")) ?? false)
            XCTAssertTrue(apiRequest.queryItems?.contains(URLQueryItem(name: "sdk_config", value: "1")) ?? false)
            XCTAssertTrue(apiRequest.queryItems?.contains(URLQueryItem(name: "mp_lib", value: "swift-sr")) ?? false)
            XCTAssertTrue(
                apiRequest.queryItems?.contains(URLQueryItem(name: "$lib_version", value: self.version)) ?? false)
            XCTAssertTrue(apiRequest.queryItems?.contains(URLQueryItem(name: "$os", value: "iOS")) ?? false)
            return .success((self.mockNetwork.responseJson!.data(using: .utf8)!, HTTPURLResponse()))
        }

        let config = MPSessionReplayConfig()
        let expectation = self.expectation(description: "Completion handler invoked")

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .fallback,
            originalConfig: config
        ) { _, _ in
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)
    }

    // MARK: - Legacy Recording Field Tests

    func testLegacyRecordingFieldDisabled() {
        // Configure mock to return JSON response with recording disabled
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {
                    "is_enabled": false,
                    "error": "Recording disabled"
                }
            }
            """

        let config = MPSessionReplayConfig()
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultSettings: SettingsResponse?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .fallback,
            originalConfig: config
        ) { settings, _ in
            resultSettings = settings
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        XCTAssertNotNil(resultSettings?.recording)
        XCTAssertFalse(resultSettings?.recording?.isEnabled ?? true)
        XCTAssertEqual(resultSettings?.recording?.error, "Recording disabled")
    }

    func testResponseWithoutSDKConfig() {
        // Configure mock to return JSON response without sdk_config
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {"is_enabled": true}
            }
            """

        let config = MPSessionReplayConfig(recordingSessionsPercent: 100)
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .fallback,
            originalConfig: config
        ) { settings, updatedConfig in
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        XCTAssertEqual(
            resultConfig?.recordingSessionsPercent, 100, "Original config should be preserved when no sdk_config")
    }

    // MARK: - Cache Tests

    func testCacheIsUpdatedOnSuccessfulFetch() {
        // Configure mock to return JSON response - tests full JSON decoding path
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {"is_enabled": true},
                "sdk_config": {
                    "config": {"record_sessions_percent": 60}
                }
            }
            """

        let config = MPSessionReplayConfig()
        let expectation = self.expectation(description: "Completion handler invoked")

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .fallback,
            originalConfig: config
        ) { _, _ in
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        // Verify cache was updated
        let cached = settingsService.getCachedSettingsState(token: testToken)
        XCTAssertEqual(cached.sdkConfig?.config?.recordSessionsPercent, 60.0)
        XCTAssertTrue(cached.recording?.isEnabled ?? false)
    }

    func testTimeout() {
        // Test that timeout error is handled correctly

        // Configure mock to return timeout error (synchronously, no sleep needed)
        let timeoutError = NSError(
            domain: NetworkError.domain,
            code: NetworkError.timeoutErrorCode,
            userInfo: [NSLocalizedDescriptionKey: "Request timed out"]
        )
        mockNetwork.sendRawRequestStub = { _ in
            return .failure(timeoutError)
        }

        let config = MPSessionReplayConfig()
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .fallback,
            originalConfig: config
        ) { _, updatedConfig in
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        // Should use original config in fallback mode on timeout
        XCTAssertEqual(resultConfig?.recordingSessionsPercent, 100)
    }

    // MARK: - Invalid recordSessionsPercent Tests

    func testSDKConfigMergingIgnoresInvalidRecordSessionsPercent_Negative() {
        // Configure mock to return JSON response with invalid negative value
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {"is_enabled": true},
                "sdk_config": {
                    "config": {"record_sessions_percent": -10}
                }
            }
            """

        let config = MPSessionReplayConfig(recordingSessionsPercent: 100)
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .fallback,
            originalConfig: config
        ) { settings, updatedConfig in
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        XCTAssertEqual(
            resultConfig?.recordingSessionsPercent, 100,
            "Invalid negative value should be ignored, original config preserved")
    }

    func testSDKConfigMergingIgnoresInvalidRecordSessionsPercent_GreaterThan100() {
        // Configure mock to return JSON response with invalid >100 value
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {"is_enabled": true},
                "sdk_config": {
                    "config": {"record_sessions_percent": 150}
                }
            }
            """

        let config = MPSessionReplayConfig(recordingSessionsPercent: 100)

        let expectation = self.expectation(description: "Completion handler invoked")
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .fallback,
            originalConfig: config
        ) { settings, updatedConfig in
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        XCTAssertEqual(
            resultConfig?.recordingSessionsPercent, 100,
            "Invalid >100 value should be ignored, original config preserved")
    }

    func testSDKConfigMergingAcceptsValidBoundaryValues() {
        // Test 0.0 (valid lower bound)
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {"is_enabled": true},
                "sdk_config": {
                    "config": {"record_sessions_percent": 0}
                }
            }
            """

        let config0 = MPSessionReplayConfig(recordingSessionsPercent: 100)
        let expectation0 = self.expectation(description: "Completion handler invoked for 0.0")
        var resultConfig0: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .fallback,
            originalConfig: config0
        ) { settings, updatedConfig in
            resultConfig0 = updatedConfig
            expectation0.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertEqual(resultConfig0?.recordingSessionsPercent, 0.0, "0.0 should be accepted as valid")

        // Test 100.0 (valid upper bound)
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {"is_enabled": true},
                "sdk_config": {
                    "config": {"record_sessions_percent": 100}
                }
            }
            """

        let config100 = MPSessionReplayConfig(recordingSessionsPercent: 50)
        let expectation100 = self.expectation(description: "Completion handler invoked for 100.0")
        var resultConfig100: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .fallback,
            originalConfig: config100
        ) { settings, updatedConfig in
            resultConfig100 = updatedConfig
            expectation100.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertEqual(resultConfig100?.recordingSessionsPercent, 100.0, "100.0 should be accepted as valid")
    }

    // MARK: - Disabled Mode Failure Tests

    func testRemoteSettingsModeDisabledFailureUsesCache() {
        // Set up cached config
        let cachedResponse = SettingsResponse(
            sdkConfig: SDKConfigWrapper(
                config: SDKConfig(recordSessionsPercent: 30.0, recordingEventTriggers: nil), error: nil),
            recording: RecordingSettings(isEnabled: true, error: nil)
        )
        settingsService.cacheSettingsState(settingConfig: cachedResponse, token: testToken)

        // Configure mock to return failure
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        mockNetwork.sendRawRequestStub = { _ in
            return .failure(error)
        }

        let config = MPSessionReplayConfig(
            recordingSessionsPercent: 100,
            remoteSettingsMode: .disabled
        )
        let expectation = self.expectation(description: "Completion handler invoked")
        var resultSettings: SettingsResponse?
        var resultConfig: MPSessionReplayConfig?

        settingsService.getRemoteConfiguration(
            token: testToken,
            mode: .disabled,
            originalConfig: config
        ) { settings, updatedConfig in
            resultSettings = settings
            resultConfig = updatedConfig
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5, handler: nil)

        XCTAssertNotNil(resultSettings, "Settings should be available from cache")
        XCTAssertTrue(resultSettings?.recording?.isEnabled ?? false, "Cached recording should be enabled")
        XCTAssertEqual(
            resultConfig?.recordingSessionsPercent, 100, "Original config should not be merged in disabled mode")
    }

    // MARK: - Cache Key Tests

    func testCacheKeysAreDifferentForDifferentTokens() {
        let token1 = "token1"
        let token2 = "token2"

        let cachedResponse1 = SettingsResponse(
            sdkConfig: SDKConfigWrapper(
                config: SDKConfig(recordSessionsPercent: 25.0, recordingEventTriggers: nil), error: nil),
            recording: RecordingSettings(isEnabled: true, error: nil)
        )
        let cachedResponse2 = SettingsResponse(
            sdkConfig: SDKConfigWrapper(
                config: SDKConfig(recordSessionsPercent: 75.0, recordingEventTriggers: nil), error: nil),
            recording: RecordingSettings(isEnabled: false, error: "Disabled for token2")
        )

        settingsService.cacheSettingsState(settingConfig: cachedResponse1, token: token1)
        settingsService.cacheSettingsState(settingConfig: cachedResponse2, token: token2)

        let retrieved1 = settingsService.getCachedSettingsState(token: token1)
        let retrieved2 = settingsService.getCachedSettingsState(token: token2)

        XCTAssertEqual(retrieved1.sdkConfig?.config?.recordSessionsPercent, 25.0)
        XCTAssertEqual(retrieved2.sdkConfig?.config?.recordSessionsPercent, 75.0)
        XCTAssertTrue(retrieved1.recording?.isEnabled ?? false)
        XCTAssertFalse(retrieved2.recording?.isEnabled ?? true)
    }
}
