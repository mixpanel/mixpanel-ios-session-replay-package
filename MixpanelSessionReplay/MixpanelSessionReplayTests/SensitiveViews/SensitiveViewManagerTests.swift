//
//  SensitiveViewManagerTests.swift
//  MixpanelSessionReplay
//
//  Created by Ketan on 04/03/25.
//  Copyright © 2025 Mixpanel. All rights reserved.
//

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
        XCTAssertEqual(result, .sensitiveTextField, "UITextField should be detected as sensitiveTextField")
    }

    func testSensitiveViewDetection_Label() {
        let label = UILabel()
        let result = manager.isSensitiveView(view: label)
        XCTAssertEqual(
            result, .sensitive, "UILabel should be detected as sensitive when maskAllText is enabled")
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
        manager.sensitiveTextFieldViews.insert(textField)

        XCTAssertTrue(manager.knownSensitiveViews.contains(label))
        XCTAssertTrue(manager.sensitiveClassViews.contains(customView))
        XCTAssertTrue(manager.sensitiveTextFieldViews.contains(textField))

        // Clear cache
        manager.clearCache()

        // Verify all caches are cleared
        XCTAssertFalse(manager.knownSensitiveViews.contains(label))
        XCTAssertFalse(manager.sensitiveClassViews.contains(customView))
        XCTAssertFalse(manager.sensitiveTextFieldViews.contains(textField))
    }

    func testSensitiveViewDetection_TextField_ReturnsSensitiveTextField() {
        let textField = UITextField()
        let result = manager.isSensitiveView(view: textField)
        XCTAssertEqual(
            result, .sensitiveTextField,
            "UITextField should return .sensitiveTextField enum case")
    }

    func testSensitiveViewDetection_TextField_ConsistentOnMultipleChecks() {
        let textField = UITextField()

        // First check - not in cache
        let firstResult = manager.isSensitiveView(view: textField)
        XCTAssertEqual(
            firstResult, .sensitiveTextField,
            "UITextField should return .sensitiveTextField on first check")

        // Second check - now in cache
        let secondResult = manager.isSensitiveView(view: textField)
        XCTAssertEqual(
            secondResult, .sensitiveTextField,
            "UITextField should still return .sensitiveTextField on subsequent checks (cached)")

        // Third check - verify consistency
        let thirdResult = manager.isSensitiveView(view: textField)
        XCTAssertEqual(
            thirdResult, .sensitiveTextField,
            "UITextField should consistently return .sensitiveTextField")
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

    // MARK: - Layer Frame Detection Tests

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
}
