//
//  MPSessionReplayTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2025 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

class MPSessionReplayTests: XCTestCase {
    let testToken = "testToken123"
    let testDistinctId = "testUser123"
    var mockNetwork: MockNetwork!
    var settingsService: SettingsService!

    override func setUp() {
        super.setUp()

        // Clean up the SDK's UserDefaults cache for the test token
        let settingsDefaults = UserDefaults(suiteName: ReplaySettings.userDefaultsName) ?? UserDefaults.standard
        settingsDefaults.removeObject(forKey: "mp_sr_recording_settings_config_\(testToken)")
        settingsDefaults.removeObject(forKey: "mp_sr_recording_timestamp_\(testToken)")

        // Create MockNetwork and inject into real SettingsService
        mockNetwork = MockNetwork()
        settingsService = SettingsService(
            network: mockNetwork,
            version: APIConstants.currentLibVersion,
            mpLib: APIConstants.currentMpLib,
            userDefaults: settingsDefaults
        )

        // Inject SettingsService (with MockNetwork) into MPSessionReplayManager
        MPSessionReplayManager.sharedInstance.testOverride_settingsService = settingsService
    }

    override func tearDown() {
        // Clean up the SDK's UserDefaults cache
        let settingsDefaults = UserDefaults(suiteName: ReplaySettings.userDefaultsName) ?? UserDefaults.standard
        settingsDefaults.removeObject(forKey: "mp_sr_recording_settings_config_\(testToken)")
        settingsDefaults.removeObject(forKey: "mp_sr_recording_timestamp_\(testToken)")

        // Deinitialize any instance
        MPSessionReplayManager.sharedInstance.deinitializeInstance()

        // Clean up test hooks and mocks
        MPSessionReplayManager.sharedInstance.testOverride_settingsService = nil
        mockNetwork = nil
        settingsService = nil

        super.tearDown()
    }

    // MARK: - Strict Mode Tests

    func testInitializeWithStrictModeSuccess() {
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
            autoStartRecording: false,
            recordingSessionsPercent: 100,
            remoteSettingsMode: .strict,
            enableSessionReplayOniOS26AndLater: true
        )

        let expectation = self.expectation(description: "Initialization completes")
        var initResult: Result<MPSessionReplayInstance?, Error>?

        MPSessionReplay.initialize(token: testToken, distinctId: testDistinctId, config: config) { result in
            initResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0, handler: nil)

