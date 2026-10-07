//
//  SessionReplayCompatibilityCheckerTests.swift
//  MixpanelSessionReplayTests
//
//  Created by Ketan on 19/12/25.
//  Copyright © 2025 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

final class SessionReplayCompatibilityCheckerTests: XCTestCase {

    // MARK: - Helper

    private func makeChecker(
        xcodeVersion: String? = "1640",
        isiOS26OrLater: Bool = false
    ) -> SessionReplayCompatibilityChecker {
        SessionReplayCompatibilityChecker(
            xcodeVersionProvider: { xcodeVersion },
            isiOS26OrLater: { isiOS26OrLater }
        )
    }

    // MARK: - Status Description Tests

    func testCompatibleStatusDescription() {
        XCTAssertEqual(
            SessionReplayCompatibilityStatus.compatible.description,
            "Session replay is compatible and can be enabled"
        )
    }

    func testIncompatibleStatusDescription() {
        XCTAssertEqual(
            SessionReplayCompatibilityStatus.incompatible.description,
            "Session replay is incompatible as app is built with Xcode 26+ and running iOS 26+ device"
        )
    }

    func testUnclearStatusDescription() {
        XCTAssertEqual(
            SessionReplayCompatibilityStatus.unclear.description,
            "Unable to determine session replay compatibility"
        )
    }

    // MARK: - Xcode Version Compatibility Tests

    func testXcodeBelow2600_ReturnsCompatible() {
        let checker = makeChecker(xcodeVersion: "1640", isiOS26OrLater: true)
        XCTAssertEqual(checker.isCompatible(), .compatible)
    }

    func testXcode2599_ReturnsCompatible() {
        let checker = makeChecker(xcodeVersion: "2599", isiOS26OrLater: true)
        XCTAssertEqual(checker.isCompatible(), .compatible)
    }

    func testXcode2600_WithiOS26_ReturnsIncompatible() {
        let checker = makeChecker(xcodeVersion: "2600", isiOS26OrLater: true)
        XCTAssertEqual(checker.isCompatible(), .incompatible)
    }

    func testXcodeAbove2600_WithiOS26_ReturnsIncompatible() {
        let checker = makeChecker(xcodeVersion: "2610", isiOS26OrLater: true)
        XCTAssertEqual(checker.isCompatible(), .incompatible)
    }

    func testXcodeVersionNil_WithiOSBelow26_ReturnsCompatible() {
        let checker = makeChecker(xcodeVersion: nil, isiOS26OrLater: false)
        XCTAssertEqual(checker.isCompatible(), .compatible)
    }

    func testXcodeVersionNil_WithiOS26_ReturnsIncompatible() {
        let checker = makeChecker(xcodeVersion: nil, isiOS26OrLater: true)
        XCTAssertEqual(checker.isCompatible(), .incompatible)
    }

    func testXcodeVersionInvalidString_WithiOSBelow26_ReturnsCompatible() {
        let checker = makeChecker(xcodeVersion: "invalid", isiOS26OrLater: false)
        XCTAssertEqual(checker.isCompatible(), .compatible)
    }

    func testXcodeVersionInvalidString_WithiOS26_ReturnsIncompatible() {
        let checker = makeChecker(xcodeVersion: "invalid", isiOS26OrLater: true)
        XCTAssertEqual(checker.isCompatible(), .incompatible)
    }

    func testXcodeVersionEmpty_WithiOSBelow26_ReturnsCompatible() {
        let checker = makeChecker(xcodeVersion: "", isiOS26OrLater: false)
        XCTAssertEqual(checker.isCompatible(), .compatible)
    }

    func testXcodeVersionWithWhitespace_WithiOS26_ReturnsIncompatible() {
        // Int(" 1640 ") returns nil, so Xcode status is .unclear
        let checker = makeChecker(xcodeVersion: " 1640 ", isiOS26OrLater: true)
        XCTAssertEqual(checker.isCompatible(), .incompatible)
    }

    // MARK: - iOS Version Compatibility Tests

    func testIOSBelow26_ReturnsCompatible() {
        let checker = makeChecker(xcodeVersion: "2600", isiOS26OrLater: false)
        XCTAssertEqual(checker.isCompatible(), .compatible)
    }

    func testiOS26OrLater_WithXcodeBelow26_ReturnsCompatible() {
        let checker = makeChecker(xcodeVersion: "1640", isiOS26OrLater: true)
        XCTAssertEqual(checker.isCompatible(), .compatible)
    }

    // MARK: - Combined Compatibility Matrix Tests

    func testBothCompatible_ReturnsCompatible() {
        // Xcode < 26, iOS < 26
        let checker = makeChecker(xcodeVersion: "1640", isiOS26OrLater: false)
        XCTAssertEqual(checker.isCompatible(), .compatible)
    }

    func testXcodeCompatible_iOSIncompatible_ReturnsCompatible() {
        // Xcode < 26, iOS 26+
        let checker = makeChecker(xcodeVersion: "1640", isiOS26OrLater: true)
        XCTAssertEqual(checker.isCompatible(), .compatible)
    }

    func testXcodeIncompatible_iOSCompatible_ReturnsCompatible() {
        // Xcode 26+, iOS < 26
        let checker = makeChecker(xcodeVersion: "2600", isiOS26OrLater: false)
        XCTAssertEqual(checker.isCompatible(), .compatible)
    }

    func testBothIncompatible_ReturnsIncompatible() {
        // Xcode 26+, iOS 26+ (Liquid Glass scenario)
        let checker = makeChecker(xcodeVersion: "2600", isiOS26OrLater: true)
        XCTAssertEqual(checker.isCompatible(), .incompatible)
    }

    func testXcodeUnclear_iOSCompatible_ReturnsCompatible() {
        // Unknown Xcode, iOS < 26
        let checker = makeChecker(xcodeVersion: nil, isiOS26OrLater: false)
        XCTAssertEqual(checker.isCompatible(), .compatible)
    }

    func testXcodeUnclear_iOSIncompatible_ReturnsIncompatible() {
        // Unknown Xcode, iOS 26+
        let checker = makeChecker(xcodeVersion: nil, isiOS26OrLater: true)
        XCTAssertEqual(checker.isCompatible(), .incompatible)
    }

    // MARK: - Static Method Tests

    func testStaticIsCompatible_ReturnsValidStatus() {
        let status = SessionReplayCompatibilityChecker.isCompatible()
        XCTAssertTrue(
            status == .compatible || status == .incompatible,
            "Static isCompatible() should return compatible or incompatible"
        )
    }

    // MARK: - Status Equality Tests

    func testStatusEquality() {
        XCTAssertEqual(SessionReplayCompatibilityStatus.compatible, .compatible)
        XCTAssertEqual(SessionReplayCompatibilityStatus.incompatible, .incompatible)
        XCTAssertEqual(SessionReplayCompatibilityStatus.unclear, .unclear)
    }

    func testStatusInequality() {
        XCTAssertNotEqual(SessionReplayCompatibilityStatus.compatible, .incompatible)
        XCTAssertNotEqual(SessionReplayCompatibilityStatus.compatible, .unclear)
        XCTAssertNotEqual(SessionReplayCompatibilityStatus.incompatible, .unclear)
    }
}
