//
//  SensitiveViewManager+HierarchyWalk.swift
//  MixpanelSessionReplay
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import UIKit

// One traversal of a view hierarchy produces two things: the rectangles the
// screenshot pass grays out, and the wireframe elements that describe the same
// screen to the AI summary. They are computed together on purpose — a second walk
// could disagree with the first, and a disagreement here means either masked pixels
// described in the clear or described content that was actually redacted.
//
// The invariant the whole file is built around: *the wireframe sees more, the pixels
// see exactly the same*. Enabling wireframes makes the walk descend into subtrees it
// used to stop at, so masking must not change. That is enforced structurally rather
// than by review — every write goes through ``SensitiveViewManager/HierarchyWalk``,
// whose methods refuse anything an ancestor already settled.
extension SensitiveViewManager {

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
        let role = walk.collectingWireframes ? wireframeClassifier.role(for: view) : nil

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

        let role = wireframeClassifier.role(for: view)
        guard role != nil || declaredText != nil,
            let rect = hashableFrame(for: view.layer, in: walk.window)
        else { return context }

        let text = declaredText ?? role.flatMap { wireframeClassifier.text(for: view, role: $0) }
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
        childContext.insideWireframeLeaf = role != nil && wireframeClassifier.accessibilityRole(for: view) == nil
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
}

extension Dictionary where Key == HashableRect, Value == MaskDecision {
    /// Records `decision` for `rect`, keeping whichever decision has higher priority
    /// when the same rect is reached twice.
    mutating func record(_ decision: MaskDecision, at rect: HashableRect) {
        if let existing = self[rect], existing >= decision { return }
        self[rect] = decision
    }
}
