//
//  ReactNativeWireframeTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import UIKit
import XCTest

@testable import MixpanelSessionReplay

// MARK: - React Native stand-ins
//
// The test target does not link React Native, so `NSClassFromString` would resolve
// nothing and every check in `ReactNativeWireframeSupport` would be inert. These
// classes claim RN's Objective-C names, which is all the lookup keys on, and expose
// only the members the support file actually reads. `@objc(...)` is what registers
// the name — the Swift type name is irrelevant.
//
// Each one mirrors the real class's shape as verified against react-native 0.79.2:
//
//  - `RCTParagraphComponentView` (Fabric): `RCTViewComponentView` subclass with
//    `@property (readonly) NSAttributedString *attributedText`, documented in
//    `RCTParagraphComponentView.h` as "to be only used by external introspection and
//    debug tools".
//  - `RCTParagraphTextView` (Fabric): the private `UIView` subclass that does the
//    drawing, held as a subview of the component view. This is the class the React
//    Native bridge registers with `addSensitiveClass`, which is why the geometric
//    case below matters.
//  - `RCTTextView` (Paper): `UIView` subclass whose `NSTextStorage` is private and
//    whose `accessibilityLabel` override returns the rendered string.
//  - `RCTImageView` (Paper): an `RCTView`, *not* a `UIImageView`.

@objc(RCTParagraphComponentView)
private final class FakeParagraphComponentView: UIView {
    @objc var attributedText: NSAttributedString?
}

@objc(RCTParagraphTextView)
private final class FakeParagraphTextView: UIView {}

@objc(RCTTextView)
private final class FakeLegacyTextView: UIView {}

@objc(RCTImageView)
private final class FakeLegacyImageView: UIView {}

/// Wireframe capture for React Native screens.
///
/// React Native draws its own text, so before this support existed an RN screen
/// produced a wireframe with no text elements in it at all — the pixels were masked
/// correctly the whole time, but nothing described the screen, which is the one thing
/// wireframes exist to do. These tests pin both halves: that RN views are now
/// described, and that describing them cannot outrun masking.
final class ReactNativeWireframeTests: XCTestCase {

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

    // MARK: - The lookup itself

    /// If this fails, every other test in the file is passing vacuously: the `@objc`
    /// names above are what make the support file's class lookups resolve.
    func test_stubsRegisterTheReactNativeClassNames() {
        XCTAssertTrue(
            ReactNativeWireframeSupport.isReactNativeApp,
            "the @objc(RCT…) stand-ins must be visible to NSClassFromString")
    }

    // MARK: - Classification

    func test_fabricParagraph_classifiesAsText() {
        XCTAssertEqual(ReactNativeWireframeSupport.role(for: FakeParagraphComponentView()), .text)
        XCTAssertEqual(manager.classifyForWireframe(view: FakeParagraphComponentView()), .text)
    }

    func test_legacyTextView_classifiesAsText() {
        XCTAssertEqual(manager.classifyForWireframe(view: FakeLegacyTextView()), .text)
    }

    /// Paper's `<Image>` is an `RCTView`, so the `UIImageView` check misses it. Fabric's
    /// is backed by a real `UIImageView` subclass and is already handled without help.
    func test_legacyImageView_classifiesAsImage() {
        XCTAssertEqual(manager.classifyForWireframe(view: FakeLegacyImageView()), .image)
    }

    /// The support table must not widen classification for anything else. A plain
    /// container view stays unclassified, which is what keeps RN's many layout wrappers
    /// out of the wireframe.
    func test_plainView_isStillUnclassified() {
        XCTAssertNil(ReactNativeWireframeSupport.role(for: UIView()))
        XCTAssertNil(manager.classifyForWireframe(view: UIView()))
    }

    // MARK: - Text extraction

    func test_fabricParagraph_textComesFromAttributedText() {
        let view = FakeParagraphComponentView()
        view.attributedText = NSAttributedString(string: "Order total")

        XCTAssertEqual(manager.extractWireframeText(view: view, role: .text), "Order total")
    }

