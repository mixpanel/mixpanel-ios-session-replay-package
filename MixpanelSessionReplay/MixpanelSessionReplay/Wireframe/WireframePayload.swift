//
//  WireframePayload.swift
//  MixpanelSessionReplay
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import Foundation

/// Wire DTO for the `mp_wireframe` custom event payload.
struct WireframePayload: Codable, Equatable {
  let viewport: [Int]?
  let elements: [WireframeElementJson]
}

struct WireframeElementJson: Codable, Equatable {
  /// "text" | "button" | "input" | "image"
  let role: String
  /// Truncated to 60 chars + "…" at emit time; `nil` for masked or empty.
  let text: String?
  /// `[x, y, w, h]` in window-relative pixels.
  let bounds: [Int]
}
