//
//  DebugOptionsTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

class DebugOptionsTests: XCTestCase {

    func testDefaultInitialization() {
        let options = DebugOptions()

        XCTAssertNotNil(options.overlayColors, "Default overlayColors should not be nil")
    }

    func testInitializationWithNilColors() {
        let options = DebugOptions(overlayColors: nil)

        XCTAssertNil(options.overlayColors, "overlayColors should be nil when initialized with nil")
    }

    func testInitializationWithCustomColors() {
        let customColors = DebugOverlayColors(
            maskColor: .blue,
            autoMaskColor: .yellow,
            unmaskColor: .purple,
            alpha: 0.8
        )

        let options = DebugOptions(overlayColors: customColors)

        XCTAssertNotNil(options.overlayColors, "overlayColors should not be nil")
        XCTAssertEqual(options.overlayColors?.alpha, 0.8, "Custom alpha should be preserved")
    }

    func testEncodingAndDecoding() throws {
        let original = DebugOptions(
            overlayColors: DebugOverlayColors(
                maskColor: .red,
                autoMaskColor: .orange,
                unmaskColor: .green,
                alpha: 0.6
            ))

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DebugOptions.self, from: data)

        XCTAssertNotNil(decoded.overlayColors, "overlayColors should be preserved after encoding/decoding")
        XCTAssertEqual(decoded.overlayColors?.alpha, 0.6, "Alpha should match after encoding/decoding")
    }

    func testEncodingWithNilColors() throws {
        let original = DebugOptions(overlayColors: nil)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DebugOptions.self, from: data)

        XCTAssertNil(decoded.overlayColors, "Nil overlayColors should remain nil after encoding/decoding")
    }

    func testIntegrationWithMPSessionReplayConfig() {
        let debugOptions = DebugOptions(overlayColors: DebugOverlayColors())
        let config = MPSessionReplayConfig(debugOptions: debugOptions)

        XCTAssertNotNil(config.debugOptions, "Config should preserve debugOptions")
        XCTAssertNotNil(config.debugOptions?.overlayColors, "Config should preserve overlayColors")
    }

    func testConfigWithoutDebugOptions() {
        let config = MPSessionReplayConfig()

        XCTAssertNil(config.debugOptions, "Default config should have nil debugOptions")
    }
}