    /// Fabric's `attributedText` is nil until the component has state, and empty for an
    /// empty `<Text>`. Both must produce a textless shell, not `""`, so the element
    /// reads the same as any other role + bounds shell.
    func test_fabricParagraph_withoutText_yieldsNoText() {
        XCTAssertNil(manager.extractWireframeText(view: FakeParagraphComponentView(), role: .text))

        let empty = FakeParagraphComponentView()
        empty.attributedText = NSAttributedString(string: "")
        XCTAssertNil(manager.extractWireframeText(view: empty, role: .text))
    }

    /// Fabric's text is tier 2, not the accessibility-label tier: `attributedText` is the
    /// string the view draws, so it is text a viewer can read off the replay. Gating it on
    /// `useAccessibilityLabelFallback` — off by default — would ship every New Architecture
    /// screen with no text at all.
    func test_fabricText_isNotGatedByTheLabelFallback() {
        XCTAssertFalse(manager.useAccessibilityLabelFallback, "precondition: the default")

        let fabric = FakeParagraphComponentView()
        fabric.attributedText = NSAttributedString(string: "Continue")

        XCTAssertEqual(manager.extractWireframeText(view: fabric, role: .text), "Continue")
    }

    /// Paper's text *is* the label tier, and waits on the customer's setting.
    ///
    /// `RCTTextView` publishes its string only by overriding `accessibilityLabel`, and that
    /// override prefers an explicitly-set label over the rendered text — so what comes back
    /// may describe the view rather than quote it, and which one it is cannot be told from
    /// outside RN. That is exactly the uncertainty `useAccessibilityLabelFallback` governs,
    /// so the decision is the customer's rather than ours.
    func test_paperText_isGatedByTheLabelFallback() {
        XCTAssertFalse(manager.useAccessibilityLabelFallback, "precondition: the default")

        let paper = FakeLegacyTextView()
        paper.accessibilityLabel = "Continue"

        XCTAssertNil(
            manager.extractWireframeText(view: paper, role: .text),
            "legacy-architecture text is the label tier, and the fallback is off")

        manager.useAccessibilityLabelFallback = true
        XCTAssertEqual(manager.extractWireframeText(view: paper, role: .text), "Continue")
    }

    /// The two architectures differ only in the tier, never in whether the element ships.
    /// A Paper `<Text>` with the fallback off is a `role + bounds` shell — the shape of the
    /// screen is preserved either way, and `mpWireframeText` is the way to describe it.
    func test_paperText_withFallbackOff_stillShipsAShell() {
        let root = UIView(frame: window.bounds)
        let paper = FakeLegacyTextView(frame: CGRect(x: 5, y: 15, width: 180, height: 25))
        paper.accessibilityLabel = "Order total"
        root.addSubview(paper)
        window.addSubview(root)

        let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes

        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(elements[0].role, .text)
        XCTAssertNil(elements[0].text)
        XCTAssertEqual([elements[0].x, elements[0].y, elements[0].w, elements[0].h], [5, 15, 180, 25])
    }

    /// Fabric falls through to the label tier too, but only when it has no drawn string of
    /// its own — an empty `<Text>`, or a component that has no state yet.
    func test_fabricText_withoutAttributedText_fallsThroughToTheLabelTier() {
        let fabric = FakeParagraphComponentView()
        fabric.accessibilityLabel = "Continue"

        XCTAssertNil(manager.extractWireframeText(view: fabric, role: .text))

        manager.useAccessibilityLabelFallback = true
        XCTAssertEqual(manager.extractWireframeText(view: fabric, role: .text), "Continue")
    }

    /// An unlabelled Paper view has no text source at all, at either setting.
    func test_legacyTextView_withoutLabel_yieldsNoText() {
        XCTAssertNil(manager.extractWireframeText(view: FakeLegacyTextView(), role: .text))

        manager.useAccessibilityLabelFallback = true
        XCTAssertNil(manager.extractWireframeText(view: FakeLegacyTextView(), role: .text))
    }

