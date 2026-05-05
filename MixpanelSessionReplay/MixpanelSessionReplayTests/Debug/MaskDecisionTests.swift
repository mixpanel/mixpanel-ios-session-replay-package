//
//  MaskDecisionTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

class MaskDecisionTests: XCTestCase {

    func testMaskDecisionOrdering() {
        // Verify priority ordering: unmask < auto < mask < textInput
        XCTAssertTrue(MaskDecision.unmask < MaskDecision.auto, "unmask should have lower priority than auto")
        XCTAssertTrue(MaskDecision.auto < MaskDecision.mask, "auto should have lower priority than mask")
        XCTAssertTrue(MaskDecision.mask < MaskDecision.textInput, "mask should have lower priority than textInput")
    }

    func testMaskDecisionRawValues() {
        XCTAssertEqual(MaskDecision.unmask.rawValue, 0, "unmask should have raw value 0")
        XCTAssertEqual(MaskDecision.auto.rawValue, 1, "auto should have raw value 1")
        XCTAssertEqual(MaskDecision.mask.rawValue, 2, "mask should have raw value 2")
        XCTAssertEqual(MaskDecision.textInput.rawValue, 3, "textInput should have raw value 3")
    }

    func testMaskDecisionComparison() {
        let decisions: [MaskDecision] = [.textInput, .unmask, .mask, .auto]
        let sorted = decisions.sorted()

        XCTAssertEqual(sorted, [.unmask, .auto, .mask, .textInput], "Decisions should sort by priority")
    }

    func testMaskDecisionEquality() {
        XCTAssertEqual(MaskDecision.unmask, MaskDecision.unmask)
        XCTAssertEqual(MaskDecision.auto, MaskDecision.auto)
        XCTAssertEqual(MaskDecision.mask, MaskDecision.mask)
        XCTAssertEqual(MaskDecision.textInput, MaskDecision.textInput)

        XCTAssertNotEqual(MaskDecision.unmask, MaskDecision.auto)
        XCTAssertNotEqual(MaskDecision.auto, MaskDecision.mask)
        XCTAssertNotEqual(MaskDecision.mask, MaskDecision.textInput)
    }

    func testMaskDecisionInDictionary() {
        let rect1 = HashableRect(CGRect(x: 0, y: 0, width: 50, height: 50))
        let rect2 = HashableRect(CGRect(x: 50, y: 50, width: 50, height: 50))

        var decisions: [HashableRect: MaskDecision] = [:]
        decisions[rect1] = .mask
        decisions[rect2] = .auto

        XCTAssertEqual(decisions[rect1], .mask)
        XCTAssertEqual(decisions[rect2], .auto)
    }

    func testPriorityOverride() {
        // Simulates the addOrUpdate behavior where higher priority wins
        let rect = HashableRect(CGRect(x: 0, y: 0, width: 50, height: 50))
        var decisions: [HashableRect: MaskDecision] = [:]

        // Add auto first
        decisions[rect] = .auto
        XCTAssertEqual(decisions[rect], .auto)

        // Override with higher priority mask
        if let existing = decisions[rect], MaskDecision.mask > existing {
            decisions[rect] = .mask
        }
        XCTAssertEqual(decisions[rect], .mask)

        // Try to override with lower priority auto (should not change)
        if let existing = decisions[rect], MaskDecision.auto > existing {
            decisions[rect] = .auto
        }
        XCTAssertEqual(decisions[rect], .mask, "Lower priority should not override")

        // Override with highest priority textInput
        if let existing = decisions[rect], MaskDecision.textInput > existing {
            decisions[rect] = .textInput
        }
        XCTAssertEqual(decisions[rect], .textInput)
    }
}
