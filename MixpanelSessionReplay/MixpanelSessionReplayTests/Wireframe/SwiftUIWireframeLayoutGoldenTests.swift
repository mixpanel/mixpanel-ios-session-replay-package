//
//  SwiftUIWireframeLayoutGoldenTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//
//  The SwiftUI peer of `WireframeLayoutGoldenTests`, section for section, so the
//  two iOS toolkits mirror each other the way Android's `ViewWireframeGoldenTest`
//  and `ComposeWireframeGoldenTest` do. Same device-keyed goldens under
//  `Golden/Layout/<key>/`, same JSON format, same scenarios.
//
//  **One outcome differs by nature, everywhere in this file: scraped text is always
//  `nil`.** SwiftUI does not expose its rendered `Text` — the string lives on
//  `_UIHostingView._rootView`, not on the leaf drawing node the walk reaches — and
//  the SDK deliberately does not read it by private reflection. So a SwiftUI text
//  element ships as a role + bounds shell. That is the documented contract, not a
//  gap, and it is precisely why these cases are still worth running: the *decisions*
//  (`AUTO`, `EXPLICIT`, `TEXT_ENTRY`, `GEOMETRIC`, `DECLARED`, `RULE_*`), the roles,
//  the bounds and the element counts must all match the UIKit suite even though the
//  text column does not.
//
//  Declared text (`.mpReplay(wireframeText:)`) is the exception — it is authored
//  rather than scraped, so it survives, and it is the only way a SwiftUI screen gets
//  readable copy into a summary. The declared cases below therefore carry real
//  strings and exercise the rule engine the same way UIKit does.
//
//  SwiftUI content also crosses the `#available(iOS 26.0, *)` fork: below 26 it is
//  view-backed and found by the view walk; from 26 it renders to `CGDrawingLayer` /
//  `SwiftUI.ImageLayer` with no backing view and only `traverseLayer` sees it. The
//  goldens are recorded per OS, so a divergence between the two implementations
//  shows up as a directory diff.
//

import SwiftUI
import UIKit
import XCTest

@testable import MixpanelSessionReplay

/// `@available` because SwiftUI's `accessibilityLabel(_:)` is iOS 14+. The package
/// floor is iOS 13, but every destination we test against is far above that, so the
/// annotation costs no coverage — it just keeps the suite off a runtime it could not
/// compile for.
@available(iOS 14.0, *)
final class SwiftUIWireframeLayoutGoldenTests: XCTestCase {

