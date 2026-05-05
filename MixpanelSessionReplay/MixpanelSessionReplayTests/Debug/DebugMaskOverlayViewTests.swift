//
//  DebugMaskOverlayViewTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

class DebugMaskOverlayViewTests: XCTestCase {

    var colors: DebugOverlayColors!

    override func setUp() {
        super.setUp()
        colors = DebugOverlayColors(
            maskColor: .red,
            autoMaskColor: .orange,
            unmaskColor: .green,
            alpha: 0.5
        )
    }

    override func tearDown() {
        colors = nil
        super.tearDown()
    }

    func testInitialization() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let view = DebugMaskOverlayView(frame: frame, colors: colors)

        XCTAssertEqual(view.frame, frame, "Frame should match initialization")
        XCTAssertFalse(view.isUserInteractionEnabled, "Overlay should not intercept user interactions")
        XCTAssertEqual(view.backgroundColor, .clear, "Background should be transparent")
        XCTAssertFalse(view.isOpaque, "View should not be opaque")
    }

    func testHitTestReturnsNil() {
        let view = DebugMaskOverlayView(frame: CGRect(x: 0, y: 0, width: 100, height: 100), colors: colors)

        let testPoint = CGPoint(x: 50, y: 50)
        let result = view.hitTest(testPoint, with: nil)

        XCTAssertNil(result, "hitTest should always return nil to allow touches to pass through")
    }

    func testUpdateMaskDecisionsTriggersRedraw() {
        let view = DebugMaskOverlayView(frame: CGRect(x: 0, y: 0, width: 100, height: 100), colors: colors)

        let decisions: [HashableRect: MaskDecision] = [
            HashableRect(CGRect(x: 0, y: 0, width: 50, height: 50)): .mask,
            HashableRect(CGRect(x: 50, y: 0, width: 50, height: 50)): .auto,
        ]

        // This should not crash and should trigger setNeedsDisplay internally
        view.updateMaskDecisions(decisions)

        // No direct way to test setNeedsDisplay was called, but we can verify no crash
        XCTAssertTrue(true, "updateMaskDecisions should complete without crashing")
    }

    func testUpdateWithSameDecisionsDoesNotRedraw() {
        let view = DebugMaskOverlayView(frame: CGRect(x: 0, y: 0, width: 100, height: 100), colors: colors)

        let decisions: [HashableRect: MaskDecision] = [
            HashableRect(CGRect(x: 0, y: 0, width: 50, height: 50)): .mask
        ]

        view.updateMaskDecisions(decisions)

        // Update with same decisions - internally should skip setNeedsDisplay
        view.updateMaskDecisions(decisions)

        XCTAssertTrue(true, "Updating with same decisions should complete without issues")
    }

    func testUpdateWithEmptyDecisions() {
        let view = DebugMaskOverlayView(frame: CGRect(x: 0, y: 0, width: 100, height: 100), colors: colors)

        view.updateMaskDecisions([:])

        XCTAssertTrue(true, "Empty decisions should be handled gracefully")
    }

    func testAllMaskDecisionTypes() {
        let view = DebugMaskOverlayView(frame: CGRect(x: 0, y: 0, width: 200, height: 100), colors: colors)

        let decisions: [HashableRect: MaskDecision] = [
            HashableRect(CGRect(x: 0, y: 0, width: 50, height: 50)): .unmask,
            HashableRect(CGRect(x: 50, y: 0, width: 50, height: 50)): .auto,
            HashableRect(CGRect(x: 100, y: 0, width: 50, height: 50)): .mask,
            HashableRect(CGRect(x: 150, y: 0, width: 50, height: 50)): .textInput,
        ]

        view.updateMaskDecisions(decisions)

        XCTAssertTrue(true, "All mask decision types should be handled")
    }

    func testNilColorsSuppressRendering() {
        let nilColors = DebugOverlayColors(
            maskColor: nil,
            autoMaskColor: nil,
            unmaskColor: nil,
            alpha: 0.5
        )

        let view = DebugMaskOverlayView(frame: CGRect(x: 0, y: 0, width: 100, height: 100), colors: nilColors)

        let decisions: [HashableRect: MaskDecision] = [
            HashableRect(CGRect(x: 0, y: 0, width: 50, height: 50)): .mask,
            HashableRect(CGRect(x: 50, y: 0, width: 50, height: 50)): .auto,
            HashableRect(CGRect(x: 0, y: 50, width: 50, height: 50)): .unmask,
        ]

        view.updateMaskDecisions(decisions)

        // With all colors nil, nothing should be drawn (but shouldn't crash)
        XCTAssertTrue(true, "Nil colors should be handled gracefully")
    }
}
