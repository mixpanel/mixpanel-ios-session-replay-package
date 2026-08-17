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

  // MARK: - useAccessibilityLabelFallback

  func test_accessibilityFallbackOff_imageShipsAsTextlessShell() {
    manager.useAccessibilityLabelFallback = false
    let root = UIView(frame: window.bounds)
    let iv = UIImageView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
    iv.accessibilityLabel = "avatar"
    root.addSubview(iv)
    window.addSubview(root)

    let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes
    XCTAssertEqual(elements.count, 1, "the role + bounds shell is always kept")
    XCTAssertEqual(elements[0].role, .image)
    XCTAssertNil(elements[0].text)
    XCTAssertEqual(elements[0].decision, .none)
  }

  func test_accessibilityFallbackOff_buttonKeepsItsOwnTitle() {
    // Tier 2 (the view's own rendered text) is unaffected by the flag — only
    // tier 3 is gated.
    manager.useAccessibilityLabelFallback = false
    let root = UIView(frame: window.bounds)
    let button = UIButton(frame: CGRect(x: 0, y: 0, width: 120, height: 44))
    button.setTitle("Continue", for: .normal)
    button.accessibilityLabel = "continue button"
    root.addSubview(button)
    window.addSubview(root)

    let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes
    let buttons = elements.filter { $0.role == .button }
    XCTAssertEqual(buttons.count, 1)
    XCTAssertEqual(buttons[0].text, "Continue")
  }

  func test_accessibilityFallbackOff_declaredTextStillWins() {
    manager.useAccessibilityLabelFallback = false
    let root = UIView(frame: window.bounds)
    let button = UIButton(frame: CGRect(x: 0, y: 0, width: 48, height: 48))
    button.accessibilityLabel = "settings"
    button.mpWireframeText = "Open settings"
    root.addSubview(button)
    window.addSubview(root)

    let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes
    let buttons = elements.filter { $0.role == .button }
    XCTAssertEqual(buttons.count, 1)
    XCTAssertEqual(buttons[0].text, "Open settings")
    XCTAssertEqual(buttons[0].decision, .declared)
  }

  // MARK: - Declared text on UIKit views (`mpWireframeText`)

  func test_declaredText_onUIKitView_keepsRealRole() {
    let root = UIView(frame: window.bounds)
    let button = UIButton(frame: CGRect(x: 0, y: 0, width: 120, height: 44))
    button.setTitle("Continue", for: .normal)
    button.mpWireframeText = "checkout action"
    root.addSubview(button)
    window.addSubview(root)

    let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes
    let buttons = elements.filter { $0.role == .button }
    XCTAssertEqual(buttons.count, 1)
    XCTAssertEqual(buttons[0].text, "checkout action", "declared text outranks the title")
    XCTAssertEqual(buttons[0].decision, .declared)
  }

  /// An input is always masked, but a declared label names the field. The typed
  /// value is still never scraped. Matches Android's declared handling for
  /// `EditText`.
  func test_declaredText_onTextField_labelsInputWithoutLeakingValue() {
    let root = UIView(frame: window.bounds)
    let field = UITextField(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
    field.text = "4111 1111 1111 1111"
    field.mpWireframeText = "Card number"
    root.addSubview(field)
    window.addSubview(root)

    let result = manager.collectFramesAndWireframes(in: root, window: window)
    XCTAssertFalse(result.frames.isEmpty, "a text field must still paint a mask region")
    XCTAssertEqual(result.wireframes.count, 1)
    XCTAssertEqual(result.wireframes[0].role, .input)
    XCTAssertEqual(result.wireframes[0].text, "Card number")
    XCTAssertEqual(result.wireframes[0].decision, .declared)
  }

  func test_declaredText_onAutoMaskedView_survivesMasking() {
    manager.maskAllImages = true
    let root = UIView(frame: window.bounds)
    let iv = UIImageView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
    iv.mpWireframeText = "profile photo"
    root.addSubview(iv)
    window.addSubview(root)

    let result = manager.collectFramesAndWireframes(in: root, window: window)
    XCTAssertFalse(result.frames.isEmpty, "the image must still be masked")
    XCTAssertEqual(result.wireframes.count, 1)
    XCTAssertEqual(result.wireframes[0].role, .image)
    XCTAssertEqual(result.wireframes[0].text, "profile photo")
    XCTAssertEqual(result.wireframes[0].decision, .declared)
  }

  /// A declared *container* has no role of its own, so it does not close the
  /// subtree — its real content is still walked.
  func test_declaredText_onContainer_doesNotSuppressChildren() {
    let root = UIView(frame: window.bounds)
    let container = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 120))
    container.mpWireframeText = "checkout summary"
    let label = UILabel(frame: CGRect(x: 10, y: 10, width: 200, height: 30))
    label.text = "Order total"
    container.addSubview(label)
    root.addSubview(container)
    window.addSubview(root)

    let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes
    XCTAssertEqual(elements.count, 2)
    XCTAssertTrue(elements.contains { $0.text == "checkout summary" && $0.decision == .declared })
    XCTAssertTrue(elements.contains { $0.text == "Order total" && $0.decision == .none })
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
  /// Contract: SwiftUI text is emitted as a role + bounds *shell* with no text.
  /// SwiftUI does not expose its rendered `Text` reliably — it lives on
  /// `_UIHostingView._rootView`, not the leaf render node the walker reaches
  /// (leaf `SwiftUI.CGDrawingView` on iOS <=18, `CGDrawingLayer` on iOS 26+
  /// carry only Swift-value-typed ivars). So the walker must never surface the
  /// rendered string, and it must never accidentally leak it either. Readable
  /// text for SwiftUI is supplied by the developer via `.mpReplay(wireframeText:)`.
  func test_realSwiftUIText_emitsShellWithoutLeakingText() throws {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    let host = UIHostingController(rootView: Text("Welcome"))
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))

    let result = manager.collectFramesAndWireframes(in: host.view, window: window)

    // The rendered string must never appear on any emitted element.
    XCTAssertFalse(
      result.wireframes.contains { $0.text == "Welcome" },
      "SwiftUI Text content must not leak into the wireframe")
    // Any SwiftUI-derived text shell is emitted with nil text.
    for element in result.wireframes where element.role == .text {
      XCTAssertNil(element.text, "SwiftUI text shell must carry no text")
    }
  }

  /// End-to-end SwiftUI check of the *real* `.mpReplay(wireframeText:)`
  /// modifier (not `MPReplayWrapper` planted directly): the modifier must
  /// install its background wrapper in the live SwiftUI hierarchy so the walker
  /// surfaces the developer-declared text. Behavioral only — SwiftUI sizes the
  /// hosted `Text` intrinsically, so exact bounds are not asserted here; the
  /// deterministic bounds live in `WireframeGoldenTests`.
  func test_realSwiftUI_mpReplayModifier_emitsDeclaredText() throws {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    let host = UIHostingController(rootView: Text("Welcome").mpReplay(wireframeText: "Welcome"))
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))

    let result = manager.collectFramesAndWireframes(in: host.view, window: window)
    let declared = result.wireframes.filter { $0.isDeclared }
    XCTAssertEqual(
      declared.count, 1, "the .mpReplay modifier must plant exactly one declared element")
    XCTAssertEqual(declared[0].role, .text)
    XCTAssertEqual(declared[0].text, "Welcome")
    XCTAssertEqual(declared[0].decision, .declared)
    // No scraped text should ever appear on the non-declared shells.
    for element in result.wireframes where !element.isDeclared && element.role == .text {
      XCTAssertNil(element.text, "SwiftUI text shell must carry no scraped text")
    }
  }

  // MARK: - Unified `.mpReplay(sensitive:text:)` opt-in (MPReplayWrapper)

  /// `.mpReplay(wireframeText:)` plants an MPReplayWrapper carrying the declared
  /// text. The walker emits it as a `.text` element with decision `.declared`.
  func test_mpReplayWrapper_withText_emitsDeclaredText() {
    let root = UIView(frame: window.bounds)
    let wrapper = MPReplayWrapper(frame: CGRect(x: 5, y: 6, width: 120, height: 40))
    wrapper.mpWireframeText = "Welcome"
    root.addSubview(wrapper)
    window.addSubview(root)

    let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes
    let texts = elements.filter { $0.role == .text }
    XCTAssertEqual(texts.count, 1)
    XCTAssertEqual(texts[0].text, "Welcome")
    XCTAssertEqual(texts[0].decision, .declared)
    XCTAssertEqual(texts[0].w, 120)
    XCTAssertEqual(texts[0].h, 40)
  }

  /// `.mpReplay(sensitive: true, wireframeText:)` is orthogonal: the region is
  /// masked (opaque rectangle) AND the customer-declared text is still emitted,
  /// because it is authored rather than scraped. The `.declared` decision lets
  /// it survive the geometric strip against its own mask region downstream.
  func test_mpReplayWrapper_sensitiveWithText_masksAndEmitsDeclaredText() {
    let root = UIView(frame: window.bounds)
    let wrapper = MPReplayWrapper(frame: CGRect(x: 0, y: 0, width: 120, height: 40))
    wrapper.mpReplaySensitive = true
    wrapper.mpWireframeText = "monthly spend"
    root.addSubview(wrapper)
    window.addSubview(root)

    let result = manager.collectFramesAndWireframes(in: root, window: window)
    XCTAssertFalse(result.frames.isEmpty, "sensitive wrapper must produce a mask region")
    let texts = result.wireframes.filter { $0.role == .text }
    XCTAssertEqual(texts.count, 1)
    XCTAssertEqual(texts[0].text, "monthly spend")
    XCTAssertEqual(texts[0].decision, .declared)
  }

  /// The `.mpReplay(text:)` background is a *sibling* of SwiftUI's drawing view,
  /// so an empty `.text` shell can be emitted at the same bounds. The dedup pass
  /// must drop that empty shell in favor of the declared-text element.
  func test_mpReplayWrapper_siblingEmptyTextShell_isDeduped() {
    let bounds = CGRect(x: 10, y: 10, width: 100, height: 30)
    let root = UIView(frame: window.bounds)
    // Empty-text label stands in for SwiftUI's textless drawing-view shell.
    let shell = UILabel(frame: bounds)
    shell.text = nil
    let wrapper = MPReplayWrapper(frame: bounds)
    wrapper.mpWireframeText = "Hello"
    root.addSubview(shell)
    root.addSubview(wrapper)
    window.addSubview(root)

    let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes
    let texts = elements.filter { $0.role == .text }
    XCTAssertEqual(texts.count, 1, "empty sibling shell should be deduped away")
    XCTAssertEqual(texts[0].text, "Hello")
  }

  /// Dedup must not touch a *masked* empty shell that happens to share bounds —
  /// safety takes precedence over collapsing.
  func test_mpReplayWrapper_dedupPreservesMaskedShell() {
    manager.maskAllText = true
    let bounds = CGRect(x: 10, y: 10, width: 100, height: 30)
    let root = UIView(frame: window.bounds)
    let masked = UILabel(frame: bounds)
    masked.text = "auto-masked"
    let wrapper = MPReplayWrapper(frame: bounds)
    wrapper.mpWireframeText = "Hello"
    root.addSubview(masked)
    root.addSubview(wrapper)
    window.addSubview(root)

    let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes
    let texts = elements.filter { $0.role == .text }
    // Declared text element + the masked (.auto, nil text) shell both survive.
    XCTAssertEqual(texts.count, 2)
    XCTAssertTrue(texts.contains { $0.text == "Hello" && $0.decision == .declared })
    XCTAssertTrue(texts.contains { $0.text == nil && $0.decision == .auto })
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
