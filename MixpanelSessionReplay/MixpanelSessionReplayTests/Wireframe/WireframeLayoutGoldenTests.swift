//
//  WireframeLayoutGoldenTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//
//  Wireframe goldens where the coordinates are an *output* of real UIKit layout
//  rather than hardcoded frames. See `WireframeLayoutGoldenTestUtils` for why
//  this suite exists alongside `WireframeGoldenTests` and how the per-simulator
//  golden directories work.
//
//  Every tree here is built with Auto Layout and intrinsic content sizes — a
//  `UIStackView` of real `UILabel`/`UIButton`/`UITextField`/`UIImageView` — so a
//  regression in how the walker reads geometry, or a UIKit change in how text
//  measures, surfaces as a coordinate diff. Section headings mirror the Flutter
//  reference suite and the Android `ViewWireframeGoldenTest`, so the three can be
//  diffed case for case.
//
//  Fonts are pinned with `UIFont.systemFont(ofSize:)` rather than
//  `preferredFont(forTextStyle:)` so the goldens do not move with a Dynamic Type
//  setting.
//

import SwiftUI
import UIKit
import XCTest

@testable import MixpanelSessionReplay

final class WireframeLayoutGoldenTests: XCTestCase {

    private var manager: SensitiveViewManager!
    private var window: UIWindow!
    private var root: UIView!

    /// A registrable type for the `addSensitiveClass` cases.
    private final class CardNumberLabel: UILabel {}

    override func setUp() {
        super.setUp()
        SensitiveViewManager.reset()
        manager = SensitiveViewManager.shared
        manager.wireframeCollectionEnabled = true
        manager.maskAllText = false
        manager.maskAllImages = false
        manager.maskAllWebViews = false
        manager.maskAllMapViews = false
    }

    override func tearDown() {
        SensitiveViewManager.reset()
        root = nil
        window = nil
        manager = nil
        super.tearDown()
    }

    // MARK: - Builders

    private func label(_ text: String?, size: CGFloat = 17) -> UILabel {
        let view = UILabel()
        view.text = text
        view.font = .systemFont(ofSize: size)
        return view
    }

    private func button(title: String?, accessibility: String? = nil) -> UIButton {
        let view = UIButton(type: .custom)
        view.setTitle(title, for: .normal)
        view.titleLabel?.font = .systemFont(ofSize: 17)
        view.setTitleColor(.black, for: .normal)
        view.accessibilityLabel = accessibility
        return view
    }

