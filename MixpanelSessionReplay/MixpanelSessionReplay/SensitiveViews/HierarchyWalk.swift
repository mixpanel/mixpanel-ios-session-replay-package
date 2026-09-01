//
//  HierarchyWalk.swift
//  MixpanelSessionReplay
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import UIKit

// The state one hierarchy walk carries down (``WalkContext``) and the results it
// accumulates on the way back up (``HierarchyWalk``).
//
// Deliberately standalone rather than nested in ``SensitiveViewManager``: neither type
// extends its behaviour or reads its state. The traversal that drives them lives in
// `SensitiveViewManager+HierarchyWalk.swift`, which is genuinely an extension of the
// manager — it needs `isSensitiveView`, the registered classes and the mask caches.
// These two only need what they are handed.

/// Per-branch traversal state. A value type, so what one child sets never leaks
/// back to its siblings.
struct WalkContext {
    /// A role-bearing element already described this subtree, so a `UIButton`'s
    /// inner `UILabel` must not emit an element beside it.
    var insideWireframeLeaf = false

    /// An `mpReplaySensitive = false` ancestor was crossed.
    var insideSafeSubtree = false

    /// The wire decision of the nearest masked ancestor, or `nil` when none was
    /// crossed. Descendants inherit it: their scraped text is dropped and they
    /// report the ancestor's provenance (`.explicit` / `.auto`) rather than
    /// depending on a geometric overlap being noticed downstream.
    ///
    /// Provenance rather than geometry, because geometry is not reliable here.
    /// Layer 2 strips text only where a mask rect intersects the element's
    /// *emitted* bounds, and a descendant can be laid out clear of its masked
    /// ancestor — clipped away, scrolled out, or simply positioned outside it —
    /// and still resolve to a real rect, because ``getFrame(for:in:)`` converts
    /// to window coordinates without consulting the ancestor clip chain. That
    /// combination shipped a masked subtree's text in the clear; pinned by
    /// `test_maskedSubtree_offsetChild_doesNotShipScrapedText`. Matches Flutter,
    /// where `MaskContext.mask` propagates and `_wireframeDecision` resolves
    /// every descendant to `explicit`.
    var maskedAncestorDecision: MPMaskDecision?

    /// A masked ancestor was crossed. Its rect already covers everything below,
    /// so the walk continues only to *describe* the structure.
    ///
    /// Deliberately *not* derived from ``maskedAncestorDecision``. This one governs
    /// the mask path — ``HierarchyWalk/record(_:at:in:)`` and
    /// ``HierarchyWalk/recordSafe(_:in:)`` — and must stay set for the whole
    /// subtree, including below an unmask. Deriving it let the unmask that clears
    /// the wireframe's inheritance also clear this, which let a
    /// `mask > unmask > mpReplaySensitive(true)` nesting record an inner rect the
    /// enclosing mask had already settled. The two answer different questions: this
    /// one is "has any mask claimed this region", the other is "whose text am I".
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
/// and ``HierarchyWalk/record(_:at:in:)`` / ``HierarchyWalk/recordSafe(_:in:)`` refuse to write anything new
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