    /// An RN image is described by role and bounds. Its label follows the same rule every
    /// other image follows — available only when the customer opts into the fallback.
    func test_legacyImageView_labelFollowsTheFallbackFlag() {
        let image = FakeLegacyImageView()
        image.accessibilityLabel = "profile photo"

        XCTAssertNil(
            manager.extractWireframeText(view: image, role: .image),
            "an image's label is the fallback tier, and the fallback is off")

        manager.useAccessibilityLabelFallback = true
        XCTAssertEqual(manager.extractWireframeText(view: image, role: .image), "profile photo")
    }

    // MARK: - The walk

    /// A New Architecture screen, which is what RN 0.76+ produces by default: both elements
    /// described, positioned, and quoted.
    func test_walk_describesAReactNativeScreen() {
        let root = UIView(frame: window.bounds)
        let heading = FakeParagraphComponentView(frame: CGRect(x: 10, y: 20, width: 200, height: 30))
        heading.attributedText = NSAttributedString(string: "Checkout")
        let total = FakeParagraphComponentView(frame: CGRect(x: 10, y: 60, width: 200, height: 30))
        total.attributedText = NSAttributedString(string: "Order total")
        root.addSubview(heading)
        root.addSubview(total)
        window.addSubview(root)

        let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes

        XCTAssertEqual(elements.count, 2)
        XCTAssertEqual(elements.map(\.role), [.text, .text])
        XCTAssertEqual(elements.map(\.text), ["Checkout", "Order total"])
        XCTAssertEqual(elements.map(\.decision), [.none, .none])
        XCTAssertEqual([elements[0].x, elements[0].y, elements[0].w, elements[0].h], [10, 20, 200, 30])
    }

    /// A `<Text>` inside a `<Pressable>` reads the same way it does on Android: the
    /// touchable is an unclassified container and the paragraph inside it carries the
    /// text. Neither platform emits a `button` role for React Native, so wireframes from
    /// the two stay comparable.
    func test_walk_touchableWrapperIsAContainerNotAButton() {
        let root = UIView(frame: window.bounds)
        let touchable = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        let label = FakeParagraphComponentView(frame: CGRect(x: 8, y: 8, width: 184, height: 28))
        label.attributedText = NSAttributedString(string: "Log in")
        touchable.addSubview(label)
        root.addSubview(touchable)
        window.addSubview(root)

        let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes

        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(elements[0].role, .text)
        XCTAssertEqual(elements[0].text, "Log in")
    }

    /// The component view is a wireframe leaf, so the private drawing view nested inside
    /// it does not emit a second element at the same bounds.
    func test_walk_innerDrawingViewDoesNotDuplicateTheElement() {
        let root = UIView(frame: window.bounds)
        let paragraph = FakeParagraphComponentView(frame: CGRect(x: 0, y: 0, width: 200, height: 30))
        paragraph.attributedText = NSAttributedString(string: "Welcome")
        paragraph.addSubview(FakeParagraphTextView(frame: paragraph.bounds))
        root.addSubview(paragraph)
        window.addSubview(root)

        let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes

        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(elements[0].text, "Welcome")
    }

    // MARK: - Masking wins

