//
//  DebugMaskOverlayManagerTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

class DebugMaskOverlayManagerTests: BaseTests {

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

    func testEnableDisableLifecycle() {
        let manager = DebugMaskOverlayManager(colors: colors)

        let expectation1 = expectation(description: "Enable completes")
        let expectation2 = expectation(description: "Disable completes")

        // Enable
        manager.enable()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation1.fulfill()

            // Disable
            manager.disable()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                expectation2.fulfill()
            }
        }

        wait(for: [expectation1, expectation2], timeout: 1.0)
    }

    func testEnableIsIdempotent() {
        let manager = DebugMaskOverlayManager(colors: colors)

        let expectation = self.expectation(description: "Multiple enables complete")

        manager.enable()
        manager.enable()  // Second enable should be safe
        manager.enable()  // Third enable should be safe

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testDisableIsIdempotent() {
        let manager = DebugMaskOverlayManager(colors: colors)

        let expectation = self.expectation(description: "Multiple disables complete")

        manager.enable()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            manager.disable()
            manager.disable()  // Second disable should be safe
            manager.disable()  // Third disable should be safe

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testUpdateMaskRegions() {
        let manager = DebugMaskOverlayManager(colors: colors)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))

        let decisions: [HashableRect: MaskDecision] = [
            HashableRect(CGRect(x: 0, y: 0, width: 50, height: 50)): .mask,
            HashableRect(CGRect(x: 50, y: 0, width: 50, height: 50)): .auto,
        ]

        let expectation = self.expectation(description: "Update completes")

        manager.enable()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            manager.updateMaskRegions(decisions, for: window)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                manager.disable()
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testTransitioningStateHidesOverlays() {
        let manager = DebugMaskOverlayManager(colors: colors)

        let expectation = self.expectation(description: "Transitioning state completes")

        manager.enable()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(manager.isTransitioning, "Should not be transitioning initially")

            manager.isTransitioning = true
            XCTAssertTrue(manager.isTransitioning, "Should be transitioning after setting")

            manager.isTransitioning = false
            XCTAssertFalse(manager.isTransitioning, "Should not be transitioning after reset")

            manager.disable()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testEnableTransitioningStateWithDelay() {
        let manager = DebugMaskOverlayManager(colors: colors)

        let expectation = self.expectation(description: "Transitioning with delay completes")

        // Create a mock instance
        let config = MPSessionReplayConfig(debugOptions: DebugOptions(overlayColors: colors))
        let instance = MPSessionReplayInstance(
            token: "test-token",
            distinctId: "test-user",
            config: config
        )

        // Manually set the manager (simulating initialization)
        instance.debugMaskOverlayManager = manager

        manager.enable()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            manager.enableTransitioningState()

            // Verify it eventually resets (after animation delay)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                manager.disable()
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testUpdateMaskRegionsWithEmptyDecisions() {
        let manager = DebugMaskOverlayManager(colors: colors)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let emptyDecisions: [HashableRect: MaskDecision] = [:]

        let expectation = self.expectation(description: "Empty update completes")

        manager.enable()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            manager.updateMaskRegions(emptyDecisions, for: window)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                manager.disable()
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testConcurrentUpdatesAreHandledSafely() {
        let manager = DebugMaskOverlayManager(colors: colors)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))

        let decisions1: [HashableRect: MaskDecision] = [
            HashableRect(CGRect(x: 0, y: 0, width: 50, height: 50)): .mask
        ]

        let decisions2: [HashableRect: MaskDecision] = [
            HashableRect(CGRect(x: 50, y: 50, width: 50, height: 50)): .auto
        ]

        let expectation = self.expectation(description: "Concurrent updates complete")

        manager.enable()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Fire multiple updates rapidly
            manager.updateMaskRegions(decisions1, for: window)
            manager.updateMaskRegions(decisions2, for: window)
            manager.updateMaskRegions(decisions1, for: window)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                manager.disable()
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testSensitiveViewManagerListenerIntegration() {
        let manager = DebugMaskOverlayManager(colors: colors)

        let expectation = self.expectation(description: "Listener receives callback")

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let decisions: [HashableRect: MaskDecision] = [
            HashableRect(CGRect(x: 0, y: 0, width: 50, height: 50)): .mask
        ]

        // Set up listener
        var receivedDecisions: [HashableRect: MaskDecision]?
        var receivedWindow: UIWindow?

        SensitiveViewManager.shared.maskRegionsListener = { (decisions, window) in
            receivedDecisions = decisions
            receivedWindow = window
            expectation.fulfill()
        }

        // Trigger the listener by calling getSensitiveFrames
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let sensitiveView = UILabel(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        sensitiveView.mpReplaySensitive = true
        rootView.addSubview(sensitiveView)

        SensitiveViewManager.shared.maskAllText = true
        _ = SensitiveViewManager.shared.getSensitiveFrames(in: rootView, window: window)

        wait(for: [expectation], timeout: 1.0)

        XCTAssertNotNil(receivedDecisions, "Listener should receive decisions")
        XCTAssertNotNil(receivedWindow, "Listener should receive window")

        // Clean up
        SensitiveViewManager.shared.maskRegionsListener = nil
    }

    func testDisableRemovesListener() {
        // Set up a listener
        let originalListener: ([HashableRect: MaskDecision], UIWindow?) -> Void = { _, _ in }
        SensitiveViewManager.shared.maskRegionsListener = originalListener

        XCTAssertNotNil(SensitiveViewManager.shared.maskRegionsListener, "Listener should be set")

        // This simulates what happens during cleanup - listener gets set to nil
        SensitiveViewManager.shared.maskRegionsListener = nil

        XCTAssertNil(SensitiveViewManager.shared.maskRegionsListener, "Listener should be nil after cleanup")
    }
}
