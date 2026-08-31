//
//  SensitiveViewManager.swift
//  MixpanelSessionReplay
//
//  Created by Zihe Jia on 6/20/24.
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import CoreGraphics
import MapKit
import SwiftUI
import UIKit
import WebKit

/// A wrapper around `CGRect` that conforms to `Hashable` by considering only the `origin` and `size`.
struct HashableRect: Hashable {
    let origin: CGPoint
    let size: CGSize

    /// Initialize with a given `CGRect`.
    /// - Parameter rect: The original rectangle.
    init(_ rect: CGRect) {
        self.origin = rect.origin
        self.size = rect.size
    }

    /// Converts the `HashableRect` back to a standard `CGRect`.
    var cgRect: CGRect {
        return CGRect(origin: origin, size: size)
    }

    func contains(_ other: HashableRect) -> Bool {
        cgRect.contains(other.cgRect)
    }

    // MARK: - Hashable Conformance

    /// Custom hash function combining the individual components.
    /// - Parameter hasher: The hasher to use when combining the components.
    func hash(into hasher: inout Hasher) {
        // Combine the individual components of the origin and size.
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }

    /// Custom equality operator comparing the components.
    /// - Parameters:
    ///   - lhs: The left-hand side `HashableRect`.
    ///   - rhs: The right-hand side `HashableRect`.
    /// - Returns: `true` if the rectangles are equal, otherwise `false`.
    static func == (lhs: HashableRect, rhs: HashableRect) -> Bool {
        return lhs.origin.x == rhs.origin.x && lhs.origin.y == rhs.origin.y
            && lhs.size.width == rhs.size.width && lhs.size.height == rhs.size.height
    }
}

/// Describes why a region is masked or unmasked in the debug overlay.
///
/// Cases are ordered by priority (higher raw value = higher priority).
/// When multiple decisions apply to overlapping regions, the highest priority wins.
enum MaskDecision: Int, Comparable {
    case unmask = 0
    case auto = 1
    case mask = 2
    case textInput = 3

    static func < (lhs: MaskDecision, rhs: MaskDecision) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

typealias WeakViewsMap = NSMapTable<UIView, NSNumber>

extension WeakViewsMap {

    /// Inserts a UIView into the map, marking it as sensitive.
    func insert(_ view: UIView) {
        self.setObject(NSNumber(value: true), forKey: view)
    }

    /// Removes a UIView from the map, unmarking it as sensitive.
    func remove(_ view: UIView) {
        self.removeObject(forKey: view)
    }

    /// Checks if the specified UIView key exists in the map.
    func contains(_ key: UIView) -> Bool {
        return self.object(forKey: key) != nil
    }
}

class SensitiveViewManager {
    internal private(set) static var shared: SensitiveViewManager = SensitiveViewManager()

    /// Callback invoked when mask regions are computed, providing typed mask decisions
    var maskRegionsListener: (([HashableRect: MaskDecision], UIWindow?) -> Void)?

    var maskAllText: Bool = true
    var maskAllImages: Bool = true
    var maskAllWebViews: Bool = true
    var maskAllMapViews: Bool = true

    /// When true, `walkHierarchy(in:window:)` returns a populated
    /// wireframe element list. When false, wireframe collection is a no-op
    /// (the existing masking pass runs unchanged).
    var wireframeCollectionEnabled: Bool = false

    /// Mirrors ``MPWireframesOptions/useAccessibilityLabelFallback``. Only
    /// consulted by `extractWireframeText`; masking is unaffected. When false,
    /// an element with no rendered text of its own ships as a textless
    /// `role + bounds` shell rather than borrowing its `accessibilityLabel`.
    var useAccessibilityLabelFallback: Bool = false

    var sensitiveClasses: [AnyClass] = []

    private(set) var knownSensitiveViews: WeakViewsMap!
    var sensitiveTextFieldViews: WeakViewsMap!
    var sensitiveClassViews: WeakViewsMap!

    // MARK: Liquid glass UI unaffected SwiftUI Classes
    private let swiftUITextFieldClass: AnyClass? = NSClassFromString("SwiftUI.TextEditorTextView")
    private let swiftUIImageLayer: AnyClass? = NSClassFromString("SwiftUI.ImageLayer")

    /// Byte codes for SwiftUI's private mangled `ColorShapeLayer` class name, stored
    /// the same way as `swiftUIDrawingLayerCodes` so the symbol never appears as plain
    /// text in the binary's string table. `NSClassFromString("SwiftUI.ColorShapeLayer")`
    /// does not resolve it — unlike `SwiftUI.ImageLayer`, this one carries a private
    /// discriminator. The discriminator is stable: identical on iOS 18.0 and 26.2.
    let swiftUIColorShapeLayerCodes: [UInt8] = [
        95, 84, 116, 67, 55, 83, 119, 105, 102, 116, 85, 73, 80, 51, 51, 95,
        69, 49, 57, 70, 52, 57, 48, 68, 50, 53, 68, 53, 69, 48, 69, 67,
        56, 65, 50, 52, 57, 48, 51, 65, 70, 57, 53, 56, 69, 51, 52, 49,
        49, 53, 67, 111, 108, 111, 114, 83, 104, 97, 112, 101, 76, 97, 121, 101,
        114,
    ]

