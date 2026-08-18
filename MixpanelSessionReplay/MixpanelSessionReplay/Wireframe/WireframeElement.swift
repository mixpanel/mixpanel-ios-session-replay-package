//
//  WireframeElement.swift
//  MixpanelSessionReplay
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import CoreGraphics
import Foundation

enum WireframeRole: String, Hashable {
  case text
  case button
  case input
  case image

  var wireName: String { rawValue }
}

/// Output of the wireframe walker, which runs Layer 1 (view-level masking) and
/// Layer 3 (declared-text substitution). Layers 2 (geometric leak prevention)
/// and 4 (sensitive rules) mutate `text` and `decision` before serialization.
///
/// ``MPMaskDecision/declared`` marks text the customer authored via
/// `.mpReplay(wireframeText:)` rather than text scraped from a rendered view.
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

/// Mutable buffer carried through the view walker so subviews can append.
/// Present only when the caller opted into wireframe collection.
final class WireframeCollector {
  var elements: [WireframeElement] = []
}
