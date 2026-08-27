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
  case redact(text: String, replacement: String = MPSensitiveRule.defaultReplacement)
  case strip(text: String)
  case redactRegex(NSRegularExpression, replacement: String = MPSensitiveRule.defaultReplacement)
  case stripRegex(NSRegularExpression)

  /// Replacement used by `.redact` / `.redactRegex` when the caller does not supply one.
  ///
  /// Shared with this type's `Decodable` conformance so a rule that omits `replacement`
  /// in JSON decodes to exactly what the Swift default would have produced, and with
  /// Android's `SensitiveRule.DEFAULT_REPLACEMENT` so both platforms redact to the same
  /// token.
  public static let defaultReplacement = "[REDACTED]"
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
  /// `accessibilityLabel`. Off by default: a label is not drawn on screen, so
  /// unlike visible text you cannot confirm what it contains by watching the
  /// replay, and labels sometimes hold more than what is shown.
  ///
  /// The label is only ever the third tier of the text precedence chain:
  /// 1. Text declared with `.mpWireframeText(_:)` — always wins, and is
  ///    never gated by this flag.
  /// 2. The element's own rendered text (a `UILabel`'s `text`, a `UIButton`'s
  ///    title, …).
  /// 3. `accessibilityLabel` — reached only when 1 and 2 are absent, **and**
  ///    only when this is `true`.
  ///
  /// Turn it on if you want icons and image buttons named: for an icon-only
  /// control the label is usually the only description of what the element is
  /// for, and with the fallback off it is sent as a bare `role + bounds` shell
  /// instead — `.mpWireframeText(_:)` is then the only way to describe it.
  ///
  /// This changes what an element *says*, never which pixels are masked: a
  /// masked element stays textless either way, and ``sensitiveRules`` still run
  /// over whatever text is emitted.
  public var useAccessibilityLabelFallback: Bool

  public init(
    sensitiveRules: [MPSensitiveRule] = [],
    useAccessibilityLabelFallback: Bool = false
  ) {
    self.sensitiveRules = sensitiveRules
    self.useAccessibilityLabelFallback = useAccessibilityLabelFallback
  }
}

// MARK: - JSON

/// JSON form of ``MPSensitiveRule``, for cross-platform bridges (React Native).
///
/// An enum with associated values — one of them an `NSRegularExpression` — has no
/// synthesized representation, so each case maps to one flat object tagged by `type`:
///
/// | `type`        | fields                                            |
/// |---------------|---------------------------------------------------|
/// | `redact`      | `text`, optional `replacement`                    |
/// | `strip`       | `text`                                            |
/// | `redactRegex` | `pattern`, optional `replacement`, optional flags |
/// | `stripRegex`  | `pattern`, optional flags                         |
///
/// The three optional flags — `caseInsensitive`, `multiline`, `dotMatchesAll` — are the
/// subset of regex options that mean the same thing in JavaScript (`i`, `m`, `s`), in
/// `NSRegularExpression` (`.caseInsensitive`, `.anchorsMatchLines`,
/// `.dotMatchesLineSeparators`) and in Kotlin, so a bridge can pass a JS `RegExp`
/// through unchanged. They default to `false`, matching a bare `RegExp` with no flags.
///
/// This shape is byte-for-byte the one Android's `SensitiveRuleSerializer` reads: React
/// Native sends *one* config JSON to both SDKs, so a rename on either side silently
/// disables rules on that platform. `MPWireframesOptionsTests` pins it as text.
///
/// A malformed rule throws rather than being skipped. A rule the caller wrote to remove
/// sensitive text must never fail open, so the error surfaces as a rejected `initialize`
/// at integration time instead of an SDK that quietly redacts nothing.
extension MPSensitiveRule: Codable {
  private enum CodingKeys: String, CodingKey {
    case type, text, pattern, replacement, caseInsensitive, multiline, dotMatchesAll
  }