    /// The default configuration. With `.text` in `autoMaskedViews` the React Native
    /// bridge registers RN's text classes through `addSensitiveClass`, and the text has
    /// to disappear from the wireframe as well as from the pixels.
    ///
    /// The bridge registers the *inner* drawing view, one level below the view that
    /// carries the element, so it is the emitter's geometric layer that closes the gap:
    /// the parent's bounds necessarily intersect its own child's mask rect. Nothing here
    /// depends on the two views having equal frames.
    func test_maskedByClass_stripsTheTextGeometrically() {
        manager.sensitiveClasses = [FakeParagraphTextView.self]

        let root = UIView(frame: window.bounds)
        let paragraph = FakeParagraphComponentView(frame: CGRect(x: 0, y: 0, width: 200, height: 30))
        paragraph.attributedText = NSAttributedString(string: "4111 1111 1111 1111")
        paragraph.addSubview(FakeParagraphTextView(frame: CGRect(x: 4, y: 4, width: 192, height: 22)))
        root.addSubview(paragraph)
        window.addSubview(root)

        let result = manager.collectFramesAndWireframes(in: root, window: window)
        XCTAssertFalse(result.frames.isEmpty, "the drawn text must still paint a mask region")
        XCTAssertEqual(result.wireframes.count, 1)

        let emitter = WireframeEmitter(options: MPWireframesOptions())
        let processed = emitter.applyMaskingPipeline(
            result.wireframes[0], maskBounds: Set(result.frames.keys))

        XCTAssertNil(processed.text, "masked React Native text must not reach the wireframe")
        XCTAssertEqual(processed.decision, .geometric)
    }

    /// The whole component view registered as sensitive — the shape a customer gets from
    /// `addSensitiveClass(RCTParagraphComponentView.self)`, and the one the masked branch
    /// of the walk handles directly rather than through geometry.
    func test_maskedComponentView_shipsATextlessShell() {
        manager.sensitiveClasses = [FakeParagraphComponentView.self]

        let root = UIView(frame: window.bounds)
        let paragraph = FakeParagraphComponentView(frame: CGRect(x: 0, y: 0, width: 200, height: 30))
        paragraph.attributedText = NSAttributedString(string: "4111 1111 1111 1111")
        root.addSubview(paragraph)
        window.addSubview(root)

        let result = manager.collectFramesAndWireframes(in: root, window: window)
        XCTAssertFalse(result.frames.isEmpty)
        XCTAssertEqual(result.wireframes.count, 1)
        XCTAssertEqual(result.wireframes[0].role, .text, "the shape of the screen is preserved")
        XCTAssertNil(result.wireframes[0].text)
        XCTAssertEqual(result.wireframes[0].decision, .explicit)
    }

    /// `<MPSessionReplayView sensitive>` around a `<Text>`: the wrapper's mask rect covers
    /// its children, so the paragraph inside it is described but never quoted.
    func test_insideASensitiveWrapper_textIsStripped() {
        let root = UIView(frame: window.bounds)
        let wrapper = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        wrapper.mpReplaySensitive = true
        let paragraph = FakeParagraphComponentView(frame: CGRect(x: 10, y: 10, width: 200, height: 30))
        paragraph.attributedText = NSAttributedString(string: "Account 12345")
        wrapper.addSubview(paragraph)
        root.addSubview(wrapper)
        window.addSubview(root)

        let result = manager.collectFramesAndWireframes(in: root, window: window)
        let emitter = WireframeEmitter(options: MPWireframesOptions())
        let processed = result.wireframes.map {
            emitter.applyMaskingPipeline($0, maskBounds: Set(result.frames.keys))
        }

        XCTAssertFalse(processed.isEmpty)
        for element in processed {
            XCTAssertNil(element.text, "nothing under a sensitive wrapper may carry text")
        }
    }

    /// Declared text is authored by the developer, so it outranks whatever RN drew — and,
    /// as everywhere else, it survives masking.
    func test_declaredText_winsOverRenderedReactNativeText() {
        let root = UIView(frame: window.bounds)
        let paragraph = FakeParagraphComponentView(frame: CGRect(x: 0, y: 0, width: 200, height: 30))
        paragraph.attributedText = NSAttributedString(string: "4111 1111 1111 1111")
        paragraph.mpWireframeText = "Card number"
        root.addSubview(paragraph)
        window.addSubview(root)

        let elements = manager.collectFramesAndWireframes(in: root, window: window).wireframes

        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(elements[0].text, "Card number")
        XCTAssertEqual(elements[0].decision, .declared)
    }
}