    /// SwiftUI renders an SF Symbol into a `ColorShapeLayer` rather than an
    /// `ImageLayer`, so symbols were invisible to image detection: `maskAllImages`
    /// did not gray them and the wireframe did not describe them, while a bitmap
    /// `Image(uiImage:)` in the same position was handled correctly.
    ///
    /// Matching this class is narrow, not a catch-all for SwiftUI shapes. Measured on
    /// iOS 18.0 and 26.2: `Color`, `Rectangle().fill()`, `Circle().fill()`,
    /// `RoundedRectangle().fill()` and `Capsule().stroke()` all render into a plain
    /// `CALayer` (usually via `backgroundColor`), and a gradient into `GradientLayer`.
    /// `ColorShapeLayer` was produced only by the symbol — pinned by
    /// `test_swiftui_shapesAreNotMaskedAsImages`.
    let swiftUIColorShapeLayer: AnyClass?

    // MARK: - Legacy SwiftUI Classes (iOS 18 and earlier)
    private let swiftUiTextClass: AnyClass? = NSClassFromString("SwiftUI.CGDrawingView")

    // MARK: - iOS 26+ Layer Classes

    /// iOS 26: SwiftUI Text is rendered directly to CGDrawingLayer (CALayer subclass)
    /// Byte codes for SwiftUI's private mangled `_TtC7SwiftUIP33_863CCF9D49B535DAEB1C7D61BEE53B5914CGDrawingLayer` class name.
    /// Stored as individual UInt8s (not a contiguous string literal) so the
    /// symbol never appears as plain text in the binary's string table.
    let swiftUIDrawingLayerCodes: [UInt8] = [
        95, 84, 116, 67, 55, 83, 119, 105, 102, 116, 85, 73, 80, 51, 51, 95,
        56, 54, 51, 67, 67, 70, 57, 68, 52, 57, 66, 53, 51, 53, 68, 65, 69,
        66, 49, 67, 55, 68, 54, 49, 66, 69, 69, 53, 51, 66, 53, 57, 49, 52,
        67, 71, 68, 114, 97, 119, 105, 110, 103, 76, 97, 121, 101, 114,
    ]

    let swiftUIiOS26TextLayerClass: AnyClass?

    private let buttonLabelClass: AnyClass? = NSClassFromString("UIButtonLabel")

    enum SensitiveViewState {
        case sensitiveTextField
        case sensitive
        case safe
        case unknown
    }

    private init() {
        // NOTE: iOS 26 introduces layer-based rendering for SwiftUI
        // Text views no longer create UIViews (CGDrawingView), instead they render to CGDrawingLayer

        knownSensitiveViews = WeakViewsMap.weakToWeakObjects()
        sensitiveClassViews = WeakViewsMap.weakToWeakObjects()
        sensitiveTextFieldViews = WeakViewsMap.weakToWeakObjects()
        swiftUIiOS26TextLayerClass = ObfuscatedClassLookup.resolveClass(from: swiftUIDrawingLayerCodes)
        swiftUIColorShapeLayer = ObfuscatedClassLookup.resolveClass(from: swiftUIColorShapeLayerCodes)
    }

    static func reset() {
        SensitiveViewManager.shared = SensitiveViewManager()
    }

    func clearCache() {
        knownSensitiveViews.removeAllObjects()
        sensitiveClassViews.removeAllObjects()
        sensitiveTextFieldViews.removeAllObjects()
    }

    func isSensitiveView(view: UIView) -> SensitiveViewState {
        if view.mpReplaySensitive == true {
            return .sensitive
        }

        // Check text field cache first to maintain .sensitiveTextField return type
        if sensitiveTextFieldViews.contains(view) {
            return .sensitiveTextField
        }

        if knownSensitiveViews.contains(view) || sensitiveClassViews.contains(view) {
            return .sensitive
        }

        // Text fields are always sensitive, so check before !isSensitive
        if isTextField(view: view) {
            sensitiveTextFieldViews.insert(view)
            return .sensitiveTextField
        }

        // If mpReplaySensitive is false, view is manually marked as safe
        if view.mpReplaySensitive == false {
            return .safe
        }

        if maskAllText, isLabel(view: view) {
            knownSensitiveViews.insert(view)
            return .sensitive
        }

        if maskAllImages, isImage(view: view) {
            knownSensitiveViews.insert(view)
            return .sensitive
        }

        if maskAllWebViews, isWebView(view: view) {
            knownSensitiveViews.insert(view)
            return .sensitive
        }

        if maskAllMapViews, isMapView(view: view) {
            knownSensitiveViews.insert(view)
            return .sensitive
        }

        if sensitiveClasses.contains(where: { view.isKind(of: $0) }) {
            sensitiveClassViews.insert(view)
            return .sensitive
        }

        return .unknown
    }

    // Legacy text/label detection
    func isLabel(view: UIView) -> Bool {
        if view.isKind(of: UILabel.self) || view.isKind(of: UITextView.self) {
            return true
        }

        // Legacy: SwiftUI CGDrawingView (iOS 18 and earlier)
        if let swiftUiTextClass, type(of: view) == swiftUiTextClass {
            return true
        }

        return false
    }