  private enum RuleType: String, Codable {
    case redact, strip, redactRegex, stripRegex
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(RuleType.self, forKey: .type)
    let replacement =
      try container.decodeIfPresent(String.self, forKey: .replacement)
      ?? MPSensitiveRule.defaultReplacement

    switch type {
      case .redact:
        self = .redact(text: try container.decode(String.self, forKey: .text), replacement: replacement)
      case .strip:
        self = .strip(text: try container.decode(String.self, forKey: .text))
      case .redactRegex:
        self = .redactRegex(try MPSensitiveRule.regex(from: container), replacement: replacement)
      case .stripRegex:
        self = .stripRegex(try MPSensitiveRule.regex(from: container))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
      case .redact(let text, let replacement):
        try container.encode(RuleType.redact, forKey: .type)
        try container.encode(text, forKey: .text)
        try container.encode(replacement, forKey: .replacement)
      case .strip(let text):
        try container.encode(RuleType.strip, forKey: .type)
        try container.encode(text, forKey: .text)
      case .redactRegex(let regex, let replacement):
        try container.encode(RuleType.redactRegex, forKey: .type)
        try MPSensitiveRule.encode(regex, into: &container)
        try container.encode(replacement, forKey: .replacement)
      case .stripRegex(let regex):
        try container.encode(RuleType.stripRegex, forKey: .type)
        try MPSensitiveRule.encode(regex, into: &container)
    }
  }

  private static func regex(
    from container: KeyedDecodingContainer<CodingKeys>
  ) throws -> NSRegularExpression {
    let pattern = try container.decode(String.self, forKey: .pattern)
    var options: NSRegularExpression.Options = []
    if try container.decodeIfPresent(Bool.self, forKey: .caseInsensitive) == true {
      options.insert(.caseInsensitive)
    }
    if try container.decodeIfPresent(Bool.self, forKey: .multiline) == true {
      options.insert(.anchorsMatchLines)
    }
    if try container.decodeIfPresent(Bool.self, forKey: .dotMatchesAll) == true {
      options.insert(.dotMatchesLineSeparators)
    }
    do {
      return try NSRegularExpression(pattern: pattern, options: options)
    } catch {
      // A pattern that compiles in JavaScript can still be rejected by ICU, so this is
      // reachable from a well-formed bridge payload. Rethrow as a decoding error so the
      // caller sees "this config is bad", not an opaque ICU failure.
      throw DecodingError.dataCorruptedError(
        forKey: .pattern,
        in: container,
        debugDescription:
          "'\(pattern)' is not a valid regular expression on iOS: \(error.localizedDescription)")
    }
  }

  private static func encode(
    _ regex: NSRegularExpression,
    into container: inout KeyedEncodingContainer<CodingKeys>
  ) throws {
    try container.encode(regex.pattern, forKey: .pattern)
    try container.encode(regex.options.contains(.caseInsensitive), forKey: .caseInsensitive)
    try container.encode(regex.options.contains(.anchorsMatchLines), forKey: .multiline)
    try container.encode(
      regex.options.contains(.dotMatchesLineSeparators), forKey: .dotMatchesAll)
  }
}

/// Lets React Native turn wireframes on through the config JSON it already sends; see
/// ``MPSensitiveRule`` for the per-rule shape.
///
/// Both fields are optional, so `"wireframesOptions": {}` means "on, with the defaults" —
/// the same thing `MPWireframesOptions()` means in Swift. The synthesized conformance
/// would have required both keys, which is why this is written out.
extension MPWireframesOptions: Codable {
  private enum CodingKeys: String, CodingKey {
    case sensitiveRules, useAccessibilityLabelFallback
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      sensitiveRules: try container.decodeIfPresent([MPSensitiveRule].self, forKey: .sensitiveRules)
        ?? [],
      useAccessibilityLabelFallback: try container.decodeIfPresent(
        Bool.self, forKey: .useAccessibilityLabelFallback) ?? false)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(sensitiveRules, forKey: .sensitiveRules)
    try container.encode(useAccessibilityLabelFallback, forKey: .useAccessibilityLabelFallback)
  }
}
