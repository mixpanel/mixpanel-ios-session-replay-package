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

    /// When true, `collectFramesAndWireframes(in:window:)` returns a populated
    /// wireframe element list. When false, wireframe collection is a no-op
    /// (the existing masking pass runs unchanged).
    var wireframeCollectionEnabled: Bool = false

    /// Mirrors ``MPWireframesOptions/useAccessibilityLabelFallback``. Only
    /// consulted by `extractWireframeText`; masking is unaffected. When false,
    /// an element with no rendered text of its own ships as a textless
    /// `role + bounds` shell rather than borrowing its `accessibilityLabel`.
    var useAccessibilityLabelFallback: Bool = true

    var sensitiveClasses: [AnyClass] = []

    private(set) var knownSensitiveViews: WeakViewsMap!
    var sensitiveTextFieldViews: WeakViewsMap!
    var sensitiveClassViews: WeakViewsMap!

    // MARK: Liquid glass UI unaffected SwiftUI Classes
    private let swiftUITextFieldClass: AnyClass? = NSClassFromString("SwiftUI.TextEditorTextView")
    private let swiftUIImageLayer: AnyClass? = NSClassFromString("SwiftUI.ImageLayer")

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

    /// Returns visible sensitive regions within a view hierarchy that should be masked during session replay.
    ///
    /// Performs a unified traversal of both UIView and CALayer hierarchies to detect:
    /// - Text views and labels (UILabel, UITextView, iOS 26+ SwiftUI Text)
    /// - Images (UIImageView, iOS 26+ SwiftUI Image)
    /// - Input fields (UITextField, text editors)
    /// - Web views and map views
    /// - Custom sensitive classes
    ///
    /// Respects views explicitly marked as safe via `mpReplaySensitive = false`.
    ///
    /// - Parameters:
    ///   - rootView: The root view to traverse
    ///   - window: The window providing coordinate space for frame conversion
    /// - Returns: Set of rectangles in window coordinates representing sensitive content to mask
    func getSensitiveFrames(in rootView: UIView, window: UIView) -> [HashableRect: MaskDecision] {
        return collectFramesAndWireframes(in: rootView, window: window).frames
    }

    /// Returns both the mask decisions used by the screenshot pass and, when
    /// `wireframeCollectionEnabled` is true, a list of wireframe elements
    /// captured in the same walk. When wireframes are disabled the elements
    /// list is always empty.
    func collectFramesAndWireframes(in rootView: UIView, window: UIView)
        -> (frames: [HashableRect: MaskDecision], wireframes: [WireframeElement])
    {
        var maskDecisions = [HashableRect: MaskDecision]()
        var safeFrames = Set<HashableRect>()
        let collector: WireframeCollector? =
            wireframeCollectionEnabled ? WireframeCollector() : nil

        // Single unified traversal
        traverseViewAndLayers(
            rootView,
            window: window,
            maskDecisions: &maskDecisions,
            safeFrames: &safeFrames,
            wireframes: collector,
            insideWireframeLeaf: false,
            insideSafeSubtree: false)

        // Remove regions contained within safe frames.
        //
        // An unmask overrides *auto*-masking — that is what it is for. It does not
        // override a decision the developer made explicitly, so `.mask` (an explicit
        // `mpReplaySensitive = true` / `addSensitiveView` / registered class) and
        // `.textInput` both survive the sweep. Without the `.mask` exemption an inner
        // unmask could delete an enclosing explicit mask outright and show pixels the
        // developer asked to hide: `Mask > Unmask > Text` is Flutter fixture 20, where
        // Flutter and Android keep the mask and strip the text geometrically, and iOS
        // was dropping it whenever the safe rect happened to contain the mask rect —
        // which a SwiftUI `VStack` hugging its only child makes trivially true.
        if !safeFrames.isEmpty {
            maskDecisions = maskDecisions.filter { (rect, decision) in
                decision == .textInput || decision == .mask
                    || !safeFrames.contains { $0.contains(rect) }
            }
        }

        // Only add unmask entries and notify when a debug listener is active
        if let listener = maskRegionsListener {
            // Build a separate dictionary for the listener that includes unmask entries
            // so the debug overlay can visualize safe regions without polluting the
            // production return value
            var debugDecisions = maskDecisions
            for safeFrame in safeFrames {
                addOrUpdate(&debugDecisions, rect: safeFrame, decision: .unmask)
            }
            listener(debugDecisions, window as? UIWindow)
        }

        return (maskDecisions, dedupedWireframes(collector?.elements ?? []))
    }

    /// Drops the empty SwiftUI text shell that overlaps a customer-declared
    /// `.mpReplay(wireframeText:)` element. The declaration is planted as a
    /// `.background`, which is a *sibling* of SwiftUI's drawing view — not a
    /// descendant — so `insideWireframeLeaf` cannot suppress it, and both emit a
    /// `.text` element at the same bounds (one with the declared text, one
    /// empty). Keep the text-bearing element; drop the empty, unmasked shell.
    /// Masked shells (decision != .none) are never dropped — safety is
    /// preserved.
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

    /// Adds or updates a mask decision, keeping the higher priority decision.
    private func addOrUpdate(
        _ decisions: inout [HashableRect: MaskDecision], rect: HashableRect, decision: MaskDecision
    ) {
        if let existing = decisions[rect] {
            if decision > existing {
                decisions[rect] = decision
            }
        } else {
            decisions[rect] = decision
        }
    }

    /// Mask-decision write for the wireframe-driven part of the walk: a no-op
    /// once we are inside an explicitly-unmasked subtree.
    ///
    /// The walk continues below an unmask container only to *describe* it (see
    /// ``traverseViewAndLayers``); the screenshot's behavior for that region was
    /// settled the moment the container was marked safe. Routing every mask write
    /// in the traversal through this one guard is what makes "the wireframe sees
    /// more, the pixels see exactly the same" a property of the code rather than
    /// a promise — a new mask site added later cannot silently start graying
    /// pixels inside a region the developer asked to show.
    private func recordMask(
        _ decisions: inout [HashableRect: MaskDecision],
        rect: HashableRect,
        decision: MaskDecision,
        insideSafeSubtree: Bool
    ) {
        guard !insideSafeSubtree else { return }
        addOrUpdate(&decisions, rect: rect, decision: decision)
    }

    /// Unified traversal that handles both UIView hierarchy and CALayer hierarchy in a single pass
    ///
    /// This method efficiently combines:
    /// - UIView hierarchy traversal (for UIKit and iOS <26 SwiftUI)
    /// - CALayer hierarchy traversal (for iOS 26+ SwiftUI rendered directly to layers)
    ///
    /// By traversing both simultaneously, we avoid redundant work and maintain correct precedence:
    /// 1. Check if view itself is sensitive/safe (UIView level)
    /// 2. If not handled at view level, check the view's layer subtree for iOS 26+ SwiftUI content
    /// 3. Recurse into subviews
    ///
    /// - Parameter insideSafeSubtree: True once an ancestor was explicitly
    ///   unmasked (`mpReplaySensitive == false`). The walk keeps going so the
    ///   wireframe can describe content the developer deliberately chose to show,
    ///   but every mask write below is suppressed (see ``recordMask``) so the
    ///   screenshot for that region is byte-identical to what it was when the
    ///   walk stopped at the container.
    /// - Parameter insideMaskedSubtree: set once an explicitly/auto masked view has
    ///   been entered. The subtree is traversed purely to *describe* it — every mask
    ///   and unmask write below is suppressed, so the frame set (and therefore the
    ///   pixels) is identical to stopping at the mask. The container's rect already
    ///   covers everything inside it.
    private func traverseViewAndLayers(
        _ view: UIView,
        window: UIView,
        maskDecisions: inout [HashableRect: MaskDecision],
        safeFrames: inout Set<HashableRect>,
        wireframes: WireframeCollector?,
        insideWireframeLeaf: Bool,
        insideSafeSubtree: Bool,
        insideMaskedSubtree: Bool = false
    ) {
        // Skip invisible views
        guard view.isVisible() else { return }

        // MARK: - Mixpanel opt-in wrapper (`.mpReplay(sensitive:wireframeText:)`)
        // A single MPReplayWrapper background carries both the sensitivity flag
        // and any customer-declared wireframe text. Its two concerns are
        // orthogonal: `sensitive` covers the view with an opaque mask rectangle,
        // while `wireframeText` is authored (not scraped) and is emitted even
        // when the view is sensitive. The wrapper is an empty background view, so
        // we fully resolve it here and stop.
        if view is MPReplayWrapper {
            if let hashableRect = hashableFrame(for: view.layer, in: window) {
                switch view.mpReplaySensitive {
                    case .some(true):
                        recordMask(
                            &maskDecisions, rect: hashableRect, decision: .mask,
                            insideSafeSubtree: insideSafeSubtree || insideMaskedSubtree)
                    case .some(false):
                        if !insideSafeSubtree && !insideMaskedSubtree {
                            if !insideMaskedSubtree { safeFrames.insert(hashableRect) }
                        }
                    case .none:
                        break
                }
                if let wireframes, !insideWireframeLeaf,
                    let text = declaredWireframeText(for: view)
                {
                    // Role `.text`: the wrapper is a sibling background of the
                    // SwiftUI content, so there is no view to infer a role from.
                    // The contract's fallback for an unknowable role is `text`.
                    wireframes.elements.append(
                        WireframeElement.from(
                            role: .text,
                            text: text,
                            rect: hashableRect.cgRect,
                            decision: .declared))
                }
            }
            return
        }

        // Developer-declared text (`.mpReplay(wireframeText:)` / `mpWireframeText`).
        // Authored rather than scraped, so it is emitted with the view's real role
        // even when the view is masked — masking hides the pixels while the
        // declared text still describes the view for the AI summary. Resolved once
        // here so every branch below can substitute it (Layer 3).
        let declaredText: String? =
            (wireframes != nil && !insideWireframeLeaf) ? declaredWireframeText(for: view) : nil

        // Set once a `.safe` ancestor is crossed; every mask write below is gated
        // on it. Shadows the parameter deliberately so nothing further down can
        // read the pre-unmask value by accident.
        var insideSafeSubtree = insideSafeSubtree

        // MARK: - Check UIView level first (UIKit + legacy SwiftUI)
        switch isSensitiveView(view: view) {
            case .safe:
                // View is explicitly marked as safe — record the frame that
                // exempts this region from masking.
                if let hashableRect = hashableFrame(for: view.layer, in: window),
                    !insideSafeSubtree
                {
                    safeFrames.insert(hashableRect)
                }

                // An unmask is a statement about *pixels*: "this region is fine
                // to show." It was never a reason to stop describing the region,
                // yet stopping here is exactly what made an explicitly-shown
                // subtree emit zero wireframe elements — the one content the
                // developer positively vouched for was the one content the AI
                // summary never heard about. So with wireframes on we fall
                // through: this view and its children are described like any
                // other visible content.
                //
                // The screenshot is untouched. Everything below runs with
                // `insideSafeSubtree`, which suppresses every mask write, so this
                // region grays exactly the same pixels it did when the walk
                // stopped at the container. With wireframes off there is nothing
                // to gain by descending, so the original early exit stands.
                guard wireframes != nil else { return }
                insideSafeSubtree = true

            case .sensitiveTextField:
                // Text fields are always sensitive and cannot be overridden by safe parents.
                // Declared text labels the field ("Card number"); the value the user typed
                // is still never emitted.
                if let hashableRect = hashableFrame(for: view.layer, in: window) {
                    recordMask(
                        &maskDecisions, rect: hashableRect, decision: .textInput,
                        insideSafeSubtree: insideSafeSubtree)
                    if let wireframes, !insideWireframeLeaf {
                        wireframes.elements.append(
                            WireframeElement.from(
                                role: .input,
                                text: declaredText,
                                rect: hashableRect.cgRect,
                                decision: declaredText != nil ? .declared : .textEntry))
                    }
                }
                return  // Don't process subviews or sublayers

            case .sensitive:
                // Auto-masking is precisely what an unmask overrides, so inside a
                // safe subtree an auto-detected view is ordinary visible content:
                // its pixels ship unmasked, and the wireframe describes it with
                // its real text like any other element. Matches Android, where
                // `shouldMask` clears for a class-sensitive view under a safe
                // ancestor. An *explicit* `mpReplaySensitive = true` nested inside
                // still falls through to the masked handling below — the developer
                // asked for that one by name.
                if insideSafeSubtree, view.mpReplaySensitive != true {
                    break
                }

                // Determine if this is an auto-detected or manually marked sensitive view.
                //
                // A class registered via `addSensitiveClass` counts as *manually
                // marked*, reporting `.mask` (wire `EXPLICIT`) rather than `.auto`:
                // per the ERD's Layer 1 table it is a developer opt-in, alongside
                // `mpReplay(sensitive: true)`. Only the `maskAllText`/`maskAllImages`/
                // `maskAllWebViews`/`maskAllMapViews` type matches are `AUTO`.
                // Matches Android's `isViewClassCustomerSensitive` branch.
                //
                // Reporting only — the pixels are identical either way, since the
                // painter fills every rect in the mask set without reading its
                // decision, and the safe-frame filter singles out `.textInput`
                // alone. What changes is the wireframe's `maskDecision` and the
                // debug overlay's fill, which now paints a registered class red
                // (mask) rather than orange (auto). One taxonomy, two consumers.
                //
                // Tested by class membership rather than by which cache the view
                // landed in: `isSensitiveView` checks auto-detection *before*
                // `sensitiveClasses`, so a `UILabel` that is also a registered
                // class never reaches the class branch and would otherwise report
                // `AUTO`. Android tests the class directly, so we do too.
                if let hashableRect = hashableFrame(for: view.layer, in: window) {
                    let isCustomerClass = sensitiveClasses.contains { view.isKind(of: $0) }
                    let decision: MaskDecision =
                        (view.mpReplaySensitive == true || isCustomerClass) ? .mask : .auto
                    recordMask(
                        &maskDecisions, rect: hashableRect, decision: decision,
                        insideSafeSubtree: insideSafeSubtree || insideMaskedSubtree)
                    let role = classifyForWireframe(view: view)
                    if let wireframes, !insideWireframeLeaf, let declaredText {
                        // Emitted even for views that map to no role (fall back to
                        // `.text`) — the developer explicitly opted the view in.
                        wireframes.elements.append(
                            WireframeElement.from(
                                role: role ?? .text,
                                text: declaredText,
                                rect: hashableRect.cgRect,
                                decision: .declared))
                    } else if let wireframes, !insideWireframeLeaf, let role {
                        let wireDecision: MPMaskDecision =
                            (decision == .mask) ? .explicit : .auto
                        wireframes.elements.append(
                            WireframeElement.from(
                                role: role,
                                text: nil,
                                rect: hashableRect.cgRect,
                                decision: wireDecision))
                    }
                }
                // Describe the masked region's *structure* rather than dropping it.
                //
                // Stopping here left a masked container invisible to the summarizer
                // rather than merely redacted: a masked form emitted nothing at all,
                // where Android and Flutter emit its children as textless shells
                // (`GEOMETRIC`, stripped by Layer 2 against the mask rect). Existence
                // and position are not customer content; the text is what must not
                // escape, and Layer 2 already guarantees that.
                //
                // Masking is deliberately untouched. `insideMaskedSubtree` suppresses
                // every mask and unmask write below, so the frame set is identical to
                // stopping here — the container's rect already covers the whole
                // subtree. Same discipline as the unmask fix: descend to describe,
                // never to change which pixels ship.
                //
                // With wireframe collection off there is nothing to gain, so the
                // original early exit stands and integrations that never asked for
                // wireframes pay no traversal cost.
                guard wireframes != nil else { return }
                let maskedSubtreeLeaf =
                    insideWireframeLeaf || classifyForWireframe(view: view) != nil
                for subview in view.subviews {
                    traverseViewAndLayers(
                        subview,
                        window: window,
                        maskDecisions: &maskDecisions,
                        safeFrames: &safeFrames,
                        wireframes: wireframes,
                        insideWireframeLeaf: maskedSubtreeLeaf,
                        insideSafeSubtree: insideSafeSubtree,
                        insideMaskedSubtree: true)
                }
                return

            case .unknown:
                // View itself is not sensitive/safe, continue checking
                break
        }

        // View not sensitive/safe: emit a wireframe element if it maps to a role
        // or carries declared text, then continue recursion. Once a role-bearing
        // leaf is emitted, mark descendants as being inside a wireframe leaf so a
        // UIButton's inner UILabel doesn't re-emit. A declared *container* (no
        // role of its own) does not close the subtree — its children are still
        // real content worth capturing.
        var newInsideLeaf = insideWireframeLeaf
        if let wireframes, !insideWireframeLeaf {
            let role = classifyForWireframe(view: view)
            if role != nil || declaredText != nil,
                let hashableRect = hashableFrame(for: view.layer, in: window)
            {
                let text =
                    declaredText ?? role.flatMap { extractWireframeText(view: view, role: $0) }
                wireframes.elements.append(
                    WireframeElement.from(
                        role: role ?? .text,
                        text: text,
                        rect: hashableRect.cgRect,
                        decision: declaredText != nil ? .declared : .none))
                newInsideLeaf = role != nil
            }
        }

        // MARK: - Check Layer subtree for iOS 26+ SwiftUI content
        // Only traverse layers if we're on iOS 26+ and the view itself wasn't sensitive
        if #available(iOS 26.0, *) {
            // Check direct sublayers (not the view's own layer, which we already handled)
            // This catches SwiftUI Text/Image rendered directly to layers
            if let sublayers = view.layer.sublayers {
                for sublayer in sublayers {
                    traverseLayer(
                        sublayer,
                        window: window,
                        maskDecisions: &maskDecisions,
                        safeFrames: &safeFrames,
                        wireframes: wireframes,
                        insideWireframeLeaf: newInsideLeaf,
                        insideSafeSubtree: insideSafeSubtree || insideMaskedSubtree)
                }
            }
        }

        // MARK: - Recurse into subviews
        for subview in view.subviews {
            traverseViewAndLayers(
                subview,
                window: window,
                maskDecisions: &maskDecisions,
                safeFrames: &safeFrames,
                wireframes: wireframes,
                insideWireframeLeaf: newInsideLeaf,
                insideSafeSubtree: insideSafeSubtree,
                insideMaskedSubtree: insideMaskedSubtree)
        }
    }

    /// Traverses a layer hierarchy for iOS 26+ SwiftUI content rendered directly to layers
    ///
    /// This handles the case where SwiftUI Text/Image is rendered to CGDrawingLayer/ImageLayer
    /// without creating a corresponding UIView in the hierarchy.
    @available(iOS 26.0, *)
    private func traverseLayer(
        _ layer: CALayer,
        window: UIView,
        maskDecisions: inout [HashableRect: MaskDecision],
        safeFrames: inout Set<HashableRect>,
        wireframes: WireframeCollector?,
        insideWireframeLeaf: Bool,
        insideSafeSubtree: Bool
    ) {

        // Skip this layer if it's not visible
        guard layer.isVisible() else {
            return
        }

        // Skip a layer that is some view's *backing* layer — that view is reached by
        // the subview recursion, classified there, and its own sublayers walked from
        // there, so descending here as well double-counts it.
        //
        // This is what made a laid-out UIButton emit phantom textless `text` shells
        // beside its real `button` element: `button.layer.sublayers` contains
        // `titleLabel.layer`, whose delegate is a `UIButtonLabel`, and `isTextLayer`
        // treats that as text. Worse, because the layer walk descends the *whole*
        // layer subtree from every view, an ancestor reached the title layer before
        // the button was ever classified, so `insideWireframeLeaf` was still false
        // and could not suppress it.
        //
        // The identity check matters and a plain `delegate is UIView` would be wrong.
        // A standalone `CALayer` may carry a `UIView` delegate that is *not* in the
        // view hierarchy — the shape iOS 26 SwiftUI produces, and what
        // `testGetSensitiveFrames_WithLayerHierarchy` pins. The view walk can never
        // reach that view, so the layer walk must still handle it. Only a layer that
        // *is* `delegate.layer` is genuinely covered elsewhere.
        //
        // Masking is unaffected either way: the view walk auto-masks any `UILabel`
        // (which `UIButtonLabel` is) when `maskAllText` is on.
        if let delegateView = layer.delegate as? UIView, delegateView.layer === layer {
            return
        }

        let isText = isTextLayer(layer)
        let isImage = isImageLayer(layer)
        // Auto-masking is what an unmask overrides, so inside a safe subtree these
        // layers are shown and described as ordinary content — same rule the view
        // walk applies to an auto-detected `UILabel`/`UIImageView`.
        let masked =
            !insideSafeSubtree && ((maskAllText && isText) || (maskAllImages && isImage))

        if masked {
            if let frame = hashableFrame(for: layer, in: window) {
                recordMask(
                    &maskDecisions, rect: frame, decision: .auto,
                    insideSafeSubtree: insideSafeSubtree)
                if let wireframes, !insideWireframeLeaf {
                    let role: WireframeRole = isText ? .text : .image
                    wireframes.elements.append(
                        WireframeElement.from(
                            role: role,
                            text: nil,
                            rect: frame.cgRect,
                            decision: .auto))
                }
            }
            return
        }

        // Unmasked text/image layer (iOS 26+ SwiftUI rendered to CGDrawingLayer):
        // emit the role + bounds shell and mark descendants as inside a leaf so
        // nested runs don't double-emit.
        //
        // Text is intentionally left `nil`. SwiftUI does not expose its rendered
        // Text content reliably — it lives on `_UIHostingView._rootView`, not the
        // leaf drawing layer the walk reaches. We deliberately do not read it via
        // private reflection; SwiftUI text ships as a role + bounds shell, and
        // developers supply readable text with `.mpReplay(wireframeText:)`.
        var newInsideLeaf = insideWireframeLeaf
        if let wireframes, !insideWireframeLeaf, isText || isImage,
            let frame = hashableFrame(for: layer, in: window)
        {
            let role: WireframeRole = isText ? .text : .image
            wireframes.elements.append(
                WireframeElement.from(
                    role: role,
                    text: nil,
                    rect: frame.cgRect,
                    decision: .none))
            newInsideLeaf = true
        }

        // Recurse into sublayers
        for sublayer in layer.sublayers ?? [] {
            traverseLayer(
                sublayer,
                window: window,
                maskDecisions: &maskDecisions,
                safeFrames: &safeFrames,
                wireframes: wireframes,
                insideWireframeLeaf: newInsideLeaf,
                insideSafeSubtree: insideSafeSubtree)
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
        if let swiftUiTextClass, type(of: view) == swiftUiTextClass { return .text }
        return nil
    }

    /// Tier 1 of the text precedence chain: text the developer declared with
    /// `.mpReplay(wireframeText:)` (SwiftUI) or by setting `mpWireframeText`
    /// directly (UIKit).
    ///
    /// Never gated by ``useAccessibilityLabelFallback`` — that flag governs only
    /// the accessibility-label tier — and never suppressed by masking: it is
    /// authored copy, not scraped pixels.
    func declaredWireframeText(for view: UIView) -> String? {
        guard let declared = view.mpWireframeText, !declared.isEmpty else { return nil }
        return declared
    }

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
            case .button:
                if let button = view as? UIButton {
                    if let title = button.currentTitle, !title.isEmpty { return title }
                    if let title = button.titleLabel?.text, !title.isEmpty { return title }
                }
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
                // `.mpReplay(wireframeText:)`.
                if let swiftUiTextClass, type(of: view) == swiftUiTextClass {
                    return nil
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
