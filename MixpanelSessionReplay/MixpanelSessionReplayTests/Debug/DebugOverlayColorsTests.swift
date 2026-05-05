//
//  DebugOverlayColorsTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

class DebugOverlayColorsTests: XCTestCase {

    func testDefaultInitialization() {
        let colors = DebugOverlayColors()

        XCTAssertNotNil(colors.maskColor, "Default maskColor should not be nil")
        XCTAssertNotNil(colors.autoMaskColor, "Default autoMaskColor should not be nil")
        XCTAssertNotNil(colors.unmaskColor, "Default unmaskColor should not be nil")
        XCTAssertEqual(colors.alpha, 0.5, "Default alpha should be 0.5")
    }

    func testCustomInitialization() {
        let customMaskColor = UIColor.blue
        let customAutoMaskColor = UIColor.yellow
        let customUnmaskColor = UIColor.purple
        let customAlpha: Float = 0.8

        let colors = DebugOverlayColors(
            maskColor: customMaskColor,
            autoMaskColor: customAutoMaskColor,
            unmaskColor: customUnmaskColor,
            alpha: customAlpha
        )

        XCTAssertEqual(colors.maskColor, customMaskColor)
        XCTAssertEqual(colors.autoMaskColor, customAutoMaskColor)
        XCTAssertEqual(colors.unmaskColor, customUnmaskColor)
        XCTAssertEqual(colors.alpha, customAlpha)
    }

    func testNilColors() {
        let colors = DebugOverlayColors(
            maskColor: nil,
            autoMaskColor: nil,
            unmaskColor: nil,
            alpha: 0.3
        )

        XCTAssertNil(colors.maskColor, "maskColor should be nil when set to nil")
        XCTAssertNil(colors.autoMaskColor, "autoMaskColor should be nil when set to nil")
        XCTAssertNil(colors.unmaskColor, "unmaskColor should be nil when set to nil")
        XCTAssertEqual(colors.alpha, 0.3)
    }

    func testEncodingAndDecoding() throws {
        let original = DebugOverlayColors(
            maskColor: .red,
            autoMaskColor: .orange,
            unmaskColor: .green,
            alpha: 0.6
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DebugOverlayColors.self, from: data)

        XCTAssertEqual(decoded.alpha, original.alpha, "Alpha should match after encoding/decoding")
        XCTAssertNotNil(decoded.maskColor, "maskColor should not be nil after decoding")
        XCTAssertNotNil(decoded.autoMaskColor, "autoMaskColor should not be nil after decoding")
        XCTAssertNotNil(decoded.unmaskColor, "unmaskColor should not be nil after decoding")
    }

    func testEncodingNilColors() throws {
        let original = DebugOverlayColors(
            maskColor: nil,
            autoMaskColor: .orange,
            unmaskColor: nil,
            alpha: 0.7
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DebugOverlayColors.self, from: data)

        XCTAssertNil(decoded.maskColor, "Nil maskColor should remain nil after encoding/decoding")
        XCTAssertNotNil(decoded.autoMaskColor, "Non-nil autoMaskColor should be preserved")
        XCTAssertNil(decoded.unmaskColor, "Nil unmaskColor should remain nil after encoding/decoding")
        XCTAssertEqual(decoded.alpha, 0.7)
    }

    func testColorRoundTrip() throws {
        // Test various color values to ensure encoding/decoding preserves them
        let testCases: [(UIColor, String)] = [
            (.red, "red"),
            (.green, "green"),
            (.blue, "blue"),
            (.white, "white"),
            (.black, "black"),
            (.clear, "clear"),
            (UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0), "gray"),
            (UIColor(red: 0.25, green: 0.75, blue: 0.5, alpha: 0.8), "custom"),
        ]

        for (color, label) in testCases {
            let original = DebugOverlayColors(maskColor: color, autoMaskColor: nil, unmaskColor: nil, alpha: 0.5)

            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(DebugOverlayColors.self, from: data)

            XCTAssertNotNil(decoded.maskColor, "\(label) color should decode successfully")

            // Compare color components (allowing for slight precision loss from 8-bit encoding)
            if let decodedColor = decoded.maskColor {
                var r1: CGFloat = 0
                var g1: CGFloat = 0
                var b1: CGFloat = 0
                var a1: CGFloat = 0
                var r2: CGFloat = 0
                var g2: CGFloat = 0
                var b2: CGFloat = 0
                var a2: CGFloat = 0

                color.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
                decodedColor.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

                // Allow for ~1/255 tolerance due to 8-bit encoding
                let tolerance: CGFloat = 1.0 / 255.0 + 0.01
                XCTAssertEqual(r1, r2, accuracy: tolerance, "\(label): red component should match")
                XCTAssertEqual(g1, g2, accuracy: tolerance, "\(label): green component should match")
                XCTAssertEqual(b1, b2, accuracy: tolerance, "\(label): blue component should match")
                XCTAssertEqual(a1, a2, accuracy: tolerance, "\(label): alpha component should match")
            }
        }
    }

    func testAlphaBoundaries() throws {
        let testCases: [Float] = [0.0, 0.1, 0.5, 0.9, 1.0]

        for alpha in testCases {
            let colors = DebugOverlayColors(alpha: alpha)

            let data = try JSONEncoder().encode(colors)
            let decoded = try JSONDecoder().decode(DebugOverlayColors.self, from: data)

            XCTAssertEqual(decoded.alpha, alpha, accuracy: 0.001, "Alpha \(alpha) should match after encoding/decoding")
        }
    }
}