        switch initResult {
            case .success(let instance):
                XCTAssertNotNil(instance, "Instance should be created in strict mode with successful fetch")
                XCTAssertEqual(instance?.config.recordingSessionsPercent, 75.0, "Remote config should be applied")
            case .failure(let error):
                XCTFail("Initialization should succeed but failed with: \(error)")
            case .none:
                XCTFail("Result should not be nil")
        }
    }

    func testInitializeWithStrictMode_FailsWhenNoRemoteConfig() {
        // Configure mock to return JSON response with error in sdk_config
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {"is_enabled": true},
                "sdk_config": {
                    "error": "Remote config not found"
                }
            }
            """

        let config = MPSessionReplayConfig(
            autoStartRecording: false,
            recordingSessionsPercent: 100,
            remoteSettingsMode: .strict,
            enableSessionReplayOniOS26AndLater: true
        )

        let expectation = self.expectation(description: "Initialization fails")
        var initResult: Result<MPSessionReplayInstance?, Error>?

        MPSessionReplay.initialize(token: testToken, distinctId: testDistinctId, config: config) { result in
            initResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0, handler: nil)

        switch initResult {
            case .success:
                XCTFail("Initialization should fail in strict mode when remote fetch does not return SDK config")
            case .failure(let error):
                if case MPSessionReplayError.custom(let message) = error {
                    XCTAssertTrue(
                        message.contains("Strict mode requires remote settings"),
                        "Error message should indicate strict mode failure")
                } else {
                    XCTFail("Error should be custom error with strict mode message, got: \(error)")
                }
            case .none:
                XCTFail("Result should not be nil")
        }

        XCTAssertNil(MPSessionReplay.getInstance(), "Instance should not be created in strict mode on failure")
    }

    func testInitializeWithStrictModeFailure() {
        // Simulate network failure
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        mockNetwork.sendRawRequestStub = { _ in
            return .failure(error)
        }

        let config = MPSessionReplayConfig(
            autoStartRecording: false,
            recordingSessionsPercent: 100,
            remoteSettingsMode: .strict,
            enableSessionReplayOniOS26AndLater: true
        )

        let expectation = self.expectation(description: "Initialization fails")
        var initResult: Result<MPSessionReplayInstance?, Error>?

        MPSessionReplay.initialize(token: testToken, distinctId: testDistinctId, config: config) { result in
            initResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0, handler: nil)

        switch initResult {
            case .success:
                XCTFail("Initialization should fail in strict mode when remote fetch fails")
            case .failure(let error):
                if case MPSessionReplayError.custom(let message) = error {
                    XCTAssertTrue(
                        message.contains("Strict mode requires remote settings"),
                        "Error message should indicate strict mode failure")
                } else {
                    XCTFail("Error should be custom error with strict mode message, got: \(error)")
                }
            case .none:
                XCTFail("Result should not be nil")
        }

        XCTAssertNil(MPSessionReplay.getInstance(), "Instance should not be created in strict mode on failure")
    }

    func testInitializeWithStrictModeRecordingDisabled() {
        // Configure mock to return JSON response with recording disabled (remote enablement switch)
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {
                    "is_enabled": false,
                    "error": "Recording disabled for this project"
                },
                "sdk_config": {
                    "config": {"record_sessions_percent": 75}
                }
            }
            """

        let config = MPSessionReplayConfig(
            autoStartRecording: false,
            recordingSessionsPercent: 100,
            remoteSettingsMode: .strict,
            enableSessionReplayOniOS26AndLater: true
        )

        let expectation = self.expectation(description: "Initialization fails due to remote enablement switch")
        var initResult: Result<MPSessionReplayInstance?, Error>?

        MPSessionReplay.initialize(token: testToken, distinctId: testDistinctId, config: config) { result in
            initResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0, handler: nil)

        switch initResult {
            case .success:
                XCTFail("Initialization should fail when recording is disabled remotely")
            case .failure(let error):
                if case MPSessionReplayError.disabledByRemoteSetting(let message) = error {
                    XCTAssertEqual(
                        message, "Recording disabled for this project", "Error message should match remote error")
                } else {
                    XCTFail("Error should be disabledByRemoteSetting, got: \(error)")
                }
            case .none:
                XCTFail("Result should not be nil")
        }

        XCTAssertNil(MPSessionReplay.getInstance(), "Instance should not be created when recording is disabled")
    }

    // MARK: - Fallback Mode Tests

    func testInitializeWithFallbackModeSuccess() {
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

        let config = MPSessionReplayConfig(
            autoStartRecording: false,
            recordingSessionsPercent: 100,
            remoteSettingsMode: .fallback,
            enableSessionReplayOniOS26AndLater: true
        )

        let expectation = self.expectation(description: "Initialization completes")
        var initResult: Result<MPSessionReplayInstance?, Error>?

        MPSessionReplay.initialize(token: testToken, distinctId: testDistinctId, config: config) { result in
            initResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0, handler: nil)

        switch initResult {
            case .success(let instance):
                XCTAssertNotNil(instance, "Instance should be created in fallback mode")
                XCTAssertEqual(instance?.config.recordingSessionsPercent, 60.0, "Remote config should be applied")
            case .failure(let error):
                XCTFail("Initialization should succeed but failed with: \(error)")
            case .none:
                XCTFail("Result should not be nil")
        }
    }

    func testInitializeWithFallbackModeFailureWithCache() {
        // First, initialize successfully to populate the cache
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {"is_enabled": true},
                "sdk_config": {
                    "config": {"record_sessions_percent": 40}
                }
            }
            """

        let initialConfig = MPSessionReplayConfig(
            autoStartRecording: false,
            recordingSessionsPercent: 100,
            remoteSettingsMode: .fallback,
            enableSessionReplayOniOS26AndLater: true
        )

        let firstExpectation = self.expectation(description: "First initialization completes")

        MPSessionReplay.initialize(token: testToken, distinctId: testDistinctId, config: initialConfig) { result in
            firstExpectation.fulfill()
        }

        waitForExpectations(timeout: 1.0, handler: nil)

        // Now simulate a network failure - SettingsService will use cached settings
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])

        mockNetwork.reset()
        mockNetwork.sendRawRequestStub = { _ in
            return .failure(error)
        }

        let config = MPSessionReplayConfig(
            autoStartRecording: false,
            recordingSessionsPercent: 100,
            remoteSettingsMode: .fallback,
            enableSessionReplayOniOS26AndLater: true
        )

        let expectation = self.expectation(description: "Second initialization with cache")
        var initResult: Result<MPSessionReplayInstance?, Error>?

        MPSessionReplay.initialize(token: testToken, distinctId: testDistinctId, config: config) { result in
            initResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0, handler: nil)

        switch initResult {
            case .success(let instance):
                XCTAssertNotNil(instance, "Instance should be created using cached config")
                XCTAssertEqual(instance?.config.recordingSessionsPercent, 40.0, "Cached remote config should be used")
            case .failure(let error):
                XCTFail("Initialization should succeed with cache but failed with: \(error)")
            case .none:
                XCTFail("Result should not be nil")
        }
    }

    func testInitializeWithFallbackModeFailureWithoutCache() {
        // Simulate network failure
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        mockNetwork.sendRawRequestStub = { _ in
            return .failure(error)
        }

        let config = MPSessionReplayConfig(
            autoStartRecording: false,
            recordingSessionsPercent: 100,
            remoteSettingsMode: .fallback,
            enableSessionReplayOniOS26AndLater: true
        )

        let expectation = self.expectation(description: "Initialization with fallback to original config")
        var initResult: Result<MPSessionReplayInstance?, Error>?

        MPSessionReplay.initialize(token: testToken, distinctId: testDistinctId, config: config) { result in
            initResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0, handler: nil)

        switch initResult {
            case .success(let instance):
                XCTAssertNotNil(instance, "Instance should be created with original config")
                XCTAssertEqual(
                    instance?.config.recordingSessionsPercent, 100, "Original config should be used when no cache")
            case .failure(let error):
                XCTFail("Initialization should succeed with original config but failed with: \(error)")
            case .none:
                XCTFail("Result should not be nil")
        }
    }

    // MARK: - Disabled Mode Tests

    func testInitializeWithDisabledModeSuccess() {
        // In disabled mode, remote config is fetched but NOT merged - only used for remote enablement switch check
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
            autoStartRecording: false,
            recordingSessionsPercent: 100,
            remoteSettingsMode: .disabled,
            enableSessionReplayOniOS26AndLater: true
        )

        let expectation = self.expectation(description: "Initialization completes")
        var initResult: Result<MPSessionReplayInstance?, Error>?

        MPSessionReplay.initialize(token: testToken, distinctId: testDistinctId, config: config) { result in
            initResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0, handler: nil)

        switch initResult {
            case .success(let instance):
                XCTAssertNotNil(instance, "Instance should be created in disabled mode")
                XCTAssertEqual(
                    instance?.config.recordingSessionsPercent, 100,
                    "Original config should be used (not merged) in disabled mode")
            case .failure(let error):
                XCTFail("Initialization should succeed but failed with: \(error)")
            case .none:
                XCTFail("Result should not be nil")
        }
    }

    func testInitializeWithDisabledModeRecordingDisabled() {
        // Even in disabled mode, remote enablement switch (recording disabled) should prevent initialization
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {
                    "is_enabled": false,
                    "error": "Recording disabled via remote enablement switch"
                },
                "sdk_config": {
                    "config": {"record_sessions_percent": 50}
                }
            }
            """

        let config = MPSessionReplayConfig(
            autoStartRecording: false,
            recordingSessionsPercent: 100,
            remoteSettingsMode: .disabled,
            enableSessionReplayOniOS26AndLater: true
        )

        let expectation = self.expectation(description: "Initialization fails due to remote enablement switch")
        var initResult: Result<MPSessionReplayInstance?, Error>?

        MPSessionReplay.initialize(token: testToken, distinctId: testDistinctId, config: config) { result in
            initResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0, handler: nil)

        switch initResult {
            case .success:
                XCTFail("Initialization should fail when recording is disabled even in disabled mode")
            case .failure(let error):
                if case MPSessionReplayError.disabledByRemoteSetting(let message) = error {
                    XCTAssertEqual(message, "Recording disabled via remote enablement switch", "Error message should match")
                } else {
                    XCTFail("Error should be disabledByRemoteSetting, got: \(error)")
                }
            case .none:
                XCTFail("Result should not be nil")
        }
    }

    // MARK: - Event Trigger Integration Tests

    func testInitializeWithEventTriggers_BasicScenarios() {
        // Simple real-world event triggers covering common use cases:
        // 1. High-value purchases (amount > $100)
        // 2. Premium tier users
        // 3. Gmail signups
        // 4. Active trial users
        mockNetwork.responseJson = """
            {
                "code": 200,
                "status": "OK",
                "recording": {"is_enabled": true},
                "sdk_config": {
                    "config": {
                        "record_sessions_percent": 50,
                        "recording_event_triggers": {
                            "purchase_completed": {
                                "percentage": 100,
                                "property_filters": {
                                    ">": [{"var": "amount"}, 100]
                                }
                            },
                            "premium_feature_view": {
                                "percentage": 75,
                                "property_filters": {
                                    "===": [{"var": "tier"}, "premium"]
                                }
                            },
                            "signup": {
                                "percentage": 50,
                                "property_filters": {
                                    "in": ["gmail", {"var": "email"}]
                                }
                            },
                            "trial_action": {
                                "percentage": 80,
                                "property_filters": {
                                    "<": [{"var": "trial_days"}, 30]
                                }
                            }
                        }
                    }
                }
            }
            """

        let config = MPSessionReplayConfig(
            autoStartRecording: false,
            recordingSessionsPercent: 100,
            remoteSettingsMode: .fallback,
            enableSessionReplayOniOS26AndLater: true
        )

        let expectation = self.expectation(description: "Initialization with basic event triggers")
        var initResult: Result<MPSessionReplayInstance?, Error>?

        MPSessionReplay.initialize(token: testToken, distinctId: testDistinctId, config: config) { result in
            initResult = result
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0, handler: nil)

        switch initResult {
            case .success(let instance):
                XCTAssertNotNil(instance, "Instance should be created with event triggers")

                // Verify config was merged
                XCTAssertEqual(
                    instance?.config.recordingSessionsPercent, 50.0, "Remote recordingSessionsPercent should be applied"
                )

                // Verify event triggers were cached
                let cached = settingsService.getCachedSettingsState(token: testToken)
                let triggers = cached.sdkConfig?.config?.recordingEventTriggers

                XCTAssertNotNil(triggers, "Event triggers should be cached")
                XCTAssertEqual(triggers?.count, 4, "Should have 4 event triggers")

                // Verify purchase_completed trigger (numeric comparison)
                XCTAssertEqual(triggers?["purchase_completed"]?.percentage, 100)
                XCTAssertNotNil(triggers?["purchase_completed"]?.propertyFilters)
                XCTAssertTrue(triggers?["purchase_completed"]?.propertyFilters?.keys.contains(">") ?? false)

                // Verify premium_feature_view trigger (string equality)
                XCTAssertEqual(triggers?["premium_feature_view"]?.percentage, 75)
                XCTAssertNotNil(triggers?["premium_feature_view"]?.propertyFilters)
                XCTAssertTrue(triggers?["premium_feature_view"]?.propertyFilters?.keys.contains("===") ?? false)

                // Verify signup trigger (substring matching)
                XCTAssertEqual(triggers?["signup"]?.percentage, 50)
                XCTAssertNotNil(triggers?["signup"]?.propertyFilters)
                XCTAssertTrue(triggers?["signup"]?.propertyFilters?.keys.contains("in") ?? false)

                // Verify trial_action trigger (less than comparison)
                XCTAssertEqual(triggers?["trial_action"]?.percentage, 80)
                XCTAssertNotNil(triggers?["trial_action"]?.propertyFilters)

            case .failure(let error):
                XCTFail("Initialization should succeed with event triggers but failed with: \(error)")
            case .none:
                XCTFail("Result should not be nil")
        }
    }
}
