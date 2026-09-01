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

        let result = manager.walkHierarchy(in: root, window: window)
        XCTAssertTrue(result.wireframes.isEmpty)
    }

    func test_uilabel_emitsTextRole_withText() {
        let root = UIView(frame: window.bounds)
        let label = UILabel(frame: CGRect(x: 10, y: 20, width: 200, height: 30))
        label.text = "Hello"
        root.addSubview(label)
        window.addSubview(root)

        let elements = manager.walkHierarchy(in: root, window: window).wireframes
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

        let elements = manager.walkHierarchy(in: root, window: window).wireframes
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

        let elements = manager.walkHierarchy(in: root, window: window).wireframes
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

        let elements = manager.walkHierarchy(in: root, window: window).wireframes
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

        let elements = manager.walkHierarchy(in: root, window: window).wireframes
        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(elements[0].role, .image)
        XCTAssertEqual(elements[0].decision, .auto)
        XCTAssertNil(elements[0].text)
    }

    // MARK: - useAccessibilityLabelFallback

    func test_accessibilityFallbackOff_imageShipsAsTextlessShell() {
        manager.wireframeClassifier.useAccessibilityLabelFallback = false
        let root = UIView(frame: window.bounds)
        let iv = UIImageView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        iv.accessibilityLabel = "avatar"
        root.addSubview(iv)
        window.addSubview(root)

        let elements = manager.walkHierarchy(in: root, window: window).wireframes
        XCTAssertEqual(elements.count, 1, "the role + bounds shell is always kept")
        XCTAssertEqual(elements[0].role, .image)
        XCTAssertNil(elements[0].text)
        XCTAssertEqual(elements[0].decision, .none)
    }

    func test_accessibilityFallbackOff_buttonKeepsItsOwnTitle() {
        // Tier 2 (the view's own rendered text) is unaffected by the flag — only
        // tier 3 is gated.
        manager.wireframeClassifier.useAccessibilityLabelFallback = false
        let root = UIView(frame: window.bounds)
        let button = UIButton(frame: CGRect(x: 0, y: 0, width: 120, height: 44))
        button.setTitle("Continue", for: .normal)
        button.accessibilityLabel = "continue button"
        root.addSubview(button)
        window.addSubview(root)

        let elements = manager.walkHierarchy(in: root, window: window).wireframes
        let buttons = elements.filter { $0.role == .button }
        XCTAssertEqual(buttons.count, 1)
        XCTAssertEqual(buttons[0].text, "Continue")
    }

    func test_accessibilityFallbackOff_declaredTextStillWins() {
        manager.wireframeClassifier.useAccessibilityLabelFallback = false
        let root = UIView(frame: window.bounds)
        let button = UIButton(frame: CGRect(x: 0, y: 0, width: 48, height: 48))
        button.accessibilityLabel = "settings"
        button.mpWireframeText = "Open settings"
        root.addSubview(button)
        window.addSubview(root)

        let elements = manager.walkHierarchy(in: root, window: window).wireframes
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

        let elements = manager.walkHierarchy(in: root, window: window).wireframes
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

        let result = manager.walkHierarchy(in: root, window: window)
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

        let result = manager.walkHierarchy(in: root, window: window)
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

        let elements = manager.walkHierarchy(in: root, window: window).wireframes
        XCTAssertEqual(elements.count, 2)
        XCTAssertTrue(elements.contains { $0.text == "checkout summary" && $0.decision == .declared })
        XCTAssertTrue(elements.contains { $0.text == "Order total" && $0.decision == .none })
    }

    func test_uiimageview_notMasked_emitsAccessibilityLabelAsText() {
        // Opted in explicitly — the shipped default is off, and this case is about
        // tier 3 of the text chain.
        manager.wireframeClassifier.useAccessibilityLabelFallback = true
        let root = UIView(frame: window.bounds)
        let iv = UIImageView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        iv.accessibilityLabel = "avatar"
        root.addSubview(iv)
        window.addSubview(root)

        let elements = manager.walkHierarchy(in: root, window: window).wireframes
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

        let elements = manager.walkHierarchy(in: root, window: window).wireframes
        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(elements[0].decision, .explicit)
        XCTAssertNil(elements[0].text)
    }

    /// A `WKWebView` contributes no wireframe element at all.
    ///
    /// Web content renders out of process, so the SDK can read none of it and any role would
    /// be a guess. An earlier pass classified it `.text`, which shipped a textless full-screen
    /// `text` shell — that reads to a summary as "text we failed to extract" rather than "not
    /// our content". Android's `classifyAndroidView` has no `WebView` branch and Flutter does
    /// not classify platform views, so emitting nothing is also the parity behaviour.
    ///
    /// Masking is a separate concern and unaffected: see
    /// `SensitiveViewManagerTests.testSensitiveViewDetection_WebView`.
    func test_webview_emitsNoWireframeElement() {
        let root = UIView(frame: window.bounds)
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        root.addSubview(web)
        window.addSubview(root)

        let elements = manager.walkHierarchy(in: root, window: window).wireframes

        XCTAssertTrue(
            elements.isEmpty,
            "a web view and its WebKit internals must contribute no elements, got "
                + "\(elements.map(\.role))")
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
    /// text for SwiftUI is supplied by the developer via `.mpWireframeText(_:)`.
    func test_realSwiftUIText_emitsShellWithoutLeakingText() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let host = UIHostingController(rootView: Text("Welcome"))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        let result = manager.walkHierarchy(in: host.view, window: window)

        // The rendered string must never appear on any emitted element.
        XCTAssertFalse(
            result.wireframes.contains { $0.text == "Welcome" },
            "SwiftUI Text content must not leak into the wireframe")
        // Any SwiftUI-derived text shell is emitted with nil text.
        for element in result.wireframes where element.role == .text {
            XCTAssertNil(element.text, "SwiftUI text shell must carry no text")
        }
    }

    /// End-to-end SwiftUI check of the *real* `.mpWireframeText(_:)`
    /// modifier (not `MPReplayWrapper` planted directly): the modifier must
    /// install its background wrapper in the live SwiftUI hierarchy so the walker
    /// surfaces the developer-declared text. Behavioral only — SwiftUI sizes the
    /// hosted `Text` intrinsically, so exact bounds are not asserted here; the
    /// deterministic bounds live in `WireframeGoldenTests`.
    func test_realSwiftUI_mpReplayModifier_emitsDeclaredText() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let host = UIHostingController(rootView: Text("Welcome").mpWireframeText("Welcome"))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        let result = manager.walkHierarchy(in: host.view, window: window)
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

    // MARK: - Unified `.mpReplaySensitive(_:)` / `.mpWireframeText(_:)` opt-in (MPReplayWrapper)

    /// `.mpWireframeText(_:)` plants an MPReplayWrapper carrying the declared
    /// text. The walker emits it as a `.text` element with decision `.declared`.
    func test_mpReplayWrapper_withText_emitsDeclaredText() {
        let root = UIView(frame: window.bounds)
        let wrapper = MPReplayWrapper(frame: CGRect(x: 5, y: 6, width: 120, height: 40))
        wrapper.mpWireframeText = "Welcome"
        root.addSubview(wrapper)
        window.addSubview(root)

        let elements = manager.walkHierarchy(in: root, window: window).wireframes
        let texts = elements.filter { $0.role == .text }
        XCTAssertEqual(texts.count, 1)
        XCTAssertEqual(texts[0].text, "Welcome")
        XCTAssertEqual(texts[0].decision, .declared)
        XCTAssertEqual(texts[0].w, 120)
        XCTAssertEqual(texts[0].h, 40)
    }

    /// Masking and declared text are orthogonal: the region is masked (opaque
    /// rectangle) AND the customer-declared text is still emitted, because it is
    /// authored rather than scraped. The `.declared` decision lets it survive the
    /// geometric strip against its own mask region downstream.
    ///
    /// Both flags are set on a single wrapper here. Chaining
    /// `.mpReplaySensitive(true).mpWireframeText(…)` plants two wrappers at
    /// identical bounds instead; only the text-bearing one emits an element, so
    /// the outcome asserted below is the same either way.
    func test_mpReplayWrapper_sensitiveWithText_masksAndEmitsDeclaredText() {
        let root = UIView(frame: window.bounds)
        let wrapper = MPReplayWrapper(frame: CGRect(x: 0, y: 0, width: 120, height: 40))
        wrapper.mpReplaySensitive = true
        wrapper.mpWireframeText = "monthly spend"
        root.addSubview(wrapper)
        window.addSubview(root)

        let result = manager.walkHierarchy(in: root, window: window)
        XCTAssertFalse(result.frames.isEmpty, "sensitive wrapper must produce a mask region")
        let texts = result.wireframes.filter { $0.role == .text }
        XCTAssertEqual(texts.count, 1)
        XCTAssertEqual(texts[0].text, "monthly spend")
        XCTAssertEqual(texts[0].decision, .declared)
    }

    /// The `.mpWireframeText(_:)` background is a *sibling* of SwiftUI's drawing view,
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

        let elements = manager.walkHierarchy(in: root, window: window).wireframes
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

        let elements = manager.walkHierarchy(in: root, window: window).wireframes
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

        let elements = manager.walkHierarchy(in: root, window: window).wireframes
        XCTAssertEqual(elements.count, 1)
        // label frame (10,20,100,30) inside root at (50,100) → window (60,120,100,30)
        XCTAssertEqual(elements[0].x, 60)
        XCTAssertEqual(elements[0].y, 120)
        XCTAssertEqual(elements[0].w, 100)
        XCTAssertEqual(elements[0].h, 30)
    }

    // MARK: - addSensitiveClass reports EXPLICIT, masks the same pixels

    /// `addSensitiveClass` reporting EXPLICIT rather than AUTO changes the label on
    /// the decision, not the masking. Pins that by masking the same view two ways —
    /// once by class registration, once by auto-detection — and asserting the mask
    /// rects come out identical. The painter fills every rect in the set without
    /// reading its decision, so equal rects means equal pixels.
    func testRegisteredClass_reportsExplicitButMasksIdentically() {
        func maskRects(registerClass: Bool) -> Set<HashableRect> {
            SensitiveViewManager.reset()
            let mgr = SensitiveViewManager.shared
            mgr.wireframeCollectionEnabled = true
            mgr.maskAllText = !registerClass
            mgr.maskAllImages = false
            mgr.maskAllWebViews = false
            mgr.maskAllMapViews = false
            if registerClass { mgr.addSensitiveClass(CardNumberLabelProbe.self) }

            let win = UIView(frame: CGRect(x: 0, y: 0, width: 500, height: 800))
            let root = UIView(frame: win.bounds)
            let card = CardNumberLabelProbe(frame: CGRect(x: 16, y: 24, width: 240, height: 64))
            card.text = "4111 1111 1111 1111"
            root.addSubview(card)
            win.addSubview(root)
            return Set(mgr.walkHierarchy(in: root, window: win).frames.keys)
        }

        let viaClass = maskRects(registerClass: true)
        let viaAuto = maskRects(registerClass: false)

        XCTAssertFalse(viaClass.isEmpty, "a registered class must still mask")
        XCTAssertEqual(viaClass, viaAuto, "the decision label changes; the masked pixels do not")
    }

    /// The reported decision itself: EXPLICIT for a registered class, AUTO for a
    /// type match. Same taxonomy Android uses.
    func testRegisteredClass_wireDecisionIsExplicitNotAuto() {
        manager.addSensitiveClass(CardNumberLabelProbe.self)
        let root = UIView(frame: window.bounds)
        let card = CardNumberLabelProbe(frame: CGRect(x: 16, y: 24, width: 240, height: 64))
        card.text = "4111 1111 1111 1111"
        root.addSubview(card)
        window.addSubview(root)

        let elements = manager.walkHierarchy(in: root, window: window).wireframes
        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(elements[0].decision, .explicit)
        XCTAssertNil(elements[0].text)
    }

    // MARK: - Unmasked subtrees are described, not masked

    /// Builds a container marked `mpReplaySensitive = false` holding content that
    /// auto-masking would otherwise hide, an always-masked text field, and an
    /// explicitly re-masked label — plus an ordinary sibling *outside* the
    /// container, so the mask set is non-empty and a walk that perturbed it would
    /// be caught rather than passing vacuously.
    private func makeUnmaskedSubtree() -> UIView {
        let root = UIView(frame: window.bounds)
        let container = UIView(frame: CGRect(x: 10, y: 20, width: 300, height: 200))
        container.mpReplaySensitive = false

        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 240, height: 30))
        label.text = "vouched content"

        let field = UITextField(frame: CGRect(x: 10, y: 50, width: 240, height: 44))
        field.text = "secret"

        let reMasked = UILabel(frame: CGRect(x: 10, y: 110, width: 240, height: 30))
        reMasked.text = "still private"
        reMasked.mpReplaySensitive = true

        container.addSubview(label)
        container.addSubview(field)
        container.addSubview(reMasked)
        root.addSubview(container)

        let outside = UILabel(frame: CGRect(x: 10, y: 300, width: 240, height: 30))
        outside.text = "ordinary masked content"
        root.addSubview(outside)

        window.addSubview(root)
        return root
    }

    /// The guarantee that lets the walk descend into an unmasked subtree at all:
    /// turning wireframe collection on must not move a single pixel. The mask
    /// frames drive the screenshot, so they have to come out identical whether or
    /// not the wireframe walk ran.
    func testUnmaskSubtree_maskDecisionsUnchanged() {
        manager.maskAllText = true

        manager.wireframeCollectionEnabled = false
        let withoutWireframes = manager.walkHierarchy(in: makeUnmaskedSubtree(), window: window).frames

        SensitiveViewManager.reset()
        manager = SensitiveViewManager.shared
        manager.maskAllText = true
        manager.wireframeCollectionEnabled = true
        window = UIView(frame: CGRect(x: 0, y: 0, width: 500, height: 800))
        let withWireframes = manager.walkHierarchy(in: makeUnmaskedSubtree(), window: window).frames

        XCTAssertFalse(
            withoutWireframes.isEmpty,
            "fixture must mask something outside the unmasked subtree, or the check below is vacuous")
        XCTAssertEqual(
            withWireframes, withoutWireframes,
            "descending into an unmasked subtree for wireframes must not change what the screenshot masks"
        )
    }

    /// The coverage fix: an explicitly-unmasked container is the content the
    /// developer positively vouched for, so it is described rather than skipped.
    func testUnmaskSubtree_emitsChildrenWithText() {
        manager.maskAllText = true
        let elements = manager.walkHierarchy(in: makeUnmaskedSubtree(), window: window).wireframes

        // The vouched label ships its real text even though maskAllText is on —
        // an unmask overrides auto-masking for the pixels, so it does here too.
        XCTAssertTrue(
            elements.contains {
                $0.role == .text && $0.text == "vouched content" && $0.decision == .none
            },
            "unmasked label should ship its text")
    }

    /// A nested text field keeps the always-masked guarantee in the wireframe: the
    /// shell ships so the form's structure is legible, the typed value never does.
    func testUnmaskSubtree_nestedTextFieldStaysTextless() {
        let elements = manager.walkHierarchy(in: makeUnmaskedSubtree(), window: window).wireframes

        let inputs = elements.filter { $0.role == .input }
        XCTAssertEqual(inputs.count, 1)
        XCTAssertNil(inputs[0].text, "a text field's value never ships, safe ancestor or not")
        XCTAssertEqual(inputs[0].decision, .textEntry)
        XCTAssertFalse(
            elements.contains { $0.text == "secret" }, "the typed value must not appear anywhere")
    }

    /// An unmask overrides *auto* masking, not a developer naming a view. An
    /// explicit `mpReplaySensitive = true` nested inside still reports a textless
    /// shell — matching Android, where an explicit mask keeps `shouldMask` set
    /// under a safe ancestor.
    func testUnmaskSubtree_nestedExplicitMaskStaysTextless() {
        let elements = manager.walkHierarchy(in: makeUnmaskedSubtree(), window: window).wireframes

        XCTAssertFalse(
            elements.contains { $0.text == "still private" },
            "an explicit mask inside an unmask must not have its text scraped")
        XCTAssertTrue(
            elements.contains { $0.role == .text && $0.text == nil && $0.decision == .explicit },
            "it should still ship as a textless shell so the layout survives")
    }

    // MARK: - Masked subtree: text is stripped on provenance, not geometry

    /// A small masked parent whose child is laid out entirely OUTSIDE its bounds.
    ///
    /// No scrolling is involved: the child simply has a frame beyond the parent, which
    /// is all it takes. `getFrame(for:in:)` converts the layer's bounds to *window*
    /// coordinates and intersects only with the window — it never consults the ancestor
    /// clip chain — and `isVisible()` checks only `isHidden`/`alpha`/`frame == .zero`.
    /// So the child resolves to a real rect that lies clear of the parent's mask rect,
    /// and Layer 2's geometric strip has nothing to catch it with.
    ///
    /// `clipsToBounds` is a parameter because it makes no difference to the walk: with
    /// it on, the child is not drawn at all, and the wireframe still reports content
    /// there. Both are pinned so a future clip-aware change to `getFrame` has to
    /// confront this case rather than silently alter it.
    ///
    /// A `UIButton` is deliberately the leaf. Under shipped defaults `maskAllText` is
    /// on, so a `UILabel` here would be auto-masked in its own right and never reach
    /// the ancestor-dependent path; a button is not text-classified, so it depends
    /// entirely on the masked ancestor — which is the case that actually shipped text.
    private func makeOffsetChildOfMaskedParent(clipsToBounds: Bool) -> UIView {
        let root = UIView(frame: window.bounds)
        let masked = UIView(frame: CGRect(x: 50, y: 50, width: 100, height: 100))
        masked.clipsToBounds = clipsToBounds
        masked.mpReplaySensitive = true

        let inside = UIButton(type: .custom)
        inside.frame = CGRect(x: 0, y: 0, width: 90, height: 40)
        inside.setTitle("Inside control", for: .normal)

        let outside = UIButton(type: .custom)
        outside.frame = CGRect(x: 200, y: 200, width: 200, height: 30)
        outside.setTitle("Transfer $12,345 to Chase", for: .normal)

        masked.addSubview(inside)
        masked.addSubview(outside)
        root.addSubview(masked)
        window.addSubview(root)
        return root
    }

    private func processed(_ root: UIView) -> [WireframeElement] {
        let (frames, elements) = manager.walkHierarchy(in: root, window: window)
        return WireframeEmitter(options: MPWireframesOptions())
            .processedElements(elements: elements, maskBounds: Set(frames.keys))
    }

    /// The premise, asserted separately so a failure below cannot be misread as the
    /// fixture drifting: the offset child really does land outside every mask rect, so
    /// Layer 2 cannot be what protects it.
    func test_maskedSubtree_offsetChild_isNotCoveredByAnyMaskRect() {
        manager.maskAllText = true
        let root = makeOffsetChildOfMaskedParent(clipsToBounds: true)
        let (frames, elements) = manager.walkHierarchy(in: root, window: window)

        XCTAssertTrue(
            frames.keys.contains { $0.cgRect == CGRect(x: 50, y: 50, width: 100, height: 100) },
            "the container the developer marked sensitive must still produce a mask rect")

        guard
            let offset = elements.first(where: {
                $0.role == .button && $0.x == 250 && $0.y == 250
            })
        else {
            return XCTFail("the offset child should still be walked and emitted")
        }
        let offsetRect = CGRect(x: offset.x, y: offset.y, width: offset.w, height: offset.h)
        XCTAssertFalse(
            frames.keys.contains { $0.cgRect.intersects(offsetRect) },
            "no mask rect covers the offset child — Layer 2 cannot strip it")
    }

    /// Text scraped inside an explicitly masked subtree must never reach the wire,
    /// whether or not a mask rect happens to overlap it.
    ///
    /// Matches Flutter, which resolves every descendant of a `MixpanelMask` to
    /// `explicit` with null text at the walk rather than relying on the geometric pass.
    func test_maskedSubtree_offsetChild_doesNotShipScrapedText() {
        for clips in [true, false] {
            manager.maskAllText = true
            let elements = processed(makeOffsetChildOfMaskedParent(clipsToBounds: clips))

            XCTAssertFalse(
                elements.contains { $0.text == "Transfer $12,345 to Chase" },
                "content inside an mpReplaySensitive subtree must not be scraped "
                    + "(clipsToBounds: \(clips))")
            XCTAssertTrue(
                elements.allSatisfy { $0.text == nil },
                "nothing in a masked subtree carries text (clipsToBounds: \(clips))")

            let offset = elements.first { $0.role == .button && $0.x == 250 }
            XCTAssertEqual(
                offset?.decision, .explicit,
                "the ancestor's decision is the provenance, not a geometric coincidence "
                    + "(clipsToBounds: \(clips))")

            SensitiveViewManager.reset()
            manager = SensitiveViewManager.shared
            manager.wireframeCollectionEnabled = true
            window = UIView(frame: CGRect(x: 0, y: 0, width: 500, height: 800))
        }
    }

    /// The exemption that has to survive the strip: `mpWireframeText` on a *descendant*
    /// of a masked view is authored copy, not scraped pixels, so it is still emitted.
    ///
    /// This is the whole reason the walk descends into a masked subtree rather than
    /// stopping at the container, and it had no coverage before: every other
    /// declared-under-mask test puts the declaration on the masked view itself or on an
    /// overlapping sibling.
    func test_maskedSubtree_descendantDeclaredText_survives() {
        manager.maskAllText = true
        let root = UIView(frame: window.bounds)
        let masked = UIView(frame: CGRect(x: 50, y: 50, width: 200, height: 200))
        masked.mpReplaySensitive = true

        let scraped = UILabel(frame: CGRect(x: 10, y: 10, width: 150, height: 30))
        scraped.text = "4111 1111 1111 1111"
        scraped.mpWireframeText = "Card number"
        masked.addSubview(scraped)
        root.addSubview(masked)
        window.addSubview(root)

        let elements = processed(root)
        XCTAssertTrue(
            elements.contains { $0.text == "Card number" && $0.decision == .declared },
            "declared text on a descendant of a masked view must still be emitted")
        XCTAssertFalse(
            elements.contains { $0.text == "4111 1111 1111 1111" },
            "the scraped value it labels must not be")
    }


    // MARK: - The mask set is untouched by wireframe collection

    /// `mask > unmask > mpReplaySensitive(true)` must record only the enclosing mask.
    ///
    /// The inner explicit mask is inside a region an ancestor already settled, so it
    /// adds nothing — `HierarchyWalk.record` refuses it on `insideMaskedSubtree`. That
    /// flag has to stay set for the whole subtree *including below the unmask*, which
    /// is why it is stored rather than derived from `maskedAncestorDecision`: the
    /// unmask clears the wireframe's text inheritance, and deriving the two from one
    /// field let it clear this as well, adding an inner rect the mask set never had.
    ///
    /// No existing case covered three levels, so the goldens stayed green through it.
    /// Asserted on the frame dictionary directly, because that dictionary *is* the
    /// screenshot.
    func test_maskSet_maskThenUnmaskThenExplicitMask_recordsOnlyTheOuterMask() {
        manager.maskAllText = true
        manager.maskAllImages = true

        let root = UIView(frame: window.bounds)
        let masked = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        masked.mpReplaySensitive = true
        let safe = UIView(frame: CGRect(x: 10, y: 10, width: 200, height: 200))
        safe.mpReplaySensitive = false
        let inner = UIView(frame: CGRect(x: 5, y: 5, width: 100, height: 50))
        inner.mpReplaySensitive = true
        safe.addSubview(inner)
        masked.addSubview(safe)
        root.addSubview(masked)
        window.addSubview(root)

        let frames = manager.walkHierarchy(in: root, window: window).frames
        XCTAssertEqual(
            frames, [HashableRect(CGRect(x: 0, y: 0, width: 300, height: 300)): .mask],
            "only the enclosing mask may be recorded — the inner one adds nothing")
    }

    /// The same shape one level deeper, so a fix that only special-cased a single
    /// unmask would still fail.
    func test_maskSet_maskThenTwoUnmasksThenExplicitMask_recordsOnlyTheOuterMask() {
        manager.maskAllText = true

        let root = UIView(frame: window.bounds)
        let masked = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        masked.mpReplaySensitive = true
        let safeOuter = UIView(frame: CGRect(x: 10, y: 10, width: 200, height: 200))
        safeOuter.mpReplaySensitive = false
        let safeInner = UIView(frame: CGRect(x: 5, y: 5, width: 150, height: 150))
        safeInner.mpReplaySensitive = false
        let inner = UIView(frame: CGRect(x: 2, y: 2, width: 80, height: 40))
        inner.mpReplaySensitive = true
        safeInner.addSubview(inner)
        safeOuter.addSubview(safeInner)
        masked.addSubview(safeOuter)
        root.addSubview(masked)
        window.addSubview(root)

        let frames = manager.walkHierarchy(in: root, window: window).frames
        XCTAssertEqual(
            frames, [HashableRect(CGRect(x: 0, y: 0, width: 300, height: 300)): .mask])
    }

    /// A `UITextField` is the one decision nothing above it can settle, so it still
    /// earns its own rect in the same nesting. Guards against "fix" the leak above by
    /// refusing every nested write.
    func test_maskSet_maskThenUnmaskThenTextField_stillRecordsTextInput() {
        let root = UIView(frame: window.bounds)
        let masked = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        masked.mpReplaySensitive = true
        let safe = UIView(frame: CGRect(x: 10, y: 10, width: 200, height: 200))
        safe.mpReplaySensitive = false
        let field = UITextField(frame: CGRect(x: 5, y: 5, width: 100, height: 50))
        safe.addSubview(field)
        masked.addSubview(safe)
        root.addSubview(masked)
        window.addSubview(root)

        let frames = manager.walkHierarchy(in: root, window: window).frames
        XCTAssertEqual(
            frames,
            [
                HashableRect(CGRect(x: 0, y: 0, width: 300, height: 300)): .mask,
                HashableRect(CGRect(x: 15, y: 15, width: 100, height: 50)): .textInput,
            ],
            "a text input is never overridden by anything above it")
    }

}

/// Stand-in for a customer's own view class registered via `addSensitiveClass`.
/// A `UILabel` subclass so the same view can be masked either by registration or
/// by `maskAllText`, which is what makes the two paths comparable.
private final class CardNumberLabelProbe: UILabel {}
