//
//  MPWireframesOptions.swift
//  MixpanelSessionReplay
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import Foundation

/// A single content-level rule applied to wireframe element text.
///
/// Rules run in the order the caller declares them. Text that survives an
/// earlier rule is passed to the next.
///
/// - `.strip` / `.stripRegex` — drop the element's text entirely. The element
///   still ships (with `text = nil`) so its bounds and role remain in the
///   wireframe. Short-circuits: no later rule runs.
/// - `.redact` / `.redactRegex` — replace matches in place. The next rule
///   sees the rewritten text.
///
/// Substring text rules match case-insensitively. Regex rules honor whatever
/// options were used when the caller compiled the `NSRegularExpression`.
///
/// > Regex replacement strings are treated literally — `$1`, `\1`, etc. are
/// > emitted verbatim, not interpreted as back-references.
public enum MPSensitiveRule {
  case redact(text: String, replacement: String = "[REDACTED]")
  case strip(text: String)
  case redactRegex(NSRegularExpression, replacement: String = "[REDACTED]")
  case stripRegex(NSRegularExpression)
}

/// Configuration for the wireframe capture pass.
///
/// Setting `MPSessionReplayConfig.wireframesOptions` to a non-nil value turns
/// wireframe capture on. When nil (the default), no wireframe events are
/// emitted and the SDK behaves exactly as it did before this feature.
///
/// - Parameters:
///   - sensitiveRules: Content-level rules applied to wireframe element text.
///     Rules run in declared order.
///   - debugEmitter: Optional per-frame callback invoked with the raw
///     wireframe snapshot for local inspection. Never sent to Mixpanel.
///     ⚠️ Not a stable contract — the debug snapshot shape may change.
public struct MPWireframesOptions {
  public var sensitiveRules: [MPSensitiveRule]
  public var debugEmitter: ((MPWireframeDebugSnapshot) -> Void)?

  public init(
    sensitiveRules: [MPSensitiveRule] = [],
    debugEmitter: ((MPWireframeDebugSnapshot) -> Void)? = nil
  ) {
    self.sensitiveRules = sensitiveRules
    self.debugEmitter = debugEmitter
  }
}
