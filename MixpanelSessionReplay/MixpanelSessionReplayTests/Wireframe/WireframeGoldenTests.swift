//
//  WireframeGoldenTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//
//  Coordinate/golden snapshot coverage for the wireframe pipeline, the iOS
//  counterpart to Flutter's `wireframe_golden_test.dart`. Each test lays out a
//  deterministic UIKit tree (manual frames → integer, OS-independent bounds),
//  runs the real collect → emit pipeline, and diffs the serialized result
//  against a checked-in golden. The masking scenarios are the point: a golden
//  that shows `text: null` with the correct `maskDecision` is the regression
//  guard for "a masked view must never leak its text into the wireframe."
//
//  The SwiftUI declarative path (`.mpReplay(...)`) is exercised here through the
//  `MPReplayWrapper` it plants — the exact view the walker keys on — so the
//  declared-text goldens are both deterministic and faithful to production. A
//  real `UIHostingController` end-to-end check lives in
//  `SensitiveViewManagerWireframeTests` (behavioral, not exact-bounds, because
//  SwiftUI text intrinsically sizes its drawing views per OS/font).
//

import SwiftUI
import UIKit
import XCTest

@testable import MixpanelSessionReplay

final class WireframeGoldenTests: XCTestCase {

  private var manager: SensitiveViewManager!
  private var window: UIView!
  private var root: UIView!

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
    root = UIView(frame: window.bounds)
    window.addSubview(root)
  }

  override func tearDown() {
    SensitiveViewManager.reset()
    root = nil
    window = nil
    manager = nil
    super.tearDown()
  }

  // MARK: - Text mask decisions

  func test_golden_textPlain() {
    let label = UILabel(frame: CGRect(x: 20, y: 40, width: 200, height: 30))
    label.text = "Hello world"
    root.addSubview(label)
    assertWireframeGolden(
      manager: manager, root: root, window: window, golden: "wireframe_text_plain.json")
  }

  func test_golden_textAutoMasked() {
    manager.maskAllText = true
    let label = UILabel(frame: CGRect(x: 20, y: 40, width: 200, height: 30))
    label.text = "secret balance"
    root.addSubview(label)
    assertWireframeGolden(
      manager: manager, root: root, window: window, golden: "wireframe_text_auto_masked.json")
  }

  func test_golden_textExplicitMasked() {
    let label = UILabel(frame: CGRect(x: 20, y: 40, width: 200, height: 30))
    label.text = "hidden"
    label.mpReplaySensitive = true
    root.addSubview(label)
    assertWireframeGolden(
      manager: manager, root: root, window: window, golden: "wireframe_text_explicit_masked.json")
  }

  func test_golden_textUnmaskOverridesAuto() {
    manager.maskAllText = true
    let label = UILabel(frame: CGRect(x: 20, y: 40, width: 200, height: 30))
    label.text = "public headline"
    label.mpReplaySensitive = false
    root.addSubview(label)
    assertWireframeGolden(
      manager: manager, root: root, window: window,
      golden: "wireframe_text_unmask_overrides_auto.json")
  }

  func test_golden_textTruncated() {
    let label = UILabel(frame: CGRect(x: 0, y: 0, width: 480, height: 60))
    label.text = String(repeating: "A", count: 80)
    root.addSubview(label)
    assertWireframeGolden(
      manager: manager, root: root, window: window, golden: "wireframe_text_truncated.json")
  }

  // MARK: - Buttons

  func test_golden_buttonWithTitle() {
    let button = UIButton(frame: CGRect(x: 30, y: 100, width: 140, height: 44))
    button.setTitle("Continue", for: .normal)
    root.addSubview(button)
    assertWireframeGolden(
      manager: manager, root: root, window: window, golden: "wireframe_button_with_title.json")
  }

  func test_golden_buttonUnlabeled() {
    let button = UIButton(frame: CGRect(x: 30, y: 100, width: 48, height: 48))
    root.addSubview(button)
    assertWireframeGolden(
      manager: manager, root: root, window: window, golden: "wireframe_button_unlabeled.json")
  }

  func test_golden_buttonAccessibilityLabel() {
    let button = UIButton(frame: CGRect(x: 30, y: 100, width: 48, height: 48))
    button.accessibilityLabel = "settings"
    root.addSubview(button)
    assertWireframeGolden(
      manager: manager, root: root, window: window,
      golden: "wireframe_button_accessibility_label.json")
  }

  /// `useAccessibilityLabelFallback = false` drops tier 3 of the text
  /// precedence chain: the icon button ships as a bare `role + bounds` shell
  /// rather than borrowing its label.
  func test_golden_buttonAccessibilityLabelFallbackOff() {
    let button = UIButton(frame: CGRect(x: 30, y: 100, width: 48, height: 48))
    button.accessibilityLabel = "settings"
    root.addSubview(button)
    assertWireframeGolden(
      manager: manager, root: root, window: window,
      useAccessibilityLabelFallback: false,
      golden: "wireframe_button_accessibility_label_fallback_off.json")
  }

  /// The flag governs only the accessibility tier — declared text is authored,
  /// so it still wins with the fallback off. Mirrors Flutter's
  /// `wireframe_declared_beats_label_fallback_off`.
  func test_golden_declaredBeatsLabelFallbackOff() {
    let button = UIButton(frame: CGRect(x: 30, y: 100, width: 48, height: 48))
    button.accessibilityLabel = "settings"
    button.mpWireframeText = "Open settings"
    root.addSubview(button)
    assertWireframeGolden(
      manager: manager, root: root, window: window,
      useAccessibilityLabelFallback: false,
      golden: "wireframe_declared_beats_label_fallback_off.json")
  }

  // MARK: - Images

  func test_golden_imageUnlabeled() {
    let imageView = UIImageView(frame: CGRect(x: 16, y: 16, width: 64, height: 64))
    root.addSubview(imageView)
    assertWireframeGolden(
      manager: manager, root: root, window: window, golden: "wireframe_image_unlabeled.json")
  }

  func test_golden_imageAccessibilityLabel() {
    let imageView = UIImageView(frame: CGRect(x: 16, y: 16, width: 64, height: 64))
    imageView.accessibilityLabel = "avatar"
    root.addSubview(imageView)
    assertWireframeGolden(
      manager: manager, root: root, window: window,
      golden: "wireframe_image_accessibility_label.json")
  }

  func test_golden_imageAutoMasked() {
    manager.maskAllImages = true
    let imageView = UIImageView(frame: CGRect(x: 16, y: 16, width: 64, height: 64))
    imageView.accessibilityLabel = "avatar"
    root.addSubview(imageView)
    assertWireframeGolden(
      manager: manager, root: root, window: window, golden: "wireframe_image_auto_masked.json")
  }

  // MARK: - Inputs (always masked, textEntry)

  func test_golden_inputAlwaysMasked() {
    let field = UITextField(frame: CGRect(x: 20, y: 60, width: 240, height: 44))
    field.text = "user@example.com"
    root.addSubview(field)
    assertWireframeGolden(
      manager: manager, root: root, window: window, golden: "wireframe_input_always_masked.json")
  }

  /// A text field nested inside an ordinary (non-safe) container is still
  /// reached by the walker and masked to `textEntry` — nesting must not lose
  /// the always-mask guarantee for inputs.
  func test_golden_inputNestedStillMasked() {
    let container = UIView(frame: CGRect(x: 10, y: 20, width: 300, height: 120))
    let field = UITextField(frame: CGRect(x: 10, y: 10, width: 240, height: 44))
    field.text = "secret"
    container.addSubview(field)
    root.addSubview(container)
    assertWireframeGolden(
      manager: manager, root: root, window: window,
      golden: "wireframe_input_nested_still_masked.json")
  }

  /// Documents (and guards) a subtle contract: an explicit unmask override
  /// (`mpReplaySensitive = false`) on a container halts the walk — the whole
  /// subtree is treated as developer-vouched and emits NO wireframe elements,
  /// including any nested text field. This is a developer opt-out, not a leak
  /// (inputs never carry scraped text), but the empty result is intentional and
  /// worth locking so a future traversal change surfaces in review.
  func test_golden_unmaskContainerHaltsSubtree() {
    let container = UIView(frame: CGRect(x: 10, y: 20, width: 300, height: 120))
    container.mpReplaySensitive = false
    let field = UITextField(frame: CGRect(x: 10, y: 10, width: 240, height: 44))
    field.text = "secret"
    let label = UILabel(frame: CGRect(x: 10, y: 60, width: 240, height: 30))
    label.text = "vouched content"
    container.addSubview(field)
    container.addSubview(label)
    root.addSubview(container)
    assertWireframeGolden(
      manager: manager, root: root, window: window,
      golden: "wireframe_unmask_container_halts_subtree.json")
  }

  // MARK: - Geometric leak prevention (Layer 2)

  func test_golden_geometricOverlapNulled() {
    // A sensitive plain view paints a mask rect; a non-sensitive label beneath
    // it must have its text stripped because its bounds intersect that rect.
    let sensitiveBox = UIView(frame: CGRect(x: 0, y: 0, width: 220, height: 100))
    sensitiveBox.mpReplaySensitive = true
    let label = UILabel(frame: CGRect(x: 10, y: 10, width: 180, height: 30))
    label.text = "should not leak"
    root.addSubview(sensitiveBox)
    root.addSubview(label)
    assertWireframeGolden(
      manager: manager, root: root, window: window,
      golden: "wireframe_geometric_overlap_nulled.json")
  }

  // MARK: - Sensitive rules (Layer 3)

  func test_golden_ruleStrip() {
    let label = UILabel(frame: CGRect(x: 10, y: 10, width: 300, height: 30))
    label.text = "my password is hunter2"
    root.addSubview(label)
    assertWireframeGolden(
      manager: manager, root: root, window: window,
      rules: [.strip(text: "password")], golden: "wireframe_rule_strip.json")
  }

  func test_golden_ruleStripRegex() throws {
    let regex = try NSRegularExpression(pattern: #"\d{3}-\d{2}-\d{4}"#)
    let label = UILabel(frame: CGRect(x: 10, y: 10, width: 300, height: 30))
    label.text = "SSN 123-45-6789"
    root.addSubview(label)
    assertWireframeGolden(
      manager: manager, root: root, window: window,
      rules: [.stripRegex(regex)], golden: "wireframe_rule_strip_regex.json")
  }

  func test_golden_ruleRedact() {
    let label = UILabel(frame: CGRect(x: 10, y: 10, width: 320, height: 30))
    label.text = "contact john@example.com now"
    root.addSubview(label)
    assertWireframeGolden(
      manager: manager, root: root, window: window,
      rules: [.redact(text: "john@example.com", replacement: "[EMAIL]")],
      golden: "wireframe_rule_redact.json")
  }

  func test_golden_ruleRedactRegex() throws {
    let regex = try NSRegularExpression(pattern: #"\d{4}"#)
    let label = UILabel(frame: CGRect(x: 10, y: 10, width: 360, height: 30))
    label.text = "card 4111 2222 3333 4444"
    root.addSubview(label)
    assertWireframeGolden(
      manager: manager, root: root, window: window,
      rules: [.redactRegex(regex, replacement: "[####]")],
      golden: "wireframe_rule_redact_regex.json")
  }

  // MARK: - Declared wireframe text (`.mpReplay(wireframeText:)`)

  func test_golden_declaredText() {
    let wrapper = MPReplayWrapper(frame: CGRect(x: 5, y: 6, width: 120, height: 40))
    wrapper.mpWireframeText = "Welcome back"
    root.addSubview(wrapper)
    assertWireframeGolden(
      manager: manager, root: root, window: window, golden: "wireframe_declared_text.json")
  }

  func test_golden_declaredSensitiveTextSurvives() {
    // Masked region AND developer-declared text: the pixels are hidden but the
    // authored label still describes the view. `declared` exempts it from its
    // own geometric mask region.
    let wrapper = MPReplayWrapper(frame: CGRect(x: 0, y: 0, width: 160, height: 40))
    wrapper.mpReplaySensitive = true
    wrapper.mpWireframeText = "monthly spend"
    root.addSubview(wrapper)
    assertWireframeGolden(
      manager: manager, root: root, window: window,
      golden: "wireframe_declared_sensitive_text.json")
  }

  func test_golden_declaredTextRuleStripped() {
    // Layer 3 rules still run over declared text as a safety net.
    let wrapper = MPReplayWrapper(frame: CGRect(x: 5, y: 6, width: 200, height: 40))
    wrapper.mpWireframeText = "password: hunter2"
    root.addSubview(wrapper)
    assertWireframeGolden(
      manager: manager, root: root, window: window,
      rules: [.strip(text: "password")], golden: "wireframe_declared_rule_stripped.json")
  }

  // MARK: - Declared wireframe text on UIKit views (`mpWireframeText`)

  /// A declared label keeps the view's *real* role rather than falling back to
  /// `text` — the walker resolves the role first and only substitutes the text.
  func test_golden_declaredButtonKeepsRole() {
    let button = UIButton(frame: CGRect(x: 30, y: 100, width: 140, height: 44))
    button.setTitle("Continue", for: .normal)
    button.mpWireframeText = "checkout action"
    root.addSubview(button)
    assertWireframeGolden(
      manager: manager, root: root, window: window, golden: "wireframe_declared_button.json")
  }

  /// A `UITextField` is always masked, but a declared label still names the
  /// field ("Card number"). The value the user typed is never scraped, so this
  /// labels the input without leaking it. Matches Android's declared handling
  /// for `EditText`.
  func test_golden_declaredInputLabeled() {
    let field = UITextField(frame: CGRect(x: 20, y: 60, width: 240, height: 44))
    field.text = "4111 1111 1111 1111"
    field.mpWireframeText = "Card number"
    root.addSubview(field)
    assertWireframeGolden(
      manager: manager, root: root, window: window, golden: "wireframe_declared_input.json")
  }

  /// Auto-masked image + declared text: the pixels are masked (`auto`) but the
  /// authored description survives, and the element keeps its `image` role.
  func test_golden_declaredAutoMaskedImage() {
    manager.maskAllImages = true
    let imageView = UIImageView(frame: CGRect(x: 16, y: 16, width: 64, height: 64))
    imageView.accessibilityLabel = "avatar"
    imageView.mpWireframeText = "profile photo"
    root.addSubview(imageView)
    assertWireframeGolden(
      manager: manager, root: root, window: window, golden: "wireframe_declared_mask_image.json")
  }

  /// Declared text on an explicitly unmasked view. The unmask halts the walk
  /// (see `test_golden_unmaskContainerHaltsSubtree`), but the developer-vouched
  /// container's own declared label is still emitted before the walk stops.
  func test_golden_declaredUnmaskCustom() {
    manager.maskAllText = true
    let label = UILabel(frame: CGRect(x: 20, y: 40, width: 200, height: 30))
    label.text = "public headline"
    label.mpReplaySensitive = false
    label.mpWireframeText = "marketing headline"
    root.addSubview(label)
    assertWireframeGolden(
      manager: manager, root: root, window: window,
      golden: "wireframe_declared_unmask_custom.json")
  }

  /// A declared *container* has no role of its own, so it falls back to `text`
  /// and — unlike a role-bearing leaf — does not close the subtree: its real
  /// content is still walked and emitted.
  func test_golden_declaredContainerKeepsChildren() {
    let container = UIView(frame: CGRect(x: 10, y: 20, width: 300, height: 120))
    container.mpWireframeText = "checkout summary"
    let label = UILabel(frame: CGRect(x: 10, y: 10, width: 240, height: 30))
    label.text = "Order total"
    container.addSubview(label)
    root.addSubview(container)
    assertWireframeGolden(
      manager: manager, root: root, window: window,
      golden: "wireframe_declared_container_keeps_children.json")
  }

  // MARK: - SwiftUI declarative path (real UIHostingController)

  /// Coordinate golden for the **real SwiftUI** path — the iOS counterpart to
  /// Compose's `composeLoginForm_matchesGolden`. A login form is rendered
  /// through a live `UIHostingController` hosted in a real `UIWindow`, laid out
  /// by SwiftUI's own engine, then run through the exact production pipeline
  /// (`collectFramesAndWireframes` → `WireframeEmitter`).
  ///
  /// Only **declared** elements are asserted. SwiftUI does not expose its
  /// rendered strings, so scraped content emits null-text shells whose bounds
  /// are intrinsically sized per OS/font — non-deterministic, and already
  /// guarded behaviorally in `SensitiveViewManagerWireframeTests`
  /// (`test_realSwiftUIText_emitsShellWithoutLeakingText`). The
  /// `.mpReplay(wireframeText:)` elements, by contrast, are planted at explicit
  /// `.frame`/`.position` bounds, so they are deterministic and OS-independent —
  /// exactly what a coordinate golden should pin. The password row also asserts
  /// the orthogonal masking contract: `sensitive: true` still emits its declared
  /// text (masking hides pixels, not authored text). Elements are sorted by
  /// (y, x) so walker traversal order can't perturb the golden.
  func test_golden_swiftUIDeclaredLoginForm() {
    let swiftUIWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    let host = UIHostingController(rootView: GoldenLoginForm())
    swiftUIWindow.rootViewController = host
    swiftUIWindow.makeKeyAndVisible()
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))

    let (frames, elements) = manager.collectFramesAndWireframes(
      in: host.view, window: swiftUIWindow)
    let emitter = WireframeEmitter(options: MPWireframesOptions(sensitiveRules: []))
    let processed = emitter.processedElementsForTesting(
      elements: elements, maskBounds: Set(frames.keys))
    let declared =
      processed
      .filter { $0.isDeclared }
      .sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    let viewport = [Int(swiftUIWindow.bounds.width), Int(swiftUIWindow.bounds.height)]
    assertWireframeGolden(
      declared, viewport: viewport, golden: "wireframe_swiftui_declared_login_form.json")
  }

  // MARK: - Complex mixed masking

  func test_golden_complexMixedMasking() {
    let title = UILabel(frame: CGRect(x: 16, y: 20, width: 300, height: 28))
    title.text = "Dashboard"

    let balance = UILabel(frame: CGRect(x: 16, y: 60, width: 200, height: 24))
    balance.text = "$12,345.67"
    balance.mpReplaySensitive = true

    let field = UITextField(frame: CGRect(x: 16, y: 100, width: 260, height: 40))
    field.text = "search"

    let logo = UIImageView(frame: CGRect(x: 300, y: 20, width: 40, height: 40))
    logo.accessibilityLabel = "brand logo"

    let logout = UIButton(frame: CGRect(x: 16, y: 160, width: 120, height: 44))
    logout.setTitle("Log out", for: .normal)

    root.addSubview(title)
    root.addSubview(balance)
    root.addSubview(field)
    root.addSubview(logo)
    root.addSubview(logout)
    assertWireframeGolden(
      manager: manager, root: root, window: window,
      golden: "wireframe_complex_mixed_masking.json")
  }
}

