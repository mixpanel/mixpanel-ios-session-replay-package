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
            DataResidency.us,
            "https://api.mixpanel.com",
            "US data residency URL should be correct"
        )
    }

    func testEUDataResidencyConstant() {
        XCTAssertEqual(
            DataResidency.eu,
            "https://api-eu.mixpanel.com",
            "EU data residency URL should be correct"
        )
    }

    func testIndiaDataResidencyConstant() {
        XCTAssertEqual(
            DataResidency.in,
            "https://api-in.mixpanel.com",
            "India data residency URL should be correct"
        )
    }

    // MARK: - Record Endpoint Tests

    func testRecordEndpointForUSDataResidency() {
        let endpoint = MPSessionReplayAPI.recordEndpoint(for: DataResidency.us)
        XCTAssertEqual(
            endpoint,
            "https://api.mixpanel.com/record",
            "US record endpoint should append /record path"
        )
    }

    func testRecordEndpointForEUDataResidency() {
        let endpoint = MPSessionReplayAPI.recordEndpoint(for: DataResidency.eu)
        XCTAssertEqual(
            endpoint,
            "https://api-eu.mixpanel.com/record",
            "EU record endpoint should append /record path"
        )
    }

    func testRecordEndpointForIndiaDataResidency() {
        let endpoint = MPSessionReplayAPI.recordEndpoint(for: DataResidency.in)
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
            "https://api.mixpanel.com/record",
            "Record endpoint should default to US data residency"
        )
    }

    // MARK: - Settings Endpoint Tests

    func testSettingsEndpointIsConstant() {
        XCTAssertEqual(
            MPSessionReplayAPI.settingsEndpoint(),
            "https://api.mixpanel.com/settings",
            "Settings endpoint should be constant across all data residencies"
        )
    }

    // MARK: - URL Format Validation

    func testDataResidencyURLsDoNotContainPaths() {
        XCTAssertFalse(
            DataResidency.us.hasSuffix("/"),
            "US data residency URL should not end with slash"
        )
        XCTAssertFalse(
            DataResidency.us.contains("/record"),
            "US data residency URL should not contain /record path"
        )

        XCTAssertFalse(
            DataResidency.eu.hasSuffix("/"),
            "EU data residency URL should not end with slash"
        )
        XCTAssertFalse(
            DataResidency.eu.contains("/record"),
            "EU data residency URL should not contain /record path"
        )

        XCTAssertFalse(
            DataResidency.in.hasSuffix("/"),
            "India data residency URL should not end with slash"
        )
        XCTAssertFalse(
            DataResidency.in.contains("/record"),
            "India data residency URL should not contain /record path"
        )
    }

    func testAllDataResidencyURLsAreHTTPS() {
        XCTAssertTrue(
            DataResidency.us.hasPrefix("https://"),
            "US data residency should use HTTPS"
        )
        XCTAssertTrue(
            DataResidency.eu.hasPrefix("https://"),
            "EU data residency should use HTTPS"
        )
        XCTAssertTrue(
            DataResidency.in.hasPrefix("https://"),
            "India data residency should use HTTPS"
        )
        XCTAssertTrue(
            MPSessionReplayAPI.settingsEndpoint().hasPrefix("https://"),
            "Settings endpoint should use HTTPS"
        )
    }
}
