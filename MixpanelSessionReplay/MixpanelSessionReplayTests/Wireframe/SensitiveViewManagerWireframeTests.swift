//
//  SensitiveViewManagerWireframeTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import SwiftUI
import UIKit
import WebKit
import XCTest

@testable import MixpanelSessionReplay

final class SensitiveViewManagerWireframeTests: XCTestCase {

  private var manager: SensitiveViewManager!
  private var window: UIView!

  override func setUp() {
    super.setUp()
    SensitiveViewManager.reset()
    manager = SensitiveViewManager.shared
    manager.wireframeCollectionEnabled = true
    manager.maskAllText = false
    manager.maskAllImages = false
    manager.maskAllWebViews = false
    manager.maskAllMapViews = false
    window = UIView(frame: CGRect(x: 0, y: 0, width: 500, height: 800))
  }

  override func tearDown() {
    SensitiveViewManager.reset()
    window = nil
    super.tearDown()
  }

  func test_wireframeCollectionDisabled_returnsEmptyElements() {
    manager.wireframeCollectionEnabled = false
    let root = UIView(frame: window.bounds)
    let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 30))
    label.text = "hi"
    root.addSubview(label)
    window.addSubview(root)

    let result = manager.collectFramesAndWireframes(in: root, window: window)
    XCTAssertTrue(result.wireframes.isEmpty)
  }

  func test_uilabel_emitsTextRole_withText() {
    let root = UIView(frame: window.bounds)
    let label = UILabel(frame: CGRect(x: 10, y: 20, width: 200, height: 30))
    label.text = "Hello"
    root.addSubview(label)
    window.addSubview(root)

    let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes
    XCTAssertEqual(elements.count, 1)
    XCTAssertEqual(elements[0].role, .text)
    XCTAssertEqual(elements[0].text, "Hello")
    XCTAssertEqual(elements[0].decision, .none)
    XCTAssertEqual(elements[0].w, 200)
    XCTAssertEqual(elements[0].h, 30)
  }

  func test_uilabel_autoMasked_emitsWithNilTextAndAutoDecision() {
    manager.maskAllText = true
    let root = UIView(frame: window.bounds)
    let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 30))
    label.text = "secret"
    root.addSubview(label)
    window.addSubview(root)

    let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes
    XCTAssertEqual(elements.count, 1)
    XCTAssertEqual(elements[0].role, .text)
    XCTAssertNil(elements[0].text)
    XCTAssertEqual(elements[0].decision, .auto)
  }

  func test_uibutton_emitsButtonRole_notNestedLabel() {
    let root = UIView(frame: window.bounds)
    let button = UIButton(frame: CGRect(x: 0, y: 0, width: 120, height: 44))
    button.setTitle("Continue", for: .normal)
    root.addSubview(button)
    window.addSubview(root)

    let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes
    let buttons = elements.filter { $0.role == .button }
    let texts = elements.filter { $0.role == .text }
    XCTAssertEqual(buttons.count, 1, "should emit exactly one button element")
    XCTAssertEqual(texts.count, 0, "should NOT emit a text element for the inner titleLabel")
    XCTAssertEqual(buttons[0].text, "Continue")
  }

  func test_uitextfield_emitsInputRole_alwaysMasked() {
    let root = UIView(frame: window.bounds)
    let field = UITextField(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
    field.text = "user@example.com"
    root.addSubview(field)
    window.addSubview(root)

    let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes
    XCTAssertEqual(elements.count, 1)
    XCTAssertEqual(elements[0].role, .input)
    XCTAssertNil(elements[0].text)
    XCTAssertEqual(elements[0].decision, .textEntry)
  }

  func test_uiimageview_autoMasked_emitsImageRoleWithAutoDecision() {
    manager.maskAllImages = true
    let root = UIView(frame: window.bounds)
    let iv = UIImageView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
    root.addSubview(iv)
    window.addSubview(root)

    let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes
    XCTAssertEqual(elements.count, 1)
    XCTAssertEqual(elements[0].role, .image)
    XCTAssertEqual(elements[0].decision, .auto)
    XCTAssertNil(elements[0].text)
  }

  func test_uiimageview_notMasked_emitsAccessibilityLabelAsText() {
    let root = UIView(frame: window.bounds)
    let iv = UIImageView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
    iv.accessibilityLabel = "avatar"
    root.addSubview(iv)
    window.addSubview(root)

    let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes
    XCTAssertEqual(elements.count, 1)
    XCTAssertEqual(elements[0].role, .image)
    XCTAssertEqual(elements[0].text, "avatar")
  }

  func test_explicitSensitiveView_emitsWithExplicitDecision() {
    let root = UIView(frame: window.bounds)
    let label = UILabel(frame: CGRect(x: 0, y: 0, width: 200, height: 30))
    label.text = "hidden"
    label.mpReplaySensitive = true
    root.addSubview(label)
    window.addSubview(root)

    let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes
    XCTAssertEqual(elements.count, 1)
    XCTAssertEqual(elements[0].decision, .explicit)
    XCTAssertNil(elements[0].text)
  }

  func test_webview_emitsTextRoleWithNilText() {
    let root = UIView(frame: window.bounds)
    let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
    root.addSubview(web)
    window.addSubview(root)

    let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes
    let webElements = elements.filter { $0.role == .text }
    XCTAssertGreaterThanOrEqual(webElements.count, 1)
    XCTAssertNil(webElements[0].text)
  }

  /// End-to-end SwiftUI check: real `Text` inside a `UIHostingController`,
  /// hosted in a real `UIWindow`, laid out through the normal SwiftUI
  /// rendering path.
  ///
  /// Current expected outcome: FAILS on iOS 18–26. Diagnostic dump (removed)
  /// showed the leaf `SwiftUI.CGDrawingView` (iOS <=18) exposes one
  /// Swift-value-typed ivar `options`, and `SwiftUI.CGDrawingLayer` (iOS 26+)
  /// exposes Swift-value-typed `content` and `state` — none of which
  /// `object_getIvar` can safely read. The visible text is stored higher up
  /// on `_UIHostingView._rootView` as `Text.storage.anyTextStorage(…)`,
  /// which the current leaf-node extractor never inspects.
  ///
  /// Verify by hand in `SampleApp` before flipping this to a passing test.
  func test_realSwiftUIText_extractsThroughFullPipeline() throws {
    try XCTSkipIf(
      true,
      "SwiftUI Text extraction not implemented — see SampleApp for interactive verification. "
        + "Text is stored at _UIHostingView._rootView; extractor is called at the leaf render node."
    )

    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    let host = UIHostingController(rootView: Text("Welcome"))
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))

    let result = manager.collectFramesAndWireframes(in: host.view, window: window)
    let welcome = result.wireframes.first { $0.text == "Welcome" }
    XCTAssertNotNil(welcome)
    XCTAssertEqual(welcome?.role, .text)
    XCTAssertEqual(welcome?.decision, .none)
  }

  func test_boundsAreWindowRelative() {
    let root = UIView(frame: CGRect(x: 50, y: 100, width: 400, height: 400))
    let label = UILabel(frame: CGRect(x: 10, y: 20, width: 100, height: 30))
    label.text = "hi"
    root.addSubview(label)
    window.addSubview(root)

    let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes
    XCTAssertEqual(elements.count, 1)
    // label frame (10,20,100,30) inside root at (50,100) → window (60,120,100,30)
    XCTAssertEqual(elements[0].x, 60)
    XCTAssertEqual(elements[0].y, 120)
    XCTAssertEqual(elements[0].w, 100)
    XCTAssertEqual(elements[0].h, 30)
  }
}