/// Deterministic SwiftUI login form for `test_golden_swiftUIDeclaredLoginForm`.
///
/// Every row is given an explicit `.frame` and absolute `.position` inside a
/// 320×480 host so the `.mpReplay(wireframeText:)` wrappers land at fixed,
/// OS-independent window coordinates. (`.mpReplay` plants its `MPReplayWrapper`
/// as a `.background`, which sizes to the framed view, so the frame drives the
/// declared element's bounds.) The rectangles stand in for the input fields;
/// their scraped shells are null-text and dropped by the test's declared-only
/// filter, so only the four authored labels reach the golden.
private struct GoldenLoginForm: View {
  var body: some View {
    ZStack {
      Text("Sign in")
        .frame(width: 200, height: 40)
        .mpReplay(wireframeText: "Sign in")
        .position(x: 160, y: 60)

      RoundedRectangle(cornerRadius: 8)
        .frame(width: 260, height: 44)
        .mpReplay(wireframeText: "Email")
        .position(x: 160, y: 130)

      RoundedRectangle(cornerRadius: 8)
        .frame(width: 260, height: 44)
        .mpReplay(sensitive: true, wireframeText: "Password")
        .position(x: 160, y: 190)

      Text("Log in")
        .frame(width: 200, height: 44)
        .mpReplay(wireframeText: "Log in")
        .position(x: 160, y: 260)
    }
    // Ignore the safe area so `.position` is measured from the window origin,
    // not the safe-area inset. Without this the host applies the running
    // simulator's top inset (e.g. 59pt on iPhone 16) to every element, which
    // would device-model-pin the golden. Ignoring it keeps the declared bounds
    // portable across simulators — matching the UIKit goldens' independence.
    // (`.edgesIgnoringSafeArea` rather than `.ignoresSafeArea()`: the SDK's
    // deployment target is iOS 13, and the latter is iOS 14+.)
    .edgesIgnoringSafeArea(.all)
  }
}
