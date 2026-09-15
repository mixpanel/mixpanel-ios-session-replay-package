//
//  WireframeElement.swift
//  MixpanelSessionReplay
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import Foundation

/// What kind of thing an element is, as reported to the summarizer.
///
/// A **closed** set, deliberately. The role is the one field the masking pipeline never
/// touches — Layers 1–4 mask, strip and redact `text`, and nothing filters `role` — so a role
/// sourced from developer-supplied text would be a channel that bypasses masking entirely.
/// Every value here is produced by mapping a platform enum or trait bitmask, never by
/// forwarding a string, so that channel does not exist.
///
/// The first four come from view type. The rest come from accessibility traits, which is
/// developer-declared intent rather than inference, and are therefore only as complete as the
/// app's own accessibility annotations. Coverage differs by platform on purpose: iOS collapses
/// most of React Native's `accessibilityRole` values to `UIAccessibilityTraitNone`, so only
/// ``button``, ``link`` and ``header`` are distinguishable here, while Android can read its
/// full role enum. Reporting what a platform can actually see beats reporting the intersection.
enum WireframeRole: String, Hashable {
    case text
    case button
    case input
    case image
    case link
    case header
    case checkbox
    case `switch`
    case radio
    case tab

    var wireName: String { rawValue }
}

/// Output of the wireframe walker, which runs Layer 1 (view-level masking) and
/// Layer 3 (declared-text substitution). Layers 2 (geometric leak prevention)
/// and 4 (sensitive rules) mutate `text` and `decision` before serialization.
///
/// ``MPMaskDecision/declared`` marks text the customer authored via
/// `.mpWireframeText(_:)` rather than text scraped from a rendered view.
/// Declared text is authored and trusted, so it is exempt from the geometric
/// leak-prevention strip (Layer 2) — including its own sensitive mask region.
/// Configured sensitive rules (Layer 4) still apply as a safety net, and may
/// replace the decision with ``MPMaskDecision/ruleStrip`` /
/// ``MPMaskDecision/ruleRedact``. Mirrors Android's `MaskDecision.DECLARED`
/// and Flutter's `MaskDecision.declared`.
struct WireframeElement: Hashable {
    var role: WireframeRole
    var text: String?
    var x: Int
    var y: Int
    var w: Int
    var h: Int
    var decision: MPMaskDecision

    /// True when this element's text was authored by the customer rather than
    /// scraped from the view.
    var isDeclared: Bool { decision == .declared }

    static func from(
        role: WireframeRole,
        text: String?,
        rect: CGRect,
        decision: MPMaskDecision
    ) -> WireframeElement {
        WireframeElement(
            role: role,
            text: text,
            x: Int(rect.origin.x.rounded()),
            y: Int(rect.origin.y.rounded()),
            w: Int(rect.size.width.rounded()),
            h: Int(rect.size.height.rounded()),
            decision: decision
        )
    }
}
