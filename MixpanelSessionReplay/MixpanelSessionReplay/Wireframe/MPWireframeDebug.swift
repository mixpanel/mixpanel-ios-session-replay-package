//
//  MPWireframeDebug.swift
//  MixpanelSessionReplay
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import Foundation

/// Why a wireframe element's text was preserved, rewritten, or dropped.
///
/// Reported through ``MPWireframeDebugSnapshot`` for local inspection only.
///
/// ⚠️ Not a stable contract — case names and semantics may change.
public enum MPMaskDecision: String, Codable {
  /// Text emitted as-is.
  case none
  /// Explicitly marked sensitive by the app
  /// (`addSensitiveClass`, `mpReplaySensitive = true`, or the
  /// `.mpReplaySensitive(true)` SwiftUI modifier).
  case explicit
  /// Automatically masked because it matched an `MPAutoMaskedViews` category
  /// (text, image, web, map).
  case auto
  /// Text-entry field — always masked, cannot be overridden.
  case textEntry
  /// Bounds intersected a mask rect the screenshot painted over.
  /// Prevents leaks when a sensitive parent covers a non-sensitive child on
  /// the screenshot but the child's text would otherwise pass through.
  case geometric
  /// Matched a `.strip` / `.stripRegex` rule; text was dropped.
  case ruleStrip
  /// Matched a `.redact` / `.redactRegex` rule; text was rewritten.
  case ruleRedact
}

/// A per-frame snapshot of the wireframe pass, delivered to
/// ``MPWireframesOptions/debugEmitter`` for local inspection.
///
/// ⚠️ Not a stable contract — the JSON shape and field names may change.
/// Never sent to Mixpanel.
public struct MPWireframeDebugSnapshot {
  public let timestamp: Int64
  public let viewport: [Int]
  public let elements: [DebugElement]

  public struct DebugElement {
    public let role: String
    public let text: String?
    public let bounds: [Int]
    public let maskDecision: MPMaskDecision
  }

  public init(
    timestamp: Int64,
    viewport: [Int],
    elements: [DebugElement]
  ) {
    self.timestamp = timestamp
    self.viewport = viewport
    self.elements = elements
  }

  /// Debug JSON — NOT a stable contract.
  public func toJson() -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let dto = DebugSnapshotJSON(
      timestamp: timestamp,
      viewport: viewport,
      elements: elements.map { e in
        DebugSnapshotJSON.Element(
          role: e.role,
          text: e.text,
          bounds: e.bounds,
          maskDecision: e.maskDecision.rawValue
        )
      }
    )
    guard let data = try? encoder.encode(dto),
      let json = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }
    return json
  }
}

private struct DebugSnapshotJSON: Encodable {
  let timestamp: Int64
  let viewport: [Int]
  let elements: [Element]
  struct Element: Encodable {
    let role: String
    let text: String?
    let bounds: [Int]
    let maskDecision: String
  }
}
