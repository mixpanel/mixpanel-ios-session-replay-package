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

/// Layer-1 output of the wireframe walker. Layers 2 and 3 mutate `text` and
/// `decision` before serialization.
struct WireframeElement: Hashable {
  var role: WireframeRole
  var text: String?
  var x: Int
  var y: Int
  var w: Int
  var h: Int
  var decision: MPMaskDecision

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
