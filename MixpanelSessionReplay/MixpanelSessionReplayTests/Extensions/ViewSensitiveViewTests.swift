//
//  ViewSensitiveViewTests.swift
//  MixpanelSessionReplay
//
//  Created by Claude on 19/08/26.
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import SwiftUI
import XCTest

@testable import MixpanelSessionReplay

class ViewSensitiveViewTests: XCTestCase {

    // MARK: - PR #113 Tests: SwiftUI Modifier Backward Compatibility

    func testMpReplaySensitive_AcceptsBoolValue() {
        // Test that the modifier accepts Bool values (backward compatibility)
        let view = Text("Test")

        // Should compile and work with true
        let sensitiveView = view.mpReplaySensitive(true)
        XCTAssertNotNil(sensitiveView, "Modifier should accept Bool value 'true'")

        // Should compile and work with false
        let safeView = view.mpReplaySensitive(false)
        XCTAssertNotNil(safeView, "Modifier should accept Bool value 'false'")
    }

    func testMpReplaySensitive_AcceptsOptionalBoolValue() {
        // Test that the modifier accepts Bool? values (new API)
        let view = Text("Test")

        // Should work with explicit Bool? values
        let sensitiveView = view.mpReplaySensitive(Optional(true))
        XCTAssertNotNil(sensitiveView, "Modifier should accept Bool? value")

        let safeView = view.mpReplaySensitive(Optional(false))
        XCTAssertNotNil(safeView, "Modifier should accept Bool? value")

        // Should work with nil
        let unspecifiedView = view.mpReplaySensitive(nil)
        XCTAssertNotNil(unspecifiedView, "Modifier should accept nil value")
    }

    func testMixpanelSensitiveWrapper_WithBoolValue() {
        // Test the new wrapper with Bool values
        let content = Text("Test Content")

        let wrapper = MixpanelSensitiveWrapper(isSensitive: true) {
            content
        }

        XCTAssertEqual(wrapper.isSensitive, true, "Wrapper should store Bool value as Bool?")
    }

    func testMixpanelSensitiveWrapper_WithNilValue() {
        // Test the new wrapper with nil value
        let content = Text("Test Content")

        let wrapper = MixpanelSensitiveWrapper(isSensitive: nil) {
            content
        }

        XCTAssertNil(wrapper.isSensitive, "Wrapper should handle nil value")
    }

    func testMixpanelSensitiveWrapper_CreatesHostingController() {
        // Test that the wrapper creates a UIHostingController
        let content = Text("Test Content")

        let wrapper = MixpanelSensitiveWrapper(isSensitive: true) {
            content
        }

        let context = wrapper.makeUIViewController(context: ViewControllerRepresentableContext(wrapper))

        XCTAssertTrue(
            context is UIHostingController<Text>,
            "Should create UIHostingController")
    }

    func testMixpanelSensitiveWrapper_SetsPropertyOnView() {
        // Test that the wrapper sets mpReplaySensitive on the view
        let content = Text("Test Content")

        let wrapper = MixpanelSensitiveWrapper(isSensitive: true) {
            content
        }

        let controller = wrapper.makeUIViewController(
            context: ViewControllerRepresentableContext(wrapper))

        XCTAssertEqual(
            controller.view.mpReplaySensitive, true,
            "Should set mpReplaySensitive=true on the controller's view")
    }

    func testMixpanelSensitiveWrapper_DoesNotSetPropertyWhenNil() {
        // Test that the wrapper doesn't set property when isSensitive is nil
        let content = Text("Test Content")

        let wrapper = MixpanelSensitiveWrapper(isSensitive: nil) {
            content
        }

        let controller = wrapper.makeUIViewController(
            context: ViewControllerRepresentableContext(wrapper))

        XCTAssertNil(
            controller.view.mpReplaySensitive,
            "Should not set mpReplaySensitive when isSensitive is nil")
    }

    func testMixpanelSensitiveWrapper_UpdatesPropertyOnChange() {
        // Test that the wrapper updates the property when state changes
        let content = Text("Test Content")

        let wrapper = MixpanelSensitiveWrapper(isSensitive: false) {
            content
        }

        let controller = wrapper.makeUIViewController(
            context: ViewControllerRepresentableContext(wrapper))

        XCTAssertEqual(
            controller.view.mpReplaySensitive, false,
            "Initial value should be false")

        // Simulate update
        let updatedWrapper = MixpanelSensitiveWrapper(isSensitive: true) {
            content
        }

        updatedWrapper.updateUIViewController(
            controller,
            context: ViewControllerRepresentableContext(updatedWrapper))

        XCTAssertEqual(
            controller.view.mpReplaySensitive, true,
            "Should update to true after updateUIViewController")
    }
}

// Helper to create ViewControllerRepresentableContext for testing
extension ViewControllerRepresentableContext {
    init(_ representable: Representable) {
        self.init(representable, coordinator: representable.makeCoordinator())
    }
}