    private func imageView(accessibility: String? = nil, side: CGFloat = 80) -> UIImageView {
        let view = UIImageView()
        view.accessibilityLabel = accessibility
        view.isAccessibilityElement = accessibility != nil
        view.backgroundColor = .lightGray
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: side),
            view.heightAnchor.constraint(equalToConstant: side),
        ])
        return view
    }

    private func textField(_ text: String?) -> UITextField {
        let view = UITextField()
        view.text = text
        view.font = .systemFont(ofSize: 17)
        view.borderStyle = .roundedRect
        NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: 260)])
        return view
    }

    /// Installs `views` in a top-left-pinned vertical stack, lays the tree out for
    /// real, and returns the walk root.
    @discardableResult
    private func layout(_ views: [UIView], spacing: CGFloat = 8) -> UIView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = spacing
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
        ])

        let made = makeLayoutWindow(container)
        window = made.window
        container.frame = made.window.bounds
        made.window.setNeedsLayout()
        made.window.layoutIfNeeded()
        container.setNeedsLayout()
        container.layoutIfNeeded()
        root = container
        return container
    }

    private func assertGolden(
        _ name: String,
        rules: [MPSensitiveRule] = [],
        useAccessibilityLabelFallback: Bool = true
    ) {
        assertWireframeLayoutGolden(
            manager: manager, root: root, window: window, rules: rules,
            useAccessibilityLabelFallback: useAccessibilityLabelFallback, golden: name)
        // Recorded for both toolkits so the suites stay symmetric. It matters most on
        // the SwiftUI side, where nil text makes masking invisible in the element
        // golden, but it is real coverage here too.
        assertWireframeMaskGolden(
            manager: manager, root: root, window: window,
            golden: name.replacingOccurrences(of: ".json", with: ".masks.json"))
    }

    // MARK: - Text mask decisions

    func test_layout_textPlain() {
        layout([label("Public Information")])
        assertGolden("layout_text_plain.json")
    }

    func test_layout_textAutoMasked() {
        manager.maskAllText = true
        layout([label("Account 4111 1111")])
        assertGolden("layout_text_auto_masked.json")
    }

    func test_layout_textExplicitlyMasked() {
        let secret = label("Balance $1,234.56")
        secret.mpReplaySensitive = true
        layout([secret])
        assertGolden("layout_text_explicit_masked.json")
    }

    func test_layout_textUnmaskOverridesAutoMask() {
        manager.maskAllText = true
        let shown = label("Public Override")
        shown.mpReplaySensitive = false
        layout([shown])
        assertGolden("layout_text_unmask_overrides_auto.json")
    }

    // MARK: - Text-entry fields

    func test_layout_inputAlwaysTextEntry() {
        layout([textField("user@example.com")])
        assertGolden("layout_input_always_masked.json")
    }

    /// An unmask cannot override the security decision on an editable field.
    func test_layout_inputInsideUnmaskStillTextEntry() {
        let field = textField("password123")
        let container = UIView()
        container.mpReplaySensitive = false
        container.addSubview(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: container.topAnchor),
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            field.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        layout([container])
        assertGolden("layout_input_in_unmask_still_masked.json")
    }

    // MARK: - Buttons

    /// A composite control emits exactly once — the cross-platform invariant
    /// (Flutter fixture 15), asserted against a *laid-out* button.
    ///
    /// `SensitiveViewManagerWireframeTests.test_uibutton_emitsButtonRole_notNestedLabel`
    /// makes the same claim but builds a `UIButton` that is never laid out, so its
    /// `titleLabel` never materializes a drawn layer. With real layout it did: the
    /// layer walk descended `button.layer.sublayers`, found the `UIButtonLabel`-backed
    /// title layer, and emitted phantom textless `text` shells beside the real
    /// `button`. Fixed by skipping view-backed layers in `traverseLayer` — see the
    /// comment there. This test is the regression guard.
    func test_layout_uiButtonEmitsExactlyOneElement() {
        layout([button(title: "Submit")])
        let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes
        XCTAssertEqual(
            elements.filter { $0.role == .button }.count, 1, "exactly one button element")
        XCTAssertEqual(
            elements.filter { $0.role == .text }.count, 0,
            "a laid-out UIButton must not emit shells for its inner UIButtonLabel")
        XCTAssertEqual(elements.count, 1, "the button is the only element on screen")
    }

    func test_layout_buttonWithTitle() {
        layout([button(title: "Submit")])
        assertGolden("layout_button_title.json")
    }

    func test_layout_buttonUnlabeled() {
        layout([button(title: nil), imageView(side: 40)])
        assertGolden("layout_button_unlabeled.json")
    }

    func test_layout_buttonFallsBackToAccessibilityLabel() {
        layout([button(title: nil, accessibility: "Open settings"), imageView(side: 40)])
        assertGolden("layout_button_accessibility_label.json")
    }

    func test_layout_buttonMaskedDropsLabel() {
        let pay = button(title: "Pay")
        pay.mpReplaySensitive = true
        layout([pay])
        assertGolden("layout_button_masked_drops_label.json")
    }

    // MARK: - Images

    func test_layout_imageUnlabeled() {
        layout([imageView()])
        assertGolden("layout_image_unlabeled.json")
    }

    func test_layout_imageWithAccessibilityLabel() {
        layout([imageView(accessibility: "Company logo")])
        assertGolden("layout_image_accessibility_label.json")
    }

    func test_layout_imageAutoMasked() {
        manager.maskAllImages = true
        layout([imageView(accessibility: "Company logo")])
        assertGolden("layout_image_auto_masked.json")
    }

    func test_layout_imageMaskedDropsLabel() {
        let logo = imageView(accessibility: "Company logo")
        logo.mpReplaySensitive = true
        layout([logo])
        assertGolden("layout_image_masked_drops_label.json")
    }

    // MARK: - Nested directives

    /// Content inside an explicitly masked container is still *described* — a textless
    /// shell with `GEOMETRIC`, matching Android's `nested_unmask_in_mask_geometric`
    /// and Flutter fixtures 20/21.
    ///
    /// The walk used to `return` before a masked view's subviews, so a masked region
    /// emitted nothing at all: the summary lost the structure entirely rather than
    /// merely losing the text. It now descends to describe, with every mask and unmask
    /// write below suppressed, so the pixels are unchanged — the container's rect
    /// already covers the subtree. Layer 2 does the redaction, stripping the text
    /// against that rect.
    func test_layout_nestedUnmaskInMaskStripsGeometrically() {
        let inner = label("Inner unmasked")
        inner.mpReplaySensitive = false
        let masked = UIStackView(arrangedSubviews: [inner])
        masked.axis = .vertical
        masked.mpReplaySensitive = true
        layout([masked])
        // Through the full pipeline: the walk describes it, Layer 2 redacts it against
        // the container's mask rect. Asserting on the raw walk would see the text still
        // present, which is the emitter's job to strip, not the walk's.
        let collected = manager.collectFramesAndWireframes(in: root, window: window)
        let processed = WireframeEmitter(options: MPWireframesOptions())
            .processedElementsForTesting(
                elements: collected.wireframes, maskBounds: Set(collected.frames.keys))
        XCTAssertEqual(processed.count, 1, "the masked container's contents are still described")
        XCTAssertNil(processed.first?.text, "but never with their text")
        XCTAssertEqual(processed.first?.decision, .geometric, "stripped by the mask's rect")
        assertGolden("layout_nested_unmask_in_mask_geometric.json")
    }

    /// The case this matters for: a masked form emits its structure, not nothing.
    ///
    /// Existence, role and position are not customer content — two textless `input`
    /// shells beside a `button` still reads as a login form to a summarizer, which is
    /// the whole point of the wireframe. Only the text must not escape, and Layer 2
    /// guarantees that against the container's mask rect.
    func test_layout_maskedContainerStillDescribesItsStructure() {
        let form = UIStackView(arrangedSubviews: [
            label("Sign in"),
            textField("user@example.com"),
            button(title: "Log in"),
        ])
        form.axis = .vertical
        form.spacing = 8
        form.alignment = .leading
        form.mpReplaySensitive = true
        layout([form])

        let result = manager.collectFramesAndWireframes(in: root, window: window)
        XCTAssertFalse(result.frames.isEmpty, "the region is still masked")
        XCTAssertEqual(
            result.wireframes.map(\.role), [.text, .input, .button],
            "structure survives inside a mask")
        assertGolden("layout_masked_container_describes_structure.json")
    }

    func test_layout_nestedMaskInUnmaskInnerMaskWins() {
        let secret = label("Still secret")
        secret.mpReplaySensitive = true
        let safe = UIStackView(arrangedSubviews: [secret])
        safe.axis = .vertical
        safe.mpReplaySensitive = false
        layout([safe])
        assertGolden("layout_nested_mask_in_unmask.json")
    }

    // MARK: - Geometric leak prevention

    /// The overlapped node is a sibling of the mask, not a descendant.
    func test_layout_geometricOverlapNullsSiblingText() {
        let container = UIView()
        let cover = UIView()
        cover.mpReplaySensitive = true
        cover.backgroundColor = .darkGray
        let text = label("Account balance")
        for sub in [cover, text] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(sub)
        }
        NSLayoutConstraint.activate([
            cover.topAnchor.constraint(equalTo: container.topAnchor),
            cover.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            cover.widthAnchor.constraint(equalToConstant: 300),
            cover.heightAnchor.constraint(equalToConstant: 200),
            text.topAnchor.constraint(equalTo: container.topAnchor, constant: 40),
            text.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            text.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
        ])
        layout([container])
        assertGolden("layout_geometric_overlap_nulled.json")
    }

    /// Layer 2 is role-agnostic — it strips button and image labels too.
    func test_layout_geometricOverlapStripsButtonAndImage() {
        let container = UIView()
        let cover = UIView()
        cover.mpReplaySensitive = true
        let action = button(title: "Checkout")
        let logo = imageView(accessibility: "Company logo", side: 60)
        for sub in [cover, action, logo] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(sub)
        }
        NSLayoutConstraint.activate([
            cover.topAnchor.constraint(equalTo: container.topAnchor),
            cover.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            cover.widthAnchor.constraint(equalToConstant: 300),
            cover.heightAnchor.constraint(equalToConstant: 200),
            action.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            action.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            logo.topAnchor.constraint(equalTo: action.bottomAnchor, constant: 20),
            logo.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            logo.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
            container.trailingAnchor.constraint(greaterThanOrEqualTo: action.trailingAnchor),
        ])
        layout([container])
        assertGolden("layout_geometric_overlap_button_and_image.json")
    }

    // MARK: - Sensitive rules

    func test_layout_ruleStrip() {
        layout([label("Bearer eyJhbGciOi")])
        assertGolden("layout_rule_strip.json", rules: [.strip(text: "Bearer ")])
    }

    func test_layout_ruleRedact() {
        layout([label("email: alice@example.com")])
        assertGolden(
            "layout_rule_redact.json",
            rules: [.redact(text: "alice@example.com", replacement: "[EMAIL]")])
    }

    func test_layout_ruleStripRegex() throws {
        let regex = try NSRegularExpression(pattern: #"^token-"#)
        layout([label("token-abc123")])
        assertGolden("layout_rule_strip_regex.json", rules: [.stripRegex(regex)])
    }

    func test_layout_ruleRedactRegex() throws {
        let regex = try NSRegularExpression(pattern: #"\d{3}-\d{2}-\d{4}"#)
        layout([label("SSN: 123-45-6789")])
        assertGolden("layout_rule_redact_regex.json", rules: [.redactRegex(regex, replacement: "[SSN]")])
    }

    /// Rules reach label-derived text, not just visible text.
    func test_layout_ruleRedactReachesImageLabel() {
        layout([imageView(accessibility: "avatar of alice@example.com")])
        assertGolden(
            "layout_rule_redact_image_label.json",
            rules: [.redact(text: "alice@example.com", replacement: "[EMAIL]")])
    }

    // MARK: - Declared wireframe text

    func test_layout_declaredTextSurvivesMaskOnImage() {
        let photo = imageView()
        photo.mpReplaySensitive = true
        photo.mpWireframeText = "profile photo"
        layout([photo])
        assertGolden("layout_declared_mask_image.json")
    }

    func test_layout_declaredTextAdoptsButtonRole() {
        let submit = button(title: "Submit")
        submit.mpReplaySensitive = true
        submit.mpWireframeText = "checkout action"
        layout([submit])
        assertGolden("layout_declared_button.json")
    }

    /// Labels the field without leaking the typed value.
    func test_layout_declaredTextLabelsInput() {
        let card = textField("4111 1111 1111 1111")
        card.mpWireframeText = "Card number"
        layout([card])
        assertGolden("layout_declared_input.json")
    }

    /// Declared text is exempt from Layer 2 but not from Layer 4.
    func test_layout_declaredTextStillStrippedByRule() {
        let panel = label("Scraped")
        panel.mpWireframeText = "card 4111 secret"
        layout([panel])
        assertGolden("layout_declared_rule_stripped.json", rules: [.strip(text: "secret")])
    }

    func test_layout_declaredTextSurvivesGeometricStrip() {
        let container = UIView()
        let cover = UIView()
        cover.mpReplaySensitive = true
        let text = label("Scraped")
        text.mpWireframeText = "Declared label"
        for sub in [cover, text] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(sub)
        }
        NSLayoutConstraint.activate([
            cover.topAnchor.constraint(equalTo: container.topAnchor),
            cover.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            cover.widthAnchor.constraint(equalToConstant: 300),
            cover.heightAnchor.constraint(equalToConstant: 200),
            text.topAnchor.constraint(equalTo: container.topAnchor, constant: 40),
            text.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            text.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
        ])
        layout([container])
        assertGolden("layout_declared_survives_geometric.json")
    }

    // MARK: - Accessibility fallback disabled

    func test_layout_buttonLabelFallbackOff() {
        layout([button(title: nil, accessibility: "Open settings"), imageView(side: 40)])
        assertGolden("layout_button_label_fallback_off.json", useAccessibilityLabelFallback: false)
    }

    /// The flag gates the fallback position only; visible text is untouched.
    func test_layout_visibleTextFallbackOffUnaffected() {
        layout([button(title: "Continue", accessibility: "Continue to checkout")])
        assertGolden(
            "layout_button_label_fallback_off_with_text.json", useAccessibilityLabelFallback: false)
    }

    func test_layout_imageLabelFallbackOff() {
        layout([imageView(accessibility: "Company logo")])
        assertGolden("layout_image_label_fallback_off.json", useAccessibilityLabelFallback: false)
    }

    /// Declared text is authored, not scraped, so the flag must not gate it.
    func test_layout_declaredTextFallbackOffStillEmitted() {
        let action = button(title: nil, accessibility: "scraped")
        action.mpWireframeText = "Open settings"
        layout([action, imageView(side: 40)])
        assertGolden(
            "layout_declared_beats_label_fallback_off.json", useAccessibilityLabelFallback: false)
    }

    // MARK: - Hidden content

    /// `isHidden` and zero alpha both remove a view from the replay, so neither may
    /// reach the wireframe. Counterpart to Flutter fixture 44 and Android's
    /// `hidden_views_not_emitted`.
    func test_layout_hiddenViewsNotEmitted() {
        let shown = label("Visible")
        let hidden = label("Hidden secret")
        hidden.isHidden = true
        let transparent = label("Transparent secret")
        transparent.alpha = 0
        layout([shown, hidden, transparent])
        assertGolden("layout_hidden_views_not_emitted.json")
    }

    // MARK: - Text cleaning and truncation

    func test_layout_textTruncated() {
        layout([
            label(
                "This label is far too long to ship intact and must therefore exceed the "
                    + "fifty character wireframe cap")
        ])
        assertGolden("layout_text_truncated.json")
    }

    func test_layout_emptyScreenEmitsZeroElements() {
        layout([])
        assertGolden("layout_empty_screen.json")
    }

    // MARK: - Class registration

    /// A class registered by the developer is an opt-in, so it reports EXPLICIT.
    func test_layout_registeredClassReportsExplicit() {
        manager.addSensitiveClass(CardNumberLabel.self)
        let card = CardNumberLabel()
        card.text = "4111 1111 1111 1111"
        card.font = .systemFont(ofSize: 17)
        layout([card])
        assertGolden("layout_class_explicit_masked.json")
    }

    /// An unmask overrides a class match.
    func test_layout_unmaskOverridesRegisteredClass() {
        manager.addSensitiveClass(CardNumberLabel.self)
        let card = CardNumberLabel()
        card.text = "Not actually sensitive"
        card.font = .systemFont(ofSize: 17)
        card.mpReplaySensitive = false
        layout([card])
        assertGolden("layout_class_safe_kept.json")
    }

    // MARK: - Complex mixed masking

    /// Realistic multi-view layout exercising several decisions at once — the
    /// counterpart to Flutter's `complex_mixed_masking` and Android's
    /// `complex_mixed_masking`. This is the case worth pairing with a pixel golden
    /// of the same tree.
    func test_layout_complexMixedMasking() {
        manager.maskAllText = true

        let header = label("Auto masked header", size: 20)
        let hero = imageView(accessibility: "Hero", side: 100)
        let shown = label("Explicitly unmasked")
        shown.mpReplaySensitive = false
        let chart = imageView(accessibility: "Secret chart", side: 100)
        chart.mpReplaySensitive = true

        let rowAuto = label("Row auto")
        let rowShown = label("Middle")
        rowShown.mpReplaySensitive = false
        let row = UIStackView(arrangedSubviews: [rowAuto, rowShown, textField(nil)])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center

        layout([header, hero, shown, chart, row], spacing: 12)
        assertGolden("layout_complex_mixed_masking.json")
    }
}