    // Legacy SwiftUI Image Detection
    func isImage(view: UIView) -> Bool {
        if view.isKind(of: UIImageView.self) {
            return true
        }

        // Check for SwiftUI image layer
        if let swiftUIImageLayer, type(of: view.layer) == swiftUIImageLayer {
            return true
        }

        // SF Symbols: rendered as a shape layer, not an image layer.
        if let swiftUIColorShapeLayer, type(of: view.layer) == swiftUIColorShapeLayer {
            return true
        }

        return false
    }

    func isTextField(view: UIView) -> Bool {
        if view.isKind(of: UITextField.self) {
            return true
        }

        // Check for SwiftUI text editor text view
        if let swiftUITextFieldClass, view.isKind(of: swiftUITextFieldClass) {
            return true
        }

        return false
    }

    func isWebView(view: UIView) -> Bool {
        return view.isKind(of: WKWebView.self)
    }

    func isMapView(view: UIView) -> Bool {
        return view.isKind(of: MKMapView.self)
    }

    // MARK: - iOS 26 Layer-Based Detection

    /// Checks if a CALayer is a text-rendering layer (iOS 26+)
    /// In iOS 26, SwiftUI Text views render directly to CGDrawingLayer instead of creating UIViews
    func isTextLayer(_ layer: CALayer) -> Bool {
        // Check for iOS 26 CGDrawingLayer by class
        if let swiftUIiOS26TextLayerClass, layer.isKind(of: swiftUIiOS26TextLayerClass) {
            return true
        }

        // Check for SwiftUI UILabelLayer delegate
        if let buttonLabelClass, layer.delegate?.isKind(of: buttonLabelClass) == true {
            return true
        }

        return false
    }

    /// Checks if a CALayer is an image-rendering layer (iOS 26+)
    func isImageLayer(_ layer: CALayer) -> Bool {
        // 1. MOST SPECIFIC: Known SwiftUI class (exact match)
        //    Fast pointer comparison, catches specific iOS <26 SwiftUI case
        if let swiftUIImageLayer, type(of: layer) == swiftUIImageLayer {
            return true
        }

        // SF Symbols: rendered as a shape layer, not an image layer. See
        // `swiftUIColorShapeLayer`.
        if let swiftUIColorShapeLayer, type(of: layer) == swiftUIColorShapeLayer {
            return true
        }

        // 2. SPECIFIC: UIKit images with actual content
        //    Common in UIKit apps, checks both type and content
        if layer.contents != nil, layer.delegate is UIImageView {
            return true
        }

        return false
    }

    func addSensitiveClass(_ someClass: AnyClass) {
        if !sensitiveClasses.contains(where: { $0 === someClass }) {
            sensitiveClasses.append(someClass)
        }
    }

    func removeSensitiveClass(_ someClass: AnyClass) {
        sensitiveClasses.removeAll { $0 === someClass }
        var viewsToRemove: [UIView] = []
        for key in sensitiveClassViews.keyEnumerator() {
            if let keyView = key as? UIView, keyView.isKind(of: someClass) {
                viewsToRemove.append(keyView)
            }
        }
        for view in viewsToRemove {
            sensitiveClassViews.remove(view)
        }
    }

    /// Walks `rootView` once and returns both the regions the screenshot pass must
    /// mask and, when `wireframeCollectionEnabled` is true, the wireframe elements
    /// describing the same screen. The elements list is always empty when wireframes
    /// are off.
    ///
    /// Detects text and labels (UILabel, UITextView, SwiftUI Text), images
    /// (UIImageView, SwiftUI Image, SF Symbols), input fields, web and map views, and
    /// classes registered via `addSensitiveClass`. Respects views marked safe with
    /// `mpReplaySensitive = false`.
    ///
    /// - Parameters:
    ///   - rootView: The root view to traverse.
    ///   - window: The window providing the coordinate space for frame conversion.
    /// - Returns: Mask decisions keyed by rect in window coordinates, and the
    ///   wireframe elements collected in the same walk.
    func walkHierarchy(in rootView: UIView, window: UIView)
        -> (frames: [HashableRect: MaskDecision], wireframes: [WireframeElement])
    {
        let walk = HierarchyWalk(
            window: window, collectingWireframes: wireframeCollectionEnabled)
        traverse(rootView, walk: walk, context: WalkContext())

        // An unmask overrides *auto* masking — that is what it is for — but never a
        // decision the developer made explicitly, so `.mask` and `.textInput` survive
        // the sweep. Without the `.mask` exemption an inner unmask could delete an
        // enclosing explicit mask and ship pixels the developer asked to hide, which a
        // SwiftUI `VStack` hugging its only child makes trivially easy to hit. Flutter
        // fixture 20 (`Mask > Unmask > Text`) is the parity case.
        var maskDecisions = walk.maskDecisions
        if !walk.safeFrames.isEmpty {
            maskDecisions = maskDecisions.filter { rect, decision in
                decision == .textInput || decision == .mask
                    || !walk.safeFrames.contains { $0.contains(rect) }
            }
        }

        // The debug overlay wants to draw the safe regions too; production callers
        // must not see them in the mask set.
        if let listener = maskRegionsListener {
            var debugDecisions = maskDecisions
            for safeFrame in walk.safeFrames {
                debugDecisions.record(.unmask, at: safeFrame)
            }
            listener(debugDecisions, window as? UIWindow)
        }

        return (maskDecisions, dedupedWireframes(walk.wireframes))
    }