    private var manager: SensitiveViewManager!
    private var window: UIWindow!
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
    }

    override func tearDown() {
        SensitiveViewManager.reset()
        root = nil
        window = nil
        manager = nil
        super.tearDown()
    }

    // MARK: - Harness

    /// Hosts `content` in a real window and lays it out through the normal SwiftUI
    /// rendering path. Pinned to the top-left so bounds are dictated by the content
    /// rather than by centering inside a device-sized screen.
    private func layoutSwiftUI<V: SwiftUI.View>(_ content: V) {
        let host = UIHostingController(
            rootView: VStack(alignment: .leading, spacing: 8) { content }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
        )
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // SwiftUI defers its first render past the current turn; the existing
        // hosting-controller tests use the same settle.
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        self.window = window
        root = host.view
    }

    /// A real bitmap. SF Symbols are deliberately avoided for image content:
    /// `Image(systemName:)` produces neither a mask frame nor a wireframe element on
    /// any OS — see `test_swiftui_sfSymbol_isNotMasked_knownGap`.
    private func bitmap(_ side: CGFloat = 80) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    private func image(_ side: CGFloat = 80) -> some SwiftUI.View {
        Image(uiImage: bitmap(side)).resizable().frame(width: side, height: side)
    }

    /// Records both goldens for a case: the element list, and — because the element
    /// list cannot show masking on the SwiftUI path (see
    /// `assertWireframeMaskGolden`) — the mask rectangles alongside it.
    private func assertGolden(
        _ name: String,
        rules: [MPSensitiveRule] = [],
        useAccessibilityLabelFallback: Bool = true
    ) {
        assertWireframeLayoutGolden(
            manager: manager, root: root, window: window, rules: rules,
            useAccessibilityLabelFallback: useAccessibilityLabelFallback, golden: name)
        assertWireframeMaskGolden(
            manager: manager, root: root, window: window,
            golden: name.replacingOccurrences(of: ".json", with: ".masks.json"))
    }

    // MARK: - Text mask decisions

    /// Scraped SwiftUI text is a shell — the UIKit counterpart carries the string.
    func test_swiftui_textPlain() {
        layoutSwiftUI(Text("Public Information"))
        assertGolden("swiftui_text_plain.json")
    }

    func test_swiftui_textAutoMasked() {
        manager.maskAllText = true
        layoutSwiftUI(Text("Account 4111 1111"))
        assertGolden("swiftui_text_auto_masked.json")
    }

    func test_swiftui_textExplicitlyMasked() {
        layoutSwiftUI(Text("Balance $1,234.56").mpReplay(sensitive: true))
        assertGolden("swiftui_text_explicit_masked.json")
    }

    func test_swiftui_textUnmaskOverridesAutoMask() {
        manager.maskAllText = true
        layoutSwiftUI(Text("Public Override").mpReplay(sensitive: false))
        assertGolden("swiftui_text_unmask_overrides_auto.json")
    }

    // MARK: - Text-entry fields

    func test_swiftui_inputAlwaysTextEntry() {
        layoutSwiftUI(TextField("", text: .constant("user@example.com")).frame(width: 260))
        assertGolden("swiftui_input_always_masked.json")
    }

    /// An unmask cannot override the security decision on an editable field.
    func test_swiftui_inputInsideUnmaskStillTextEntry() {
        layoutSwiftUI(
            VStack { TextField("", text: .constant("password123")).frame(width: 260) }
                .mpReplay(sensitive: false)
        )
        assertGolden("swiftui_input_in_unmask_still_masked.json")
    }

    // MARK: - Buttons

    func test_swiftui_buttonWithTitle() {
        layoutSwiftUI(Button("Submit") {})
        assertGolden("swiftui_button_title.json")
    }

    func test_swiftui_buttonUnlabeled() {
        layoutSwiftUI(Button(action: {}) { image(40) })
        assertGolden("swiftui_button_unlabeled.json")
    }

    func test_swiftui_buttonAccessibilityLabel() {
        layoutSwiftUI(Button(action: {}) { image(40) }.accessibilityLabel("Open settings"))
        assertGolden("swiftui_button_accessibility_label.json")
    }

    func test_swiftui_buttonMaskedDropsLabel() {
        layoutSwiftUI(Button("Pay") {}.mpReplay(sensitive: true))
        assertGolden("swiftui_button_masked_drops_label.json")
    }

    // MARK: - Images

    func test_swiftui_imageUnlabeled() {
        layoutSwiftUI(image())
        assertGolden("swiftui_image_unlabeled.json")
    }

    func test_swiftui_imageAccessibilityLabel() {
        layoutSwiftUI(image().accessibilityLabel("Company logo"))
        assertGolden("swiftui_image_accessibility_label.json")
    }

    func test_swiftui_imageAutoMasked() {
        manager.maskAllImages = true
        layoutSwiftUI(image())
        assertGolden("swiftui_image_auto_masked.json")
    }

    func test_swiftui_imageMaskedDropsLabel() {
        layoutSwiftUI(image().accessibilityLabel("Company logo").mpReplay(sensitive: true))
        assertGolden("swiftui_image_masked_drops_label.json")
    }

    // MARK: - Nested directives

    /// Mask on a container, unmask on a child that does not fill it — the realistic
    /// shape, and the counterpart to Flutter fixture 21. The container's mask rect is
    /// strictly larger than the child's unmask rect, so the mask stands and the region
    /// is grayed, matching UIKit, Android and Flutter.
    func test_swiftui_nestedUnmaskInMask() {
        layoutSwiftUI(
            VStack(alignment: .leading) {
                Text("Inner unmasked").mpReplay(sensitive: false)
                Text("Sibling content that makes the container taller")
                Text("And taller still")
            }
            .mpReplay(sensitive: true)
        )
        let result = manager.collectFramesAndWireframes(in: root, window: window)
        XCTAssertFalse(
            result.frames.isEmpty,
            "a mask on a container is not cancelled by unmasking part of its contents")
        assertGolden("swiftui_nested_unmask_in_mask.json")
    }

    /// The degenerate variant: the unmask covers *exactly* the same rect as the mask,
    /// because a `VStack` hugs its only child. The mask must still stand.
    ///
    /// This is the case that exposed the bug. `.mpReplay()` plants a background *rect*
    /// rather than marking an ancestor, so unlike UIKit there is no traversal stop and
    /// the safe-frame sweep arbitrates — and the sweep used to drop any mask a safe
    /// frame contained, which coincident rects make trivially true. An inner unmask
    /// could therefore delete an enclosing explicit mask and show pixels the developer
    /// asked to hide. `Mask > Unmask > Text` is Flutter fixture 20, where Flutter and
    /// Android keep the mask and strip the text geometrically.
    ///
    /// Fixed by exempting `.mask` from the sweep alongside `.textInput`: an unmask
    /// overrides *auto*-masking, never an explicit developer decision.
    func test_swiftui_unmaskCoincidentWithMask_maskStillWins() {
        layoutSwiftUI(
            VStack { Text("Inner unmasked").mpReplay(sensitive: false) }
                .mpReplay(sensitive: true)
        )
        let result = manager.collectFramesAndWireframes(in: root, window: window)
        XCTAssertFalse(
            result.frames.isEmpty,
            "an unmask must not delete an enclosing explicit mask, even at identical bounds")
        assertGolden("swiftui_unmask_coincident_with_mask.json")
    }

    func test_swiftui_nestedUnmaskUnderLayoutInMask() {
        layoutSwiftUI(
            VStack {
                VStack {
                    Text("Inner unmasked").mpReplay(sensitive: false)
                    Text("Inner plain")
                }
            }
            .mpReplay(sensitive: true)
        )
        assertGolden("swiftui_nested_unmask_under_layout.json")
    }

    /// An explicit mask nested under an unmask keeps its mask, matching Android and
    /// Flutter. This previously showed its pixels on iOS — recorded in the Android
    /// `CLAUDE.md` as an accepted divergence — and is now aligned by the same `.mask`
    /// exemption in the safe-frame sweep. The wireframe is a textless shell either way.
    func test_swiftui_nestedMaskInUnmask() {
        layoutSwiftUI(
            VStack { Text("Still secret").mpReplay(sensitive: true) }
                .mpReplay(sensitive: false)
        )
        XCTAssertFalse(
            manager.collectFramesAndWireframes(in: root, window: window).frames.isEmpty,
            "an unmask does not override an explicit mask")
        assertGolden("swiftui_nested_mask_in_unmask.json")
    }

    // MARK: - Geometric leak prevention

    func test_swiftui_geometricOverlapNullsSibling() {
        layoutSwiftUI(
            ZStack(alignment: .topLeading) {
                Color.gray.frame(width: 300, height: 200).mpReplay(sensitive: true)
                Text("Account balance").padding(.top, 40).padding(.leading, 20)
            }
        )
        assertGolden("swiftui_geometric_overlap_nulled.json")
    }

    func test_swiftui_geometricOverlapStripsButtonAndImage() {
        layoutSwiftUI(
            ZStack(alignment: .topLeading) {
                Color.gray.frame(width: 300, height: 200).mpReplay(sensitive: true)
                VStack(alignment: .leading, spacing: 12) {
                    Button("Checkout") {}
                    image(60).accessibilityLabel("Company logo")
                }
                .padding(20)
            }
        )
        assertGolden("swiftui_geometric_overlap_button_and_image.json")
    }

    // MARK: - Sensitive rules
    //
    // Rules can only bite where text survives to Layer 4. For SwiftUI that is
    // declared text, since scraped text is already nil — which is itself the
    // contract worth pinning.

    func test_swiftui_ruleStripOnDeclaredText() {
        layoutSwiftUI(Text("x").mpReplay(wireframeText: "Bearer eyJhbGciOi"))
        assertGolden("swiftui_rule_strip.json", rules: [.strip(text: "Bearer ")])
    }

    func test_swiftui_ruleRedactOnDeclaredText() {
        layoutSwiftUI(Text("x").mpReplay(wireframeText: "email: alice@example.com"))
        assertGolden(
            "swiftui_rule_redact.json",
            rules: [.redact(text: "alice@example.com", replacement: "[EMAIL]")])
    }

    func test_swiftui_ruleStripRegexOnDeclaredText() throws {
        let regex = try NSRegularExpression(pattern: #"^token-"#)
        layoutSwiftUI(Text("x").mpReplay(wireframeText: "token-abc123"))
        assertGolden("swiftui_rule_strip_regex.json", rules: [.stripRegex(regex)])
    }

    func test_swiftui_ruleRedactRegexOnDeclaredText() throws {
        let regex = try NSRegularExpression(pattern: #"\d{3}-\d{2}-\d{4}"#)
        layoutSwiftUI(Text("x").mpReplay(wireframeText: "SSN: 123-45-6789"))
        assertGolden(
            "swiftui_rule_redact_regex.json", rules: [.redactRegex(regex, replacement: "[SSN]")])
    }

    /// Scraped text is already nil, so a rule that would have matched it is a no-op
    /// — the element is a shell either way, and no rule decision is recorded.
    func test_swiftui_ruleDoesNotApplyToScrapedText() {
        layoutSwiftUI(Text("Bearer eyJhbGciOi"))
        assertGolden("swiftui_rule_no_scraped_text.json", rules: [.strip(text: "Bearer ")])
    }

    // MARK: - Declared wireframe text

    func test_swiftui_declaredTextSurvivesMaskOnImage() {
        layoutSwiftUI(image().mpReplay(sensitive: true, wireframeText: "profile photo"))
        assertGolden("swiftui_declared_mask_image.json")
    }

    func test_swiftui_declaredTextOnButton() {
        layoutSwiftUI(Button("Submit") {}.mpReplay(sensitive: true, wireframeText: "checkout action"))
        assertGolden("swiftui_declared_button.json")
    }

    func test_swiftui_declaredTextLabelsInput() {
        layoutSwiftUI(
            TextField("", text: .constant("4111 1111 1111 1111"))
                .frame(width: 260)
                .mpReplay(wireframeText: "Card number")
        )
        assertGolden("swiftui_declared_input.json")
    }

    /// A labeled container does not absorb the field inside it.
    func test_swiftui_declaredContainerKeepsInput() {
        layoutSwiftUI(
            VStack(alignment: .leading) {
                Text("Pay now")
                TextField("", text: .constant("")).frame(width: 260)
            }
            .mpReplay(sensitive: false, wireframeText: "payment form")
        )
        assertGolden("swiftui_declared_container_keeps_input.json")
    }

    /// Declared text is the only way custom-drawn SwiftUI content gets described.
    func test_swiftui_declaredTextOnCustomContent() {
        layoutSwiftUI(
            Rectangle()
                .fill(Color.blue)
                .frame(width: 200, height: 100)
                .mpReplay(wireframeText: "monthly spend")
        )
        assertGolden("swiftui_declared_custom_content.json")
    }

    /// Declared text is exempt from Layer 2 but not from Layer 4.
    func test_swiftui_declaredTextStillStrippedByRule() {
        layoutSwiftUI(Text("x").mpReplay(wireframeText: "card 4111 secret"))
        assertGolden("swiftui_declared_rule_stripped.json", rules: [.strip(text: "secret")])
    }

    func test_swiftui_declaredTextSurvivesGeometricStrip() {
        layoutSwiftUI(
            ZStack(alignment: .topLeading) {
                Color.gray.frame(width: 300, height: 200).mpReplay(sensitive: true)
                Text("Scraped")
                    .mpReplay(wireframeText: "Declared label")
                    .padding(.top, 40).padding(.leading, 20)
            }
        )
        assertGolden("swiftui_declared_survives_geometric.json")
    }

    // MARK: - Accessibility fallback disabled

    func test_swiftui_buttonLabelFallbackOff() {
        layoutSwiftUI(Button(action: {}) { image(40) }.accessibilityLabel("Open settings"))
        assertGolden("swiftui_button_label_fallback_off.json", useAccessibilityLabelFallback: false)
    }

    func test_swiftui_imageLabelFallbackOff() {
        layoutSwiftUI(image().accessibilityLabel("Company logo"))
        assertGolden("swiftui_image_label_fallback_off.json", useAccessibilityLabelFallback: false)
    }

    /// Declared text is authored, not scraped, so the flag must not gate it.
    func test_swiftui_declaredTextFallbackOffStillEmitted() {
        layoutSwiftUI(
            image(40)
                .accessibilityLabel("scraped")
                .mpReplay(wireframeText: "Open settings")
        )
        assertGolden(
            "swiftui_declared_beats_label_fallback_off.json", useAccessibilityLabelFallback: false)
    }

    // MARK: - Hidden content

    /// `.hidden()` removes the view from the render tree entirely; `.opacity(0)`
    /// keeps it laid out but invisible. Neither may reach the wireframe.
    func test_swiftui_hiddenContentNotEmitted() {
        layoutSwiftUI(
            VStack(alignment: .leading) {
                Text("Visible")
                Text("Hidden secret").hidden()
                Text("Transparent secret").opacity(0)
            }
        )
        assertGolden("swiftui_hidden_not_emitted.json")
    }

    // MARK: - Text cleaning and truncation

    /// Truncation applies to declared text, the only SwiftUI text that reaches the
    /// emitter with a value.
    func test_swiftui_declaredTextTruncated() {
        layoutSwiftUI(
            Text("x").mpReplay(
                wireframeText:
                    "This label is far too long to ship intact and must therefore exceed the "
                    + "fifty character wireframe cap")
        )
        let element = manager.collectFramesAndWireframes(in: root, window: window)
            .wireframes.first { $0.isDeclared }
        XCTAssertNotNil(element)
        assertGolden("swiftui_declared_truncated.json")
    }

    /// Declared text is authored, so its codepoints are not second-guessed.
    func test_swiftui_declaredGlyphKeptVerbatim() {
        layoutSwiftUI(image(40).mpReplay(wireframeText: "\u{E900}"))
        assertGolden("swiftui_declared_glyph_kept.json")
    }

    func test_swiftui_emptyScreenEmitsZeroElements() {
        layoutSwiftUI(EmptyView())
        assertGolden("swiftui_empty_screen.json")
    }

    // MARK: - Complex mixed masking

    /// The SwiftUI counterpart to the UIKit `complex_mixed_masking` case and to
    /// Flutter's fixture 31. Same shape, same decisions; the text column is where
    /// the toolkits legitimately differ.
    func test_swiftui_complexMixedMasking() {
        manager.maskAllText = true
        layoutSwiftUI(
            VStack(alignment: .leading, spacing: 12) {
                Text("Auto masked header").font(.title)
                image(100).accessibilityLabel("Hero")
                Text("Explicitly unmasked").mpReplay(sensitive: false)
                image(100).accessibilityLabel("Secret chart").mpReplay(sensitive: true)
                HStack(spacing: 12) {
                    Text("Row auto")
                    Text("Middle").mpReplay(sensitive: false)
                    TextField("", text: .constant("")).frame(width: 120)
                }
            }
        )
        assertGolden("swiftui_complex_mixed_masking.json")
    }

    // MARK: - Cross-cutting guards

    /// A SwiftUI `Image` must be described on every OS, not just iOS 26.
    ///
    /// Below iOS 26 SwiftUI images are backed by a view whose *layer* is a
    /// `SwiftUI.ImageLayer`; from 26 they render to that layer with no backing view
    /// and only the gated layer walk sees them. `isImage(view:)` always tested the
    /// layer class, so masking worked on both, but `classifyForWireframe` did not, so
    /// the element was dropped pre-26. Equality assertion rather than a golden,
    /// because the point is that the two OS families agree.
    func test_swiftui_imageIsDescribedOnEveryOS() {
        layoutSwiftUI(image())
        let result = manager.collectFramesAndWireframes(in: root, window: window)
        XCTAssertEqual(
            result.wireframes.map(\.role), [.image],
            "a SwiftUI Image must be described regardless of which walk finds it")
        XCTAssertTrue(result.frames.isEmpty, "nothing is masked when maskAllImages is off")
    }

    /// **Masking gap, found by this suite — pinned, not endorsed.**
    ///
    /// With `maskAllImages` on, a SwiftUI `Image(systemName:)` produces **no mask
    /// frame at all** on either side of the iOS 26 fork, so its pixels ship. A real
    /// bitmap in the same position is masked, and a UIKit `UIImageView` is masked —
    /// this is specific to SF Symbols, which render as neither a detected image layer
    /// nor a text layer.
    ///
    /// Practical exposure is limited: SF Symbols are system glyphs, so an app is
    /// unlikely to render customer content through one. But a customer who sets
    /// `maskAllImages` reasonably expects every image grayed.
    func test_swiftui_sfSymbol_isNotMasked_knownGap() {
        manager.maskAllImages = true
        layoutSwiftUI(Image(systemName: "star.fill").resizable().frame(width: 80, height: 80))
        let result = manager.collectFramesAndWireframes(in: root, window: window)
        XCTAssertTrue(
            result.frames.isEmpty,
            "KNOWN GAP: an SF Symbol is currently not masked. If this starts failing the "
                + "gap is fixed — invert the assertion and re-record the goldens.")
        XCTAssertTrue(result.wireframes.isEmpty, "and it is not described either")
    }
}
