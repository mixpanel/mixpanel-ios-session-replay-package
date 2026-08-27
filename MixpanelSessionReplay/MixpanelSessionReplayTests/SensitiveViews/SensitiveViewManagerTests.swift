//
//  SensitiveViewManagerTests.swift
//  MixpanelSessionReplay
//
//  Created by Ketan on 04/03/25.
//  Copyright © 2025 Mixpanel. All rights reserved.
//

import SwiftUI
import WebKit
import XCTest

@testable import MixpanelSessionReplay

class SensitiveViewManagerTests: BaseTests {

    var manager: SensitiveViewManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        manager = SensitiveViewManager.shared
    }

    override func tearDownWithError() throws {
        manager = nil
        try super.tearDownWithError()
    }

    func testSensitiveViewDetection_TextField() {
        let textField = UITextField()
        let result = manager.isSensitiveView(view: textField)
        XCTAssertEqual(result, .sensitiveTextInput, "UITextField should be detected as sensitiveTextInput")
    }

    func testSensitiveViewDetection_EditableTextView() {
        let textView = UITextView()
        textView.isEditable = true
        let result = manager.isSensitiveView(view: textView)
        XCTAssertEqual(result, .sensitiveTextInput, "Editable UITextView should be detected as sensitiveTextInput")
    }

    func testSensitiveViewDetection_Label() {
        let label = UILabel()
        let result = manager.isSensitiveView(view: label)
        XCTAssertEqual(
            result, .sensitive, "UILabel should be detected as sensitive when maskAllText is enabled")
    }

    func testSensitiveViewDetection_NonEditableTextView() {
        let textView = UITextView()
        textView.isEditable = false
        let result = manager.isSensitiveView(view: textView)
        XCTAssertEqual(
            result, .sensitiveTextInput,
            "Non-editable UITextView should still be masked as text input for security (conservative approach)")
    }

    func testSensitiveViewDetection_ImageView() {
        let imageView = UIImageView()
        let result = manager.isSensitiveView(view: imageView)
        XCTAssertEqual(
            result, .sensitive,
            "UIImageView should be detected as sensitive when maskAllImages is enabled")
    }

    func testSensitiveViewDetection_WebView() {
        let webView = WKWebView()
        let result = manager.isSensitiveView(view: webView)
        XCTAssertEqual(
            result, .sensitive,
            "WKWebView should be detected as sensitive when maskAllWebViews is enabled")
    }

    func testNotSensitiveViewDetection_Label() {
        manager.maskAllText = false
        let label = UILabel()
        let result = manager.isSensitiveView(view: label)
        XCTAssertEqual(
            result, .unknown, "UILabel should be detected as sensitive when maskAllText is enabled")
    }

    func testNotSensitiveViewDetection_ImageView() {
        manager.maskAllImages = false
        let imageView = UIImageView()
        let result = manager.isSensitiveView(view: imageView)
        XCTAssertEqual(
            result, .unknown, "UIImageView should be detected as sensitive when maskAllImages is enabled")
    }

    func testNotSensitiveViewDetection_WebView() {
        manager.maskAllWebViews = false
        let webView = WKWebView()
        let result = manager.isSensitiveView(view: webView)
        XCTAssertEqual(
            result, .unknown, "WKWebView should be detected as sensitive when maskAllWebViews is enabled")
    }

    func testSensitiveViewDetection_SafeView() {
        let view = UIView()
        view.mpReplaySensitive = false
        let result = manager.isSensitiveView(view: view)
        XCTAssertEqual(result, .safe, "View explicitly marked as safe should return .safe")
    }

    func testAddingAndRemovingSensitiveClasses() {
        class CustomSensitiveView: UIView {}

        manager.addSensitiveClass(CustomSensitiveView.self)
        let view = CustomSensitiveView()
        XCTAssertEqual(
            manager.isSensitiveView(view: view), .sensitive,
            "CustomSensitiveView should be detected as sensitive")
        XCTAssertEqual(SensitiveViewManager.shared.sensitiveClasses.count, 1)

        manager.addSensitiveClass(CustomSensitiveView.self)
        XCTAssertEqual(
            SensitiveViewManager.shared.sensitiveClasses.count, 1, "Should not add duplicate classes")

        manager.removeSensitiveClass(CustomSensitiveView.self)
        XCTAssertEqual(SensitiveViewManager.shared.sensitiveClasses.count, 0)
        XCTAssertEqual(
            manager.isSensitiveView(view: view), .unknown,
            "CustomSensitiveView should be unknown after removal")
    }

    func testWeakViewsMap_InsertAndContains() {
        let view = UIView()
        let weakViewsMap = WeakViewsMap.weakToWeakObjects()

        weakViewsMap.insert(view)
        XCTAssertTrue(weakViewsMap.contains(view), "View should be in the weak map")

        weakViewsMap.remove(view)
        XCTAssertFalse(weakViewsMap.contains(view), "View should be removed from the weak map")
    }

    func testGetSensitiveFrames() {
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let window = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))

        let textField = UITextField(frame: CGRect(x: 10, y: 10, width: 50, height: 20))
        rootView.addSubview(textField)

        let sensitiveFrames = manager.getSensitiveFrames(in: rootView, window: window)
        XCTAssertEqual(
            sensitiveFrames[HashableRect(textField.frame)], .textInput,
            "Text field frame should be in sensitive frames as textInput")
    }

    func testSensitiveViewDetection_MarkedAsSensitive() {
        let view = UIView()
        view.mpReplaySensitive = true  // Explicitly marked as sensitive
        let result = manager.isSensitiveView(view: view)
        XCTAssertEqual(
            result, .sensitive, "View explicitly marked as sensitive should return .sensitive")
    }

    func testSensitiveViewDetection_InSensitiveMaps() {
        let view = UIView()

        manager.knownSensitiveViews.insert(view)
        XCTAssertEqual(
            manager.isSensitiveView(view: view), .sensitive,
            "View in knownSensitiveViews should return .sensitive")

        manager.knownSensitiveViews.remove(view)
        manager.sensitiveClassViews.insert(view)
        XCTAssertEqual(
            manager.isSensitiveView(view: view), .sensitive,
            "View in sensitiveClassViews should return .sensitive")
    }

    // MARK: - Cache Management Tests

    func testClearCache() {
        // Add views to all three caches
        let label = UILabel()
        let customView = UIView()
        let textField = UITextField()

        manager.knownSensitiveViews.insert(label)
        manager.sensitiveClassViews.insert(customView)
        manager.sensitiveTextInputViews.insert(textField)

        XCTAssertTrue(manager.knownSensitiveViews.contains(label))
        XCTAssertTrue(manager.sensitiveClassViews.contains(customView))
        XCTAssertTrue(manager.sensitiveTextInputViews.contains(textField))

        // Clear cache
        manager.clearCache()

        // Verify all caches are cleared
        XCTAssertFalse(manager.knownSensitiveViews.contains(label))
        XCTAssertFalse(manager.sensitiveClassViews.contains(customView))
        XCTAssertFalse(manager.sensitiveTextInputViews.contains(textField))
    }

    func testSensitiveViewDetection_TextField_ReturnsSensitiveTextInput() {
        let textField = UITextField()
        let result = manager.isSensitiveView(view: textField)
        XCTAssertEqual(
            result, .sensitiveTextInput,
            "UITextField should return .sensitiveTextInput enum case")
    }

    func testSensitiveViewDetection_TextField_ConsistentOnMultipleChecks() {
        let textField = UITextField()

        // First check - not in cache
        let firstResult = manager.isSensitiveView(view: textField)
        XCTAssertEqual(
            firstResult, .sensitiveTextInput,
            "UITextField should return .sensitiveTextInput on first check")

        // Second check - now in cache
        let secondResult = manager.isSensitiveView(view: textField)
        XCTAssertEqual(
            secondResult, .sensitiveTextInput,
            "UITextField should still return .sensitiveTextInput on subsequent checks (cached)")

        // Third check - verify consistency
        let thirdResult = manager.isSensitiveView(view: textField)
        XCTAssertEqual(
            thirdResult, .sensitiveTextInput,
            "UITextField should consistently return .sensitiveTextInput")
    }

    func testGetSensitiveFrames_TextFieldsSeparatelyTracked() {
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let window = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))

        // Add a text field
        let textField = UITextField(frame: CGRect(x: 10, y: 10, width: 50, height: 20))
        rootView.addSubview(textField)

        // Add a regular label
        let label = UILabel(frame: CGRect(x: 70, y: 10, width: 50, height: 20))
        rootView.addSubview(label)

        manager.maskAllText = true
        let sensitiveFrames = manager.getSensitiveFrames(in: rootView, window: window)

        // Both should be in sensitive frames with correct types
        XCTAssertEqual(
            sensitiveFrames[HashableRect(textField.frame)], .textInput,
            "Text field should be marked as textInput")
        XCTAssertEqual(
            sensitiveFrames[HashableRect(label.frame)], .auto,
            "Label should be marked as auto")
    }

    // MARK: - HashableRect Tests

    func testHashableRect_Contains() {
        let outerRect = HashableRect(CGRect(x: 0, y: 0, width: 100, height: 100))
        let innerRect = HashableRect(CGRect(x: 10, y: 10, width: 50, height: 50))
        let nonContainedRect = HashableRect(CGRect(x: 50, y: 50, width: 100, height: 100))

        XCTAssertTrue(outerRect.contains(innerRect), "Outer rect should contain inner rect")
        XCTAssertFalse(
            outerRect.contains(nonContainedRect), "Outer rect should not contain overlapping rect")
        XCTAssertFalse(innerRect.contains(outerRect), "Inner rect should not contain outer rect")
    }

    func testHashableRect_ContainsSameRect() {
        let rect = HashableRect(CGRect(x: 10, y: 10, width: 50, height: 50))
        XCTAssertTrue(rect.contains(rect), "Rect should contain itself")
    }

    // MARK: - CALayer Extension Tests

    func testCALayer_IsVisible_WhenVisible() {
        let layer = CALayer()
        layer.isHidden = false
        layer.opacity = 1.0
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        XCTAssertTrue(layer.isVisible(), "Layer should be visible")
    }

    func testCALayer_IsVisible_WhenHidden() {
        let layer = CALayer()
        layer.isHidden = true
        layer.opacity = 1.0
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        XCTAssertFalse(layer.isVisible(), "Hidden layer should not be visible")
    }

    func testCALayer_IsVisible_WhenZeroOpacity() {
        let layer = CALayer()
        layer.isHidden = false
        layer.opacity = 0.0
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        XCTAssertFalse(layer.isVisible(), "Layer with zero opacity should not be visible")
    }

    // MARK: - iOS 26+ Layer Detection Tests

    @available(iOS 26.0, *)
    func testIsImageLayer_WithoutContents() {
        manager.maskAllImages = true

        // Create a layer with UIImageView as delegate
        let layer = CALayer()
        let imageView = UIImageView()
        layer.delegate = imageView

        let isImage = manager.isImageLayer(layer)
        XCTAssertFalse(
            isImage, "Layer with UIImageView delegate should not be detected as contents are empty")
    }

    @available(iOS 26.0, *)
    func testIsImageLayer_WithContents() {
        manager.maskAllImages = true

        // Create a layer with UIImageView as delegate
        let layer = CALayer()
        let imageView = UIImageView()
        layer.delegate = imageView
        let image = UIImage(systemName: "star.fill")
        layer.contents = image?.cgImage
        let isImage = manager.isImageLayer(layer)
        XCTAssertTrue(
            isImage, "Layer with UIImageView delegate should not be detected as contents are empty")
    }

    @available(iOS 26.0, *)
    func testIsImageLayer_WithoutDelegate() {
        manager.maskAllImages = true

        let layer = CALayer()
        layer.delegate = nil

        XCTAssertFalse(
            manager.isImageLayer(layer), "Layer without delegate should not be detected as image layer")
    }

    // MARK: - Layer Frame Detection Testsx

    func testGetFrame_ForVisibleLayer() {
        let window = UIView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        layer.position = CGPoint(x: 50, y: 50)
        layer.isHidden = false
        layer.opacity = 1.0

        // Add layer to window's layer
        window.layer.addSublayer(layer)

        let frame = manager.getFrame(for: layer, in: window)
        XCTAssertNotNil(frame, "Frame should be detected for visible layer")
        XCTAssertTrue(
            frame!.width > 1 && frame!.height > 1, "Frame should have valid dimensions")
    }

    func testGetFrame_ForLayerOutOfBounds() {
        let window = UIView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        layer.position = CGPoint(x: 1000, y: 1000)  // Way outside window
        layer.isHidden = false
        layer.opacity = 1.0

        let frame = manager.getFrame(for: layer, in: window)
        XCTAssertNil(frame, "Frame should be nil for layer outside window bounds")
    }

    func testGetFrame_ForTinyLayer() {
        let window = UIView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)  // Tiny layer
        layer.position = CGPoint(x: 50, y: 50)
        layer.isHidden = false
        layer.opacity = 1.0

        window.layer.addSublayer(layer)

        let frame = manager.getFrame(for: layer, in: window)
        XCTAssertNil(frame, "Frame should be nil for layers smaller than 1x1")
    }

    // MARK: - Safe Frame Filtering Tests

    func testGetSensitiveFrames_WithSafeFrameFiltering() {
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let window = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))

        // Create a container marked as safe
        let safeContainer = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        safeContainer.mpReplaySensitive = false
        rootView.addSubview(safeContainer)

        // Add sensitive view inside safe container
        let labelInsideSafe = UILabel(frame: CGRect(x: 10, y: 10, width: 50, height: 20))
        safeContainer.addSubview(labelInsideSafe)

        // Add sensitive view outside safe container
        let labelOutsideSafe = UILabel(frame: CGRect(x: 120, y: 10, width: 50, height: 20))
        rootView.addSubview(labelOutsideSafe)

        manager.maskAllText = true
        let sensitiveFrames = manager.getSensitiveFrames(in: rootView, window: window)

        // The label inside the safe container should be filtered out
        // The return value should only contain mask entries (no unmask)
        XCTAssertEqual(
            sensitiveFrames.count, 1,
            "Only label outside safe container should be in return value")
        XCTAssertEqual(
            sensitiveFrames[HashableRect(labelOutsideSafe.frame)], .auto,
            "Label outside safe container should appear as auto")
        XCTAssertNil(
            sensitiveFrames[HashableRect(labelInsideSafe.frame)],
            "Label inside safe container should be filtered out")
        // Safe container should not appear in the return value (unmask is debug-only)
        XCTAssertNil(
            sensitiveFrames[HashableRect(safeContainer.frame)],
            "Safe container should not be in production return value")
    }

    func testGetSensitiveFrames_ListenerReceivesUnmaskEntries() {
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let window = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))

        // Create a container marked as safe
        let safeContainer = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        safeContainer.mpReplaySensitive = false
        rootView.addSubview(safeContainer)

        // Add sensitive view outside safe container
        let label = UILabel(frame: CGRect(x: 120, y: 10, width: 50, height: 20))
        rootView.addSubview(label)

        manager.maskAllText = true

        // Set up listener to capture what it receives
        var listenerDecisions: [HashableRect: MaskDecision]?
        manager.maskRegionsListener = { (decisions, _) in
            listenerDecisions = decisions
        }

        let returnValue = manager.getSensitiveFrames(in: rootView, window: window)

        // Return value should NOT contain unmask
        XCTAssertNil(
            returnValue[HashableRect(safeContainer.frame)],
            "Return value should not contain unmask entries")
        XCTAssertEqual(returnValue.count, 1)

        // Listener should receive unmask entries
        XCTAssertNotNil(listenerDecisions)
        XCTAssertEqual(
            listenerDecisions?[HashableRect(safeContainer.frame)], .unmask,
            "Listener should receive unmask entry for safe container")
        XCTAssertEqual(
            listenerDecisions?[HashableRect(label.frame)], .auto,
            "Listener should receive auto entry for label")
        XCTAssertEqual(listenerDecisions?.count, 2)

        // Clean up
        manager.maskRegionsListener = nil
    }

    func testGetSensitiveFrames_InvisibleViewsExcluded() {
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let window = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))

        // Visible label
        let visibleLabel = UILabel(frame: CGRect(x: 10, y: 10, width: 50, height: 20))
        visibleLabel.isHidden = false
        rootView.addSubview(visibleLabel)

        // Hidden label
        let hiddenLabel = UILabel(frame: CGRect(x: 70, y: 10, width: 50, height: 20))
        hiddenLabel.isHidden = true
        rootView.addSubview(hiddenLabel)

        // Zero alpha label
        let invisibleLabel = UILabel(frame: CGRect(x: 130, y: 10, width: 50, height: 20))
        invisibleLabel.alpha = 0
        rootView.addSubview(invisibleLabel)

        manager.maskAllText = true
        let sensitiveFrames = manager.getSensitiveFrames(in: rootView, window: window)

        XCTAssertEqual(sensitiveFrames.count, 1, "Only visible label should be in sensitive frames")
        XCTAssertEqual(
            sensitiveFrames[HashableRect(visibleLabel.frame)], .auto,
            "Visible label should be marked as auto")
    }

    @available(iOS 26.0, *)
    func testGetSensitiveFrames_WithLayerHierarchy() {
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let window = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))

        // Create a view with sublayers
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        rootView.addSubview(containerView)

        // Add a layer with UIImageView delegate (simulating iOS 26 SwiftUI Image)
        let imageLayer = CALayer()
        imageLayer.bounds = CGRect(x: 0, y: 0, width: 50, height: 50)
        imageLayer.position = CGPoint(x: 50, y: 50)
        imageLayer.isHidden = false
        imageLayer.opacity = 1.0
        let image = UIImage(systemName: "star.fill")
        let imageView = UIImageView()
        imageLayer.delegate = imageView
        imageLayer.contents = image?.cgImage
        containerView.layer.addSublayer(imageLayer)

        manager.maskAllImages = true
        let sensitiveFrames = manager.getSensitiveFrames(in: rootView, window: window)

        XCTAssertTrue(
            sensitiveFrames.count >= 1,
            "Should detect image layer with UIImageView delegate")
        // Verify auto-detected layers are marked as .auto
        let autoEntries = sensitiveFrames.filter { $0.value == .auto }
        XCTAssertTrue(autoEntries.count >= 1, "Image layer should be marked as auto")
    }

    func test_decodedCharCodes_matchExpectedMangledName() {
        let decoded = manager.swiftUIDrawingLayerCodes.decodedString() ?? nil
        XCTAssertEqual(
            decoded,
            "_TtC7SwiftUIP33_863CCF9D49B535DAEB1C7D61BEE53B5914CGDrawingLayer",
            "Decoded byte array no longer matches the real SwiftUI private class name. "
                + "If this fails, either the byte array was edited incorrectly, or Apple has "
                + "renamed/re-mangled the class in a newer SwiftUI — re-derive the codes."
        )
    }

    func test_decodedName_resolvesToARealClass() throws {
        try XCTSkipUnless(
            {
                if #available(iOS 26.0, *) { return true }
                return false
            }(),
            "CGDrawingLayer only exists on iOS 26+"
        )

        let resolvedClass: AnyClass? = ObfuscatedClassLookup.resolveClass(from: manager.swiftUIDrawingLayerCodes)

        XCTAssertNotNil(
            resolvedClass,
            "NSClassFromString failed to resolve the decoded name to an actual class on this OS. "
                + "SwiftUI may have renamed/removed CGDrawingLayer in this iOS version — "
        )
    }

    // MARK: UIKit TextField Masking in Safe Views

    func testTextFieldInSafeView_IsMasked() {
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let window = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))

        // Create a container marked as safe
        let safeContainer = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        safeContainer.mpReplaySensitive = false
        rootView.addSubview(safeContainer)

        // Add a textfield inside the safe container
        let textField = UITextField(frame: CGRect(x: 10, y: 10, width: 80, height: 30))
        safeContainer.addSubview(textField)

        // Add a regular label inside safe container (should not be masked)
        let label = UILabel(frame: CGRect(x: 10, y: 50, width: 80, height: 20))
        safeContainer.addSubview(label)

        manager.maskAllText = true
        let sensitiveFrames = manager.getSensitiveFrames(in: rootView, window: window)

        // The textfield should be masked even though its parent is safe
        XCTAssertEqual(
            sensitiveFrames[HashableRect(textField.frame)], .textInput,
            "TextField inside safe container should still be masked as textInput")

        // The label should not be masked (parent is safe)
        XCTAssertNil(
            sensitiveFrames[HashableRect(label.frame)],
            "Label inside safe container should not be masked")
    }

    func testNestedTextFieldsInSafeView_AllMasked() {
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let window = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))

        // Create a safe container
        let safeContainer = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        safeContainer.mpReplaySensitive = false
        rootView.addSubview(safeContainer)

        // Add a nested container inside safe view
        let nestedContainer = UIView(frame: CGRect(x: 10, y: 10, width: 180, height: 180))
        safeContainer.addSubview(nestedContainer)

        // Add textfield at level 1 (direct child of safe view)
        let textField1 = UITextField(frame: CGRect(x: 10, y: 10, width: 80, height: 30))
        safeContainer.addSubview(textField1)

        // Add UITextView at level 1
        let textView1 = UITextView(frame: CGRect(x: 10, y: 50, width: 80, height: 30))
        safeContainer.addSubview(textView1)

        // Add textfield at level 2 (nested inside another view)
        let textField2 = UITextField(frame: CGRect(x: 10, y: 10, width: 80, height: 30))
        nestedContainer.addSubview(textField2)

        // Add UITextView at level 2
        let textView2 = UITextView(frame: CGRect(x: 10, y: 50, width: 40, height: 30))
        nestedContainer.addSubview(textView2)

        // Add deeply nested textfield at level 3
        let deepContainer = UIView(frame: CGRect(x: 10, y: 50, width: 160, height: 120))
        nestedContainer.addSubview(deepContainer)
        let textField3 = UITextField(frame: CGRect(x: 10, y: 10, width: 80, height: 30))
        deepContainer.addSubview(textField3)
        // Add UITextView at level 3
        let textView3 = UITextView(frame: CGRect(x: 10, y: 54, width: 90, height: 30))
        deepContainer.addSubview(textView3)
        let sensitiveFrames = manager.getSensitiveFrames(in: rootView, window: window)

        // Convert frames to window coordinates for lookup (getSensitiveFrames returns window coordinates)
        let textField1WindowFrame = textField1.convert(textField1.bounds, to: window)
        let textView1WindowFrame = textView1.convert(textView1.bounds, to: window)
        let textField2WindowFrame = textField2.convert(textField2.bounds, to: window)
        let textView2WindowFrame = textView2.convert(textView2.bounds, to: window)
        let textField3WindowFrame = textField3.convert(textField3.bounds, to: window)
        let textView3WindowFrame = textView3.convert(textView3.bounds, to: window)

        // All textfields should be masked via stack-based traversal
        XCTAssertEqual(
            sensitiveFrames[HashableRect(textField1WindowFrame)], .textInput,
            "TextField at level 1 should be masked")
        XCTAssertEqual(
            sensitiveFrames[HashableRect(textView1WindowFrame)], .textInput,
            "TextView at level 1 should be masked")
        XCTAssertEqual(
            sensitiveFrames[HashableRect(textField2WindowFrame)], .textInput,
            "TextField at level 2 should be masked")
        XCTAssertEqual(
            sensitiveFrames[HashableRect(textView2WindowFrame)], .textInput,
            "TextView at level 2 should be masked")
        XCTAssertEqual(
            sensitiveFrames[HashableRect(textField3WindowFrame)], .textInput,
            "Deeply nested textfield at level 3 should be masked")
        XCTAssertEqual(
            sensitiveFrames[HashableRect(textView3WindowFrame)], .textInput,
            "Deeply nested TextView at level 3 should be masked")

    }

    func testSafeView_WithoutTextFields_BehavesNormally() {
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let window = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))

        // Create a safe container with no textfields
        let safeContainer = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        safeContainer.mpReplaySensitive = false
        rootView.addSubview(safeContainer)

        // Add regular views inside (should not be masked)
        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 80, height: 20))
        safeContainer.addSubview(label)

        let imageView = UIImageView(frame: CGRect(x: 10, y: 40, width: 80, height: 40))
        safeContainer.addSubview(imageView)

        manager.maskAllText = true
        manager.maskAllImages = true
        let sensitiveFrames = manager.getSensitiveFrames(in: rootView, window: window)

        // Nothing should be masked (all inside safe container, no textfields)
        XCTAssertNil(
            sensitiveFrames[HashableRect(label.frame)],
            "Label inside safe container should not be masked")
        XCTAssertNil(
            sensitiveFrames[HashableRect(imageView.frame)],
            "ImageView inside safe container should not be masked")
    }

    func testMultipleSafeViews_WithTextFields() {
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let window = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))

        // First safe container with textfield
        let safeContainer1 = UIView(frame: CGRect(x: 0, y: 0, width: 140, height: 100))
        safeContainer1.mpReplaySensitive = false
        rootView.addSubview(safeContainer1)

        let textField1 = UITextField(frame: CGRect(x: 10, y: 10, width: 120, height: 30))
        safeContainer1.addSubview(textField1)

        // Second safe container with textfield
        let safeContainer2 = UIView(frame: CGRect(x: 150, y: 0, width: 140, height: 100))
        safeContainer2.mpReplaySensitive = false
        rootView.addSubview(safeContainer2)

        let textField2 = UITextField(frame: CGRect(x: 10, y: 10, width: 120, height: 30))
        safeContainer2.addSubview(textField2)

        let sensitiveFrames = manager.getSensitiveFrames(in: rootView, window: window)

        // Both textfields should be masked
        XCTAssertEqual(
            sensitiveFrames[HashableRect(textField1.frame)], .textInput,
            "TextField in first safe container should be masked")
        XCTAssertEqual(
            sensitiveFrames[HashableRect(textField2.frame)], .textInput,
            "TextField in second safe container should be masked")
    }

    func testSafeViewWithTextFieldAndSensitiveView_BothHandledCorrectly() {
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let window = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))

        // Safe container
        let safeContainer = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        safeContainer.mpReplaySensitive = false
        rootView.addSubview(safeContainer)

        // Textfield inside safe view (should be masked)
        let textField = UITextField(frame: CGRect(x: 10, y: 10, width: 80, height: 30))
        safeContainer.addSubview(textField)

        // Regular sensitive view outside safe container (should be masked)
        let sensitiveView = UIView(frame: CGRect(x: 120, y: 10, width: 70, height: 70))
        sensitiveView.mpReplaySensitive = true
        rootView.addSubview(sensitiveView)

        let sensitiveFrames = manager.getSensitiveFrames(in: rootView, window: window)

        // TextField should be masked
        XCTAssertEqual(
            sensitiveFrames[HashableRect(textField.frame)], .textInput,
            "TextField inside safe container should be masked")

        // Sensitive view should be masked
        XCTAssertEqual(
            sensitiveFrames[HashableRect(sensitiveView.frame)], .mask,
            "Explicitly sensitive view should be masked as .mask")
    }

    func testSafeView_InvisibleTextFieldsNotMasked() {
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let window = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))

        // Safe container
        let safeContainer = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        safeContainer.mpReplaySensitive = false
        rootView.addSubview(safeContainer)

        // Hidden textfield (should NOT be masked)
        let hiddenTextField = UITextField(frame: CGRect(x: 10, y: 10, width: 80, height: 30))
        hiddenTextField.isHidden = true
        safeContainer.addSubview(hiddenTextField)

        // Transparent textfield (should NOT be masked)
        let transparentTextField = UITextField(frame: CGRect(x: 10, y: 50, width: 80, height: 30))
        transparentTextField.alpha = 0
        safeContainer.addSubview(transparentTextField)

        // Visible textfield (should be masked)
        let visibleTextField = UITextField(frame: CGRect(x: 10, y: 90, width: 80, height: 30))
        safeContainer.addSubview(visibleTextField)

        let sensitiveFrames = manager.getSensitiveFrames(in: rootView, window: window)

        // Hidden and transparent textfields should NOT be in sensitive frames
        XCTAssertNil(
            sensitiveFrames[HashableRect(hiddenTextField.frame)],
            "Hidden textfield should not be masked")
        XCTAssertNil(
            sensitiveFrames[HashableRect(transparentTextField.frame)],
            "Transparent textfield should not be masked")

        // Visible textfield SHOULD be masked
        XCTAssertEqual(
            sensitiveFrames[HashableRect(visibleTextField.frame)], .textInput,
            "Visible textfield should be masked")
    }

    // MARK: - SwiftUI TextEditor TextField Masking in Safe Views

    func testSwiftUITextEditor_DetectedAsTextInput() throws {
        // SwiftUI.TextEditorTextView is the internal class used by SwiftUI TextEditor
        guard let swiftUITextEditorClass = NSClassFromString("SwiftUI.TextEditorTextView") else {
            throw XCTSkip("SwiftUI.TextEditorTextView class not available on this OS version")
        }

        // Create an instance using the class
        guard let textEditor = (swiftUITextEditorClass as? NSObject.Type)?.init() as? UIView else {
            XCTFail("Failed to create SwiftUI.TextEditorTextView instance")
            return
        }

        let result = manager.isSensitiveView(view: textEditor)
        XCTAssertEqual(
            result, .sensitiveTextInput,
            "SwiftUI TextEditor should be detected as sensitiveTextInput")
    }

    func testSwiftUITextEditor_IsTextInput() throws {
        guard let swiftUITextEditorClass = NSClassFromString("SwiftUI.TextEditorTextView") else {
            throw XCTSkip("SwiftUI.TextEditorTextView class not available on this OS version")
        }

        guard let textEditor = (swiftUITextEditorClass as? NSObject.Type)?.init() as? UIView else {
            XCTFail("Failed to create SwiftUI.TextEditorTextView instance")
            return
        }

        XCTAssertTrue(
            manager.isTextInput(view: textEditor),
            "SwiftUI TextEditor should be recognized as text input")
    }

    func testSwiftUITextEditor_InSafeView_IsMasked() throws {
        guard let swiftUITextEditorClass = NSClassFromString("SwiftUI.TextEditorTextView") else {
            throw XCTSkip("SwiftUI.TextEditorTextView class not available on this OS version")
        }

        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let window = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))

        // Create a safe container
        let safeContainer = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        safeContainer.mpReplaySensitive = false
        rootView.addSubview(safeContainer)

        // Add SwiftUI TextEditor inside safe container
        guard let textEditor = (swiftUITextEditorClass as? NSObject.Type)?.init() as? UIView else {
            XCTFail("Failed to create SwiftUI.TextEditorTextView instance")
            return
        }
        textEditor.frame = CGRect(x: 10, y: 10, width: 80, height: 30)
        safeContainer.addSubview(textEditor)

        // Add a regular label inside safe container (should not be masked)
        let label = UILabel(frame: CGRect(x: 10, y: 50, width: 80, height: 20))
        safeContainer.addSubview(label)

        manager.maskAllText = true
        let sensitiveFrames = manager.getSensitiveFrames(in: rootView, window: window)

        // SwiftUI TextEditor should be masked even though its parent is safe
        XCTAssertEqual(
            sensitiveFrames[HashableRect(textEditor.frame)], .textInput,
            "SwiftUI TextEditor inside safe container should still be masked as textInput")

        // The label should not be masked (parent is safe)
        XCTAssertNil(
            sensitiveFrames[HashableRect(label.frame)],
            "Label inside safe container should not be masked")
    }

    func testSwiftUITextEditor_NestedInSafeViews_IsMasked() throws {
        guard let swiftUITextEditorClass = NSClassFromString("SwiftUI.TextEditorTextView") else {
            throw XCTSkip("SwiftUI.TextEditorTextView class not available on this OS version")
        }

        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let window = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))

        // Create a safe container
        let safeContainer = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        safeContainer.mpReplaySensitive = false
        rootView.addSubview(safeContainer)

        // Add nested container inside safe view
        let nestedContainer = UIView(frame: CGRect(x: 10, y: 10, width: 180, height: 180))
        safeContainer.addSubview(nestedContainer)

        // Add SwiftUI TextEditor at level 1
        guard let textEditor1 = (swiftUITextEditorClass as? NSObject.Type)?.init() as? UIView else {
            XCTFail("Failed to create SwiftUI.TextEditorTextView instance")
            return
        }
        textEditor1.frame = CGRect(x: 10, y: 10, width: 80, height: 30)
        safeContainer.addSubview(textEditor1)

        // Add SwiftUI TextEditor at level 2
        guard let textEditor2 = (swiftUITextEditorClass as? NSObject.Type)?.init() as? UIView else {
            XCTFail("Failed to create SwiftUI.TextEditorTextView instance")
            return
        }
        textEditor2.frame = CGRect(x: 10, y: 10, width: 80, height: 30)
        nestedContainer.addSubview(textEditor2)

        let sensitiveFrames = manager.getSensitiveFrames(in: rootView, window: window)

        // Both SwiftUI TextEditors should be masked
        XCTAssertEqual(
            sensitiveFrames[HashableRect(textEditor1.frame)], .textInput,
            "SwiftUI TextEditor at level 1 should be masked")
        XCTAssertEqual(
            sensitiveFrames[HashableRect(textEditor2.frame)], .textInput,
            "SwiftUI TextEditor at level 2 should be masked")
    }

    func testMixedTextInputs_InSafeView_AllMasked() throws {
        guard let swiftUITextEditorClass = NSClassFromString("SwiftUI.TextEditorTextView") else {
            throw XCTSkip("SwiftUI.TextEditorTextView class not available on this OS version")
        }

        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let window = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))

        // Create a safe container
        let safeContainer = UIView(frame: CGRect(x: 0, y: 0, width: 250, height: 250))
        safeContainer.mpReplaySensitive = false
        rootView.addSubview(safeContainer)

        // Add UITextField
        let textField = UITextField(frame: CGRect(x: 10, y: 10, width: 80, height: 30))
        safeContainer.addSubview(textField)

        // Add UITextView
        let textView = UITextView(frame: CGRect(x: 10, y: 50, width: 80, height: 30))
        safeContainer.addSubview(textView)

        // Add SwiftUI TextEditor
        guard let textEditor = (swiftUITextEditorClass as? NSObject.Type)?.init() as? UIView else {
            XCTFail("Failed to create SwiftUI.TextEditorTextView instance")
            return
        }
        textEditor.frame = CGRect(x: 10, y: 90, width: 80, height: 30)
        safeContainer.addSubview(textEditor)

        // Add regular label (should not be masked)
        let label = UILabel(frame: CGRect(x: 10, y: 130, width: 80, height: 20))
        safeContainer.addSubview(label)

        manager.maskAllText = true
        let sensitiveFrames = manager.getSensitiveFrames(in: rootView, window: window)

        // All text inputs should be masked
        XCTAssertEqual(
            sensitiveFrames[HashableRect(textField.frame)], .textInput,
            "UITextField inside safe container should be masked")
        XCTAssertEqual(
            sensitiveFrames[HashableRect(textView.frame)], .textInput,
            "UITextView inside safe container should be masked")
        XCTAssertEqual(
            sensitiveFrames[HashableRect(textEditor.frame)], .textInput,
            "SwiftUI TextEditor inside safe container should be masked")

        // Label should not be masked
        XCTAssertNil(
            sensitiveFrames[HashableRect(label.frame)],
            "Label inside safe container should not be masked")
    }

    func testSwiftUITextEditor_Cache_ConsistentAcrossChecks() throws {
        guard let swiftUITextEditorClass = NSClassFromString("SwiftUI.TextEditorTextView") else {
            throw XCTSkip("SwiftUI.TextEditorTextView class not available on this OS version")
        }

        guard let textEditor = (swiftUITextEditorClass as? NSObject.Type)?.init() as? UIView else {
            XCTFail("Failed to create SwiftUI.TextEditorTextView instance")
            return
        }

        // First check - not in cache
        let firstResult = manager.isSensitiveView(view: textEditor)
        XCTAssertEqual(
            firstResult, .sensitiveTextInput,
            "SwiftUI TextEditor should return .sensitiveTextInput on first check")

        // Verify it's now in the text input cache
        XCTAssertTrue(
            manager.sensitiveTextInputViews.contains(textEditor),
            "SwiftUI TextEditor should be added to sensitiveTextInputViews cache")

        // Second check - now in cache
        let secondResult = manager.isSensitiveView(view: textEditor)
        XCTAssertEqual(
            secondResult, .sensitiveTextInput,
            "SwiftUI TextEditor should still return .sensitiveTextInput on subsequent checks (cached)")

        // Third check - verify consistency
        let thirdResult = manager.isSensitiveView(view: textEditor)
        XCTAssertEqual(
            thirdResult, .sensitiveTextInput,
            "SwiftUI TextEditor should consistently return .sensitiveTextInput")
    }

    func testSwiftUITextEditor_InvisibleInSafeView_NotMasked() throws {
        guard let swiftUITextEditorClass = NSClassFromString("SwiftUI.TextEditorTextView") else {
            throw XCTSkip("SwiftUI.TextEditorTextView class not available on this OS version")
        }

        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let window = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))

        // Create a safe container
        let safeContainer = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        safeContainer.mpReplaySensitive = false
        rootView.addSubview(safeContainer)

        // Hidden SwiftUI TextEditor
        guard let hiddenTextEditor = (swiftUITextEditorClass as? NSObject.Type)?.init() as? UIView else {
            XCTFail("Failed to create SwiftUI.TextEditorTextView instance")
            return
        }
        hiddenTextEditor.frame = CGRect(x: 10, y: 10, width: 80, height: 30)
        hiddenTextEditor.isHidden = true
        safeContainer.addSubview(hiddenTextEditor)

        // Transparent SwiftUI TextEditor
        guard let transparentTextEditor = (swiftUITextEditorClass as? NSObject.Type)?.init() as? UIView else {
            XCTFail("Failed to create SwiftUI.TextEditorTextView instance")
            return
        }
        transparentTextEditor.frame = CGRect(x: 10, y: 50, width: 80, height: 30)
        transparentTextEditor.alpha = 0
        safeContainer.addSubview(transparentTextEditor)

        // Visible SwiftUI TextEditor
        guard let visibleTextEditor = (swiftUITextEditorClass as? NSObject.Type)?.init() as? UIView else {
            XCTFail("Failed to create SwiftUI.TextEditorTextView instance")
            return
        }
        visibleTextEditor.frame = CGRect(x: 10, y: 90, width: 80, height: 30)
        safeContainer.addSubview(visibleTextEditor)

        let sensitiveFrames = manager.getSensitiveFrames(in: rootView, window: window)

        // Hidden and transparent SwiftUI TextEditors should NOT be masked
        XCTAssertNil(
            sensitiveFrames[HashableRect(hiddenTextEditor.frame)],
            "Hidden SwiftUI TextEditor should not be masked")
        XCTAssertNil(
            sensitiveFrames[HashableRect(transparentTextEditor.frame)],
            "Transparent SwiftUI TextEditor should not be masked")

        // Visible SwiftUI TextEditor SHOULD be masked
        XCTAssertEqual(
            sensitiveFrames[HashableRect(visibleTextEditor.frame)], .textInput,
            "Visible SwiftUI TextEditor should be masked")
    }
}