    /// Drops the empty SwiftUI text shell that overlaps a customer-declared
    /// `.mpWireframeText(_:)` element. The declaration is planted as a
    /// `.background`, which is a *sibling* of SwiftUI's drawing view — not a
    /// descendant — so `insideWireframeLeaf` cannot suppress it, and both emit a
    /// `.text` element at the same bounds (one with the declared text, one empty).
    /// Keep the text-bearing element; drop the empty, unmasked shell. Masked shells
    /// are never dropped, so safety is preserved.
    private func dedupedWireframes(_ elements: [WireframeElement]) -> [WireframeElement] {
        let declaredTextBounds = Set(
            elements
                .filter { $0.role == .text && $0.decision == .declared }
                .map { HashableRect(CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h)) }
        )
        guard !declaredTextBounds.isEmpty else { return elements }

        return elements.filter { element in
            guard element.role == .text, element.text == nil, element.decision == .none
            else { return true }
            let bounds = HashableRect(
                CGRect(x: element.x, y: element.y, width: element.w, height: element.h))
            return !declaredTextBounds.contains(bounds)
        }
    }

    // MARK: - Hierarchy walk

    /// Per-branch traversal state. A value type, so what one child sets never leaks
    /// back to its siblings.
    struct WalkContext {
        /// A role-bearing element already described this subtree, so a `UIButton`'s
        /// inner `UILabel` must not emit an element beside it.
        var insideWireframeLeaf = false

        /// An `mpReplaySensitive = false` ancestor was crossed.
        var insideSafeSubtree = false

        /// A masked ancestor was crossed. Its rect already covers everything below,
        /// so the walk continues only to *describe* the structure.
        var insideMaskedSubtree = false
    }

    /// Everything one hierarchy walk accumulates, and the rules for what may be
    /// written into it.
    ///
    /// Every mask, unmask and wireframe write goes through this object, and each of
    /// its methods decides for itself whether the write applies — so the traversal
    /// below never tests whether wireframes are enabled or whether an ancestor
    /// already settled a region. That is what makes "the wireframe sees more, the
    /// pixels see exactly the same" a property of the code rather than a promise:
    /// enabling wireframes makes the walk descend into subtrees it used to stop at,
    /// and ``record(_:at:in:)`` / ``recordSafe(_:in:)`` refuse to write anything new
    /// down there. Pinned by
    /// `SensitiveViewManagerWireframeTests.testUnmaskSubtree_maskDecisionsUnchanged`.
    final class HierarchyWalk {
        /// Coordinate space every frame is converted into.
        let window: UIView

        /// False when the customer never enabled wireframes: ``describe`` is then a
        /// no-op and ``wireframes`` stays empty.
        let collectingWireframes: Bool

        private(set) var maskDecisions: [HashableRect: MaskDecision] = [:]
        private(set) var safeFrames: Set<HashableRect> = []
        private(set) var wireframes: [WireframeElement] = []

        init(window: UIView, collectingWireframes: Bool) {
            self.window = window
            self.collectingWireframes = collectingWireframes
        }

        /// Marks `rect` for masking, unless an ancestor already settled the region.
        func record(_ decision: MaskDecision, at rect: HashableRect?, in context: WalkContext) {
            guard let rect else { return }
            switch decision {
                case .textInput:
                    // Never overridden by anything above it. Recording it explicitly is
                    // what keeps a typed value grayed no matter what the surrounding
                    // decision turns out to be.
                    break
                case .mask:
                    // An explicit developer mask outlives an unmask above it, but adds
                    // nothing inside a mask that already covers this region.
                    guard !context.insideMaskedSubtree else { return }
                case .auto, .unmask:
                    // Auto-masking is precisely what an unmask overrides.
                    guard !context.insideSafeSubtree, !context.insideMaskedSubtree else { return }
            }
            maskDecisions.record(decision, at: rect)
        }

        /// Exempts `rect` from masking, unless an ancestor already settled the region:
        /// an unmask inside an unmask is redundant, and an unmask inside a mask must
        /// not carve a hole in the rect the developer asked for.
        func recordSafe(_ rect: HashableRect?, in context: WalkContext) {
            guard let rect, !context.insideSafeSubtree, !context.insideMaskedSubtree else { return }
            safeFrames.insert(rect)
        }

        /// Records one wireframe element, and reports whether it did. Does nothing
        /// when wireframes are off, when a role-bearing ancestor already described
        /// this subtree, or when the view has no visible frame.
        @discardableResult
        func describe(
            _ role: WireframeRole,
            text: String? = nil,
            at rect: HashableRect?,
            decision: MPMaskDecision,
            in context: WalkContext
        ) -> Bool {
            guard collectingWireframes, !context.insideWireframeLeaf, let rect else { return false }
            wireframes.append(
                WireframeElement.from(
                    role: role, text: text, rect: rect.cgRect, decision: decision))
            return true
        }

