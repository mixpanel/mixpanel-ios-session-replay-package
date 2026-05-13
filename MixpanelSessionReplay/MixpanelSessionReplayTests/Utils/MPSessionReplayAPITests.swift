//
//  MPSessionReplayAPITests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2025 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

final class MPSessionReplayAPITests: XCTestCase {

    // MARK: - Data Residency Constants Tests

    func testUSDataResidencyConstant() {
        XCTAssertEqual(
            MPSessionReplayAPI.usDataResidency,
            "https://api-js.mixpanel.com",
            "US data residency URL should be correct"
        )
    }

    func testEUDataResidencyConstant() {
        XCTAssertEqual(
            MPSessionReplayAPI.euDataResidency,
            "https://api-eu.mixpanel.com",
            "EU data residency URL should be correct"
        )
    }

    func testIndiaDataResidencyConstant() {
        XCTAssertEqual(
            MPSessionReplayAPI.inDataResidency,
            "https://api-in.mixpanel.com",
            "India data residency URL should be correct"
        )
    }

    // MARK: - Record Endpoint Tests

    func testRecordEndpointForUSDataResidency() {
        let endpoint = MPSessionReplayAPI.recordEndpoint(for: MPSessionReplayAPI.usDataResidency)
        XCTAssertEqual(
            endpoint,
            "https://api-js.mixpanel.com/record",
            "US record endpoint should append /record path"
        )
    }

    func testRecordEndpointForEUDataResidency() {
        let endpoint = MPSessionReplayAPI.recordEndpoint(for: MPSessionReplayAPI.euDataResidency)
        XCTAssertEqual(
            endpoint,
            "https://api-eu.mixpanel.com/record",
            "EU record endpoint should append /record path"
        )
    }

    func testRecordEndpointForIndiaDataResidency() {
        let endpoint = MPSessionReplayAPI.recordEndpoint(for: MPSessionReplayAPI.inDataResidency)
        XCTAssertEqual(
            endpoint,
            "https://api-in.mixpanel.com/record",
            "India record endpoint should append /record path"
        )
    }

    func testRecordEndpointForCustomURL() {
        let customURL = "https://custom.example.com"
        let endpoint = MPSessionReplayAPI.recordEndpoint(for: customURL)
        XCTAssertEqual(
            endpoint,
            "https://custom.example.com/record",
            "Custom record endpoint should append /record path"
        )
    }

    func testRecordEndpointDefaultParameter() {
        let endpoint = MPSessionReplayAPI.recordEndpoint()
        XCTAssertEqual(
            endpoint,
            "https://api-js.mixpanel.com/record",
            "Record endpoint should default to US data residency"
        )
    }

    // MARK: - Settings Endpoint Tests

    func testSettingsEndpointIsConstant() {
        XCTAssertEqual(
            MPSessionReplayAPI.settingsEndpoint,
            "https://api.mixpanel.com/settings",
            "Settings endpoint should be constant across all data residencies"
        )
    }

    // MARK: - URL Format Validation

    func testDataResidencyURLsDoNotContainPaths() {
        XCTAssertFalse(
            MPSessionReplayAPI.usDataResidency.hasSuffix("/"),
            "US data residency URL should not end with slash"
        )
        XCTAssertFalse(
            MPSessionReplayAPI.usDataResidency.contains("/record"),
            "US data residency URL should not contain /record path"
        )

        XCTAssertFalse(
            MPSessionReplayAPI.euDataResidency.hasSuffix("/"),
            "EU data residency URL should not end with slash"
        )
        XCTAssertFalse(
            MPSessionReplayAPI.euDataResidency.contains("/record"),
            "EU data residency URL should not contain /record path"
        )

        XCTAssertFalse(
            MPSessionReplayAPI.inDataResidency.hasSuffix("/"),
            "India data residency URL should not end with slash"
        )
        XCTAssertFalse(
            MPSessionReplayAPI.inDataResidency.contains("/record"),
            "India data residency URL should not contain /record path"
        )
    }

    func testAllDataResidencyURLsAreHTTPS() {
        XCTAssertTrue(
            MPSessionReplayAPI.usDataResidency.hasPrefix("https://"),
            "US data residency should use HTTPS"
        )
        XCTAssertTrue(
            MPSessionReplayAPI.euDataResidency.hasPrefix("https://"),
            "EU data residency should use HTTPS"
        )
        XCTAssertTrue(
            MPSessionReplayAPI.inDataResidency.hasPrefix("https://"),
            "India data residency should use HTTPS"
        )
        XCTAssertTrue(
            MPSessionReplayAPI.settingsEndpoint.hasPrefix("https://"),
            "Settings endpoint should use HTTPS"
        )
    }
}
