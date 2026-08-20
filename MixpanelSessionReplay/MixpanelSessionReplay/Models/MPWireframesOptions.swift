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
/// ### Checking what you're sending
///
/// While wireframes are on, ``DebugOptions/wireframeEmitter`` hands each frame
/// back to you as it is captured, along with the reason every element's text
/// was kept or removed. It *observes* capture; it does not enable it, so
/// setting it without `wireframesOptions` is a no-op.
public struct MPWireframesOptions {
  /// Content-level rules applied to each element's text before it is sent, in
  /// the order you declare them. Elements are always kept; only their text is
  /// affected.
  ///
  /// - A matching `.strip` / `.stripRegex` rule drops the text and stops — no
  ///   later rule runs.
  /// - `.redact` / `.redactRegex` rules build on one another: a rule declared
  ///   later sees the result of the ones before it, not the original text.
  ///
  /// Empty by default.
  public var sensitiveRules: [MPSensitiveRule]

  /// Whether an element with no text of its own may fall back to its
  /// `accessibilityLabel`. On by default: for icons and image buttons the
  /// label is usually the only description of what the element is for, and
  /// without it they are sent as bare `role + bounds` shells.
  ///
  /// The label is only ever the third tier of the text precedence chain:
  /// 1. Text declared with `.mpWireframeText(_:)` — always wins, and is
  ///    never gated by this flag.
  /// 2. The element's own rendered text (a `UILabel`'s `text`, a `UIButton`'s
  ///    title, …).
  /// 3. `accessibilityLabel` — reached only when 1 and 2 are absent, **and**
  ///    only when this is `true`.
  ///
  /// Turn it off if your labels might hold anything you would not want sent. A
  /// label is not drawn on screen, so unlike visible text you cannot confirm
  /// what it contains by watching the replay — which also means turning this
  /// off leaves you no way to describe an icon except
  /// `.mpWireframeText(_:)`.
  ///
  /// This changes what an element *says*, never which pixels are masked: a
  /// masked element stays textless either way, and ``sensitiveRules`` still run
  /// over whatever text is emitted.
  public var useAccessibilityLabelFallback: Bool

  public init(
    sensitiveRules: [MPSensitiveRule] = [],
    useAccessibilityLabelFallback: Bool = true
  ) {
    self.sensitiveRules = sensitiveRules
    self.useAccessibilityLabelFallback = useAccessibilityLabelFallback
  }
}