        /// Tier 1 of the text precedence chain: text the developer authored with
        /// `.mpWireframeText(_:)` (SwiftUI) or set on `mpWireframeText` (UIKit).
        /// `nil` when there is nothing to describe here at all.
        ///
        /// Never gated by ``SensitiveViewManager/useAccessibilityLabelFallback`` —
        /// that flag governs only the accessibility-label tier — and never suppressed
        /// by masking: it is authored copy, not scraped pixels.
        func declaredText(for view: UIView, in context: WalkContext) -> String? {
            guard collectingWireframes, !context.insideWireframeLeaf else { return nil }
            guard let declared = view.mpWireframeText, !declared.isEmpty else { return nil }
            return declared
        }
    }

    /// Walks the view hierarchy and, on iOS 26+, the layer hierarchy hanging off it,
    /// in a single pass: UIKit and pre-iOS-26 SwiftUI appear as views, while iOS 26
    /// SwiftUI Text and Image render straight into layers with no view of their own.
    ///
    /// A node resolves one of four ways (see ``isSensitiveView(view:)``). In every
    /// case the walk may keep descending to *describe* the subtree, because the
    /// ``HierarchyWalk`` refuses any mask write an ancestor already settled — masking
    /// is identical whether or not wireframes are enabled.
    private func traverse(_ view: UIView, walk: HierarchyWalk, context: WalkContext) {
        guard view.isVisible() else { return }

        if let wrapper = view as? MPReplayWrapper {
            resolveReplayWrapper(wrapper, walk: walk, context: context)
            return
        }

        // Resolved once so every branch below can substitute it. Authored rather than
        // scraped, so it is emitted even when the view is masked: masking hides the
        // pixels while the declared text still describes the view for the AI summary.
        let declaredText = walk.declaredText(for: view, in: context)

        var context = context
        switch isSensitiveView(view: view) {
            case .safe:
                // An unmask is a statement about *pixels*, and was never a reason to
                // stop describing the region — yet stopping here made the one subtree
                // the developer positively vouched for the one the AI summary never
                // heard about. So record the exemption and keep walking.
                //
                // The descent happens whether or not wireframes are on: returning early
                // when they were off would make masking depend on the wireframe flag,
                // now that a safe subtree can still produce `.mask` / `.textInput`.
                walk.recordSafe(hashableFrame(for: view.layer, in: walk.window), in: context)
                context.insideSafeSubtree = true

            case .sensitiveTextField:
                // Declared text labels the field ("Card number"); the value the user
                // typed is never emitted.
                let rect = hashableFrame(for: view.layer, in: walk.window)
                walk.record(.textInput, at: rect, in: context)
                walk.describe(
                    .input, text: declaredText, at: rect,
                    decision: declaredText != nil ? .declared : .textEntry, in: context)
                return

            case .sensitive:
                // Auto-masking is precisely what an unmask overrides, so inside a safe
                // subtree an auto-detected view is ordinary visible content: pixels ship
                // unmasked and the wireframe describes it with its real text. Matches
                // Android, where `shouldMask` clears for a class-sensitive view under a
                // safe ancestor. An explicit `mpReplaySensitive = true` nested inside
                // still falls through to the masked handling — the developer asked for
                // that one by name.
                if context.insideSafeSubtree, view.mpReplaySensitive != true {
                    break
                }
                describeMaskedSubtree(view, declaredText: declaredText, walk: walk, context: context)
                return

            case .unknown:
                break
        }

        let childContext = describeVisibleView(
            view, declaredText: declaredText, walk: walk, context: context)

        // iOS 26+ SwiftUI Text/Image render into sublayers of a view that is itself
        // neither sensitive nor safe, so they are only reachable from here.
        if #available(iOS 26.0, *) {
            for sublayer in view.layer.sublayers ?? [] {
                traverse(sublayer, walk: walk, context: childContext)
            }
        }

        for subview in view.subviews {
            traverse(subview, walk: walk, context: childContext)
        }
    }

    /// Resolves a `.mpReplaySensitive(_:)` / `.mpWireframeText(_:)` background view.
    ///
    /// The two modifiers are orthogonal: `sensitive` covers the view with an opaque
    /// mask rectangle, while `wireframeText` is authored and is emitted even when the
    /// view is sensitive. Chaining them plants one wrapper each at identical bounds
    /// and only the text-bearing one emits, so two wrappers produce the same output
    /// as one carrying both. The wrapper is an empty background view, so it is fully
    /// resolved here and has no subtree worth walking.
    private func resolveReplayWrapper(
        _ view: MPReplayWrapper, walk: HierarchyWalk, context: WalkContext
    ) {
        guard let rect = hashableFrame(for: view.layer, in: walk.window) else { return }

        switch view.mpReplaySensitive {
            case .some(true): walk.record(.mask, at: rect, in: context)
            case .some(false): walk.recordSafe(rect, in: context)
            case .none: break
        }

        // Role `.text`: the wrapper is a sibling background of the SwiftUI content, so
        // there is no view to infer a role from, and the contract's fallback for an
        // unknowable role is `text`.
        if let text = walk.declaredText(for: view, in: context) {
            walk.describe(.text, text: text, at: rect, decision: .declared, in: context)
        }
    }

    /// Masks `view`, describes it, then walks its children purely to describe their
    /// *structure*.
    ///
    /// Stopping at the container left a masked form invisible to the summarizer
    /// rather than merely redacted, where Android and Flutter emit its children as
    /// textless shells (`GEOMETRIC`, stripped by Layer 2 against the mask rect).
    /// Existence and position are not customer content; the text is what must not
    /// escape, and Layer 2 already guarantees that. `insideMaskedSubtree` keeps the
    /// frame set identical to stopping here, and with wireframes off there is nothing
    /// to gain, so those integrations pay no traversal cost.
    private func describeMaskedSubtree(
        _ view: UIView, declaredText: String?, walk: HierarchyWalk, context: WalkContext
    ) {
        // A class registered via `addSensitiveClass` counts as *manually marked* and
        // reports `.mask` (wire `EXPLICIT`) rather than `.auto`: per the ERD's Layer 1
        // table it is a developer opt-in, alongside `mpReplaySensitive(true)`. Only the
        // `maskAllText`/`maskAllImages`/`maskAllWebViews`/`maskAllMapViews` type matches
        // are `AUTO`. Matches Android's `isViewClassCustomerSensitive` branch.
        //
        // Reporting only — the pixels are identical either way, since the painter fills
        // every rect without reading its decision. What changes is the wireframe's
        // `maskDecision` and the debug overlay's fill. Tested by class membership rather
        // than by which cache the view landed in, because `isSensitiveView` checks
        // auto-detection *before* `sensitiveClasses`, so a `UILabel` that is also a
        // registered class never reaches the class branch.
        let isCustomerClass = sensitiveClasses.contains { view.isKind(of: $0) }
        let decision: MaskDecision =
            (view.mpReplaySensitive == true || isCustomerClass) ? .mask : .auto
        let rect = hashableFrame(for: view.layer, in: walk.window)
        let role = walk.collectingWireframes ? classifyForWireframe(view: view) : nil

        walk.record(decision, at: rect, in: context)
        if let declaredText {
            // Emitted even for a view that maps to no role (falling back to `.text`) —
            // the developer explicitly opted this view in.
            walk.describe(role ?? .text, text: declaredText, at: rect, decision: .declared, in: context)
        } else if let role {
            walk.describe(
                role, at: rect, decision: decision == .mask ? .explicit : .auto, in: context)
        }

        guard walk.collectingWireframes else { return }
        var childContext = context
        childContext.insideMaskedSubtree = true
        childContext.insideWireframeLeaf = context.insideWireframeLeaf || role != nil
        for subview in view.subviews {
            traverse(subview, walk: walk, context: childContext)
        }
    }

    /// Describes a view that is neither masked nor explicitly safe, and returns the
    /// context its children should walk with. A no-op returning `context` unchanged
    /// when wireframes are off or an ancestor already described this subtree.
    private func describeVisibleView(
        _ view: UIView, declaredText: String?, walk: HierarchyWalk, context: WalkContext
    ) -> WalkContext {
        guard walk.collectingWireframes, !context.insideWireframeLeaf else { return context }

        let role = classifyForWireframe(view: view)
        guard role != nil || declaredText != nil,
            let rect = hashableFrame(for: view.layer, in: walk.window)
        else { return context }

        let text = declaredText ?? role.flatMap { extractWireframeText(view: view, role: $0) }
        walk.describe(
            role ?? .text, text: text, at: rect,
            decision: declaredText != nil ? .declared : .none, in: context)

        // A *view-type* role closes the subtree — a `UIButton`'s inner `UILabel` must not
        // re-emit. An accessibility-derived role must not, because it lands on containers:
        // a `Pressable` closing its subtree swallowed both the `<Text>` carrying its label
        // and any nested control, the same failure that makes Flutter's `ListTile` lose a
        // row's action. So a roled container ships as a textless shell and its children
        // keep emitting beside it — the shape Android produces, where a roled container
        // was never a leaf. A declared *container* (no role of its own) likewise does not
        // close the subtree; its children are still real content worth capturing.
        var childContext = context
        childContext.insideWireframeLeaf = role != nil && accessibilityRole(for: view) == nil
        return childContext
    }

    /// Walks a layer hierarchy for iOS 26+ SwiftUI content rendered to
    /// `CGDrawingLayer` / `ImageLayer` without a corresponding UIView.
    @available(iOS 26.0, *)
    private func traverse(_ layer: CALayer, walk: HierarchyWalk, context: WalkContext) {
        guard layer.isVisible() else { return }

        // Skip a view's own *backing* layer: the subview recursion reaches that view,
        // classifies it there and walks its sublayers from there, so descending here as
        // well double-counts it. That is what made a laid-out `UIButton` emit phantom
        // textless `text` shells beside its real `button` element — `titleLabel.layer`
        // has a `UIButtonLabel` delegate, which `isTextLayer` matches, and the layer walk
        // reached it from an ancestor before the button was ever classified.
        //
        // The identity check matters, and a plain `delegate is UIView` would be wrong: a
        // standalone `CALayer` may carry a `UIView` delegate that is *not* in the view
        // hierarchy — the shape iOS 26 SwiftUI produces, pinned by
        // `testGetSensitiveFrames_WithLayerHierarchy`. Only a layer that *is*
        // `delegate.layer` is genuinely covered elsewhere.
        if let delegateView = layer.delegate as? UIView, delegateView.layer === layer {
            return
        }

        var context = context
        let isText = isTextLayer(layer)
        let isImage = isImageLayer(layer)

        if isText || isImage {
            let role: WireframeRole = isText ? .text : .image
            let rect = hashableFrame(for: layer, in: walk.window)

            // Auto-masking is what an unmask overrides, so inside a safe subtree these
            // layers are shown and described as ordinary content — the same rule the
            // view walk applies to an auto-detected `UILabel` / `UIImageView`.
            let masked =
                !context.insideSafeSubtree
                && ((maskAllText && isText) || (maskAllImages && isImage))

            if masked {
                walk.record(.auto, at: rect, in: context)
                walk.describe(role, at: rect, decision: .auto, in: context)
                return  // the mask rect already covers the whole subtree
            }

            // Text is deliberately left `nil`. SwiftUI does not expose its rendered Text
            // reliably — it lives on `_UIHostingView._rootView`, not the leaf drawing
            // layer the walk reaches — and we do not read it via private reflection.
            // SwiftUI text ships as a role + bounds shell; developers supply readable
            // text with `.mpWireframeText(_:)`.
            if walk.describe(role, at: rect, decision: .none, in: context) {
                context.insideWireframeLeaf = true
            }
        }

        for sublayer in layer.sublayers ?? [] {
            traverse(sublayer, walk: walk, context: context)
        }
    }

    // MARK: - Wireframe classification + text extraction

    /// Map a UIView to a wireframe role. `nil` for views we do not emit
    /// (containers, layout wrappers, MKMapView, etc.).
    func classifyForWireframe(view: UIView) -> WireframeRole? {
        // Order matters: UIButton before UILabel (UIButton contains a UILabel
        // titleLabel; we want the button, not its inner label).
        if view is UIButton { return .button }
        if view is UITextField { return .input }
        if let textView = view as? UITextView { return textView.isEditable ? .input : .text }
        if view is UILabel { return .text }
        if view is UIImageView { return .image }
        if view is WKWebView { return .text }
        if let swiftUITextFieldClass, view.isKind(of: swiftUITextFieldClass) { return .input }
        // A pre-iOS-26 SwiftUI `Image` is identified by its *backing layer* class, not
        // its view class — the same test `isImage(view:)` already makes for masking.
        // Without this the two sides disagreed: the image was masked but never
        // described, so a SwiftUI screen summarized as [text, text] on iOS 18 and
        // [text, image, text] on iOS 26, where the layer walk classifies it. Masking
        // was correct throughout; only the wireframe lost the element.
        if let swiftUIImageLayer, type(of: view.layer) == swiftUIImageLayer { return .image }
        if let swiftUIColorShapeLayer, type(of: view.layer) == swiftUIColorShapeLayer {
            return .image
        }
        if let swiftUiTextClass, type(of: view) == swiftUiTextClass { return .text }
        // React Native draws its own text and (on the legacy architecture) its own
        // images, so none of the UIKit checks above see them.
        if let reactNativeRole = ReactNativeWireframeSupport.role(for: view) {
            return reactNativeRole
        }
        // Last: a role the developer declared through accessibility. Intent, not inference —
        // and the only signal available for a control that is a plain view, which is what
        // React Native's `Pressable`/`TouchableOpacity` produce.
        return accessibilityRole(for: view)
    }

    /// Role implied by a view's accessibility traits, or `nil` if it declares none we honor.
    ///
    /// Reads the trait *bitmask*, never a string, so nothing developer-authored can reach the
    /// `role` field — see ``WireframeRole``. UIKit collapses most of React Native's
    /// `accessibilityRole` values to `UIAccessibilityTraitNone`, so button, link and header are
    /// all that is distinguishable here; Android reads its full role enum and reports more.
    /// That asymmetry is deliberate.
    ///
    /// Ordered most specific first, which matters because these are a bitmask and React Native
    /// composes them: its switch trait is `0x20000000000001`, whose low bit *is*
    /// `UIAccessibilityTraitButton` (that is how iOS surfaces a switch to VoiceOver). Testing
    /// `.button` first would therefore report every switch as a button. `imagebutton` sets
    /// image|button and is deliberately left as a button, because the action is what a summary
    /// cares about.
    ///
    /// Note the trait is only present when the view is an accessibility element: React Native
    /// applies `accessibilityRole` to traits for a view that is `accessible`, which `Pressable`
    /// and `TouchableOpacity` default to but a hand-written `<View>` does not.
    func accessibilityRole(for view: UIView) -> WireframeRole? {
        let traits = view.accessibilityTraits
        // React Native's composite switch trait — not a UIKit constant, so it is spelled out.
        let switchTrait = UIAccessibilityTraits(rawValue: 0x0020_0000_0000_0001)
        if traits.contains(switchTrait) { return .switch }
        if traits.contains(.button) { return .button }
        if traits.contains(.link) { return .link }
        if traits.contains(.header) { return .header }
        return nil
    }

    // No text absorption, deliberately.
    //
    // An earlier pass borrowed a roled container's descendants' text so the control would not
    // ship textless. It was wrong twice over: the goldens showed it swallowing nested controls
    // (`role_nested_control` reported one `button: "Cupcake Add"` and lost the inner button), and
    // once an accessibility-derived role stopped closing the subtree the label was already there
    // as a sibling element with bounds inside the control. A summary can associate the two by
    // geometry; it cannot recover an element that was never emitted.

    /// Tiers 2 and 3 of the text precedence chain: the view's own rendered text,
    /// then — only when ``useAccessibilityLabelFallback`` is on — its
    /// `accessibilityLabel`. Tier 1 (declared text) is resolved by the caller,
    /// which never reaches this method when declared text is present.
    func extractWireframeText(view: UIView, role: WireframeRole) -> String? {
        switch role {
            case .input:
                return nil
            case .image:
                return accessibilityFallback(for: view)
            case .button, .link, .header, .checkbox, .switch, .radio, .tab:
                // A real UIButton knows its own title.
                if let button = view as? UIButton {
                    if let title = button.currentTitle, !title.isEmpty { return title }
                    if let title = button.titleLabel?.text, !title.isEmpty { return title }
                }
                // An accessibility-derived role deliberately gets *no* text.
                //
                // Those roles land on containers, and React Native gives an accessible container
                // an `accessibilityLabel` synthesized by concatenating its descendants. Reading
                // it duplicated the label: the container reported "Log in" and the `<Text>`
                // inside it emitted "Log in" again, because such a role does not close the
                // subtree. Worse, that synthesized label is the same
                // swallow-the-subtree-into-one-string behaviour this deliberately avoids.
                //
                // So the control ships as a textless shell with its label beside it, bounds
                // nested inside — the same shape Android produces.
                if accessibilityRole(for: view) != nil { return nil }
                return accessibilityFallback(for: view)
            case .text:
                if let label = view as? UILabel {
                    if let text = label.text, !text.isEmpty { return text }
                }
                if let textView = view as? UITextView {
                    if !textView.text.isEmpty { return textView.text }
                }
                // SwiftUI text (iOS <=18 `SwiftUI.CGDrawingView`): emit the
                // role + bounds shell with no text. SwiftUI doesn't expose its
                // rendered Text reliably (it lives on `_UIHostingView._rootView`,
                // not this leaf render view), and we deliberately do not read it
                // via private reflection. The accessibility fallback below is
                // skipped on purpose; developers label these with
                // `.mpWireframeText(_:)`.
                if let swiftUiTextClass, type(of: view) == swiftUiTextClass {
                    return nil
                }
                // React Native paragraph text. Tier 2, not the label tier — see
                // `ReactNativeWireframeSupport.renderedText(for:)`.
                if let reactNativeText = ReactNativeWireframeSupport.renderedText(for: view) {
                    return reactNativeText
                }
                return accessibilityFallback(for: view)
        }
    }

    /// Last-resort text source, honoring ``useAccessibilityLabelFallback``. An
    /// accessibility label is not drawn on screen, so a customer who cannot vet
    /// what their labels hold can switch this tier off and ship bare
    /// `role + bounds` shells instead.
    private func accessibilityFallback(for view: UIView) -> String? {
        guard useAccessibilityLabelFallback else { return nil }
        let label = view.accessibilityLabel
        return (label?.isEmpty == false) ? label : nil
    }

    func getFrame(for layer: CALayer, in window: UIView) -> CGRect? {
        // Use presentation layer for accurate frame during animations
        let targetLayer = layer.presentation() ?? layer

        // Convert layer bounds to window coordinates
        let frameInWindow = targetLayer.convert(targetLayer.bounds, to: window.layer)

        // Check if visible in window bounds
        guard window.bounds.intersects(frameInWindow) else { return nil }

        // Filter out very small layers (likely not actual content)
        guard frameInWindow.width > 1 && frameInWindow.height > 1 else { return nil }

        return frameInWindow
    }

    /// Retrieves the frame for the given view within the specified window,
    /// and wraps it as a `HashableRect`, if the frame is available.
    /// - Parameters:
    ///   - view: The view for which to retrieve the frame.
    ///   - window: The reference window used to calculate the frame.
    /// - Returns: A `HashableRect` if the frame is retrieved successfully; otherwise, `nil`.
    func hashableFrame(for layer: CALayer, in window: UIView) -> HashableRect? {
        if let frame = getFrame(for: layer, in: window) {
            return HashableRect(frame)
        } else {
            return nil
        }
    }
}

extension Dictionary where Key == HashableRect, Value == MaskDecision {
    /// Records `decision` for `rect`, keeping whichever decision has higher priority
    /// when the same rect is reached twice.
    mutating func record(_ decision: MaskDecision, at rect: HashableRect) {
        if let existing = self[rect], existing >= decision { return }
        self[rect] = decision
    }
}

extension Array where Element == UInt8 {
    func decodedString() -> String? {
        String(bytes: self, encoding: .utf8)
    }
}

enum ObfuscatedClassLookup {
    static func resolveClass(from codes: [UInt8]) -> AnyClass? {
        guard let name = codes.decodedString() else { return nil }
        return NSClassFromString(name)
    }
}
