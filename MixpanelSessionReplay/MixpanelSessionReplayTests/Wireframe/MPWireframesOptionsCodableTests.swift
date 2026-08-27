//
//  MPWireframesOptionsCodableTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import Foundation
import XCTest

@testable import MixpanelSessionReplay

/// The JSON contract for wireframe options.
///
/// React Native sends **one** config JSON to both SDKs, so this shape is shared with
/// Android's `SensitiveRuleSerializer` and its `WireframesOptionsTest`. Field names and
/// `type` tokens are asserted as literal text rather than round-tripped, because a round
/// trip stays green after a rename that silently disables every rule on one platform.
final class MPWireframesOptionsCodableTests: XCTestCase {

  private let decoder = JSONDecoder()

  private func decodeOptions(_ json: String) throws -> MPWireframesOptions {
    try decoder.decode(MPWireframesOptions.self, from: Data(json.utf8))
  }

  // MARK: - Decoding

  func test_decodesTheReactNativePayload() throws {
    let options = try decodeOptions(
      """
      {
        "sensitiveRules": [
          { "type": "strip", "text": "password" },
          { "type": "redact", "text": "SSN", "replacement": "[SSN]" },
          { "type": "stripRegex", "pattern": "\\\\d{16}" },
          { "type": "redactRegex", "pattern": "[^@]+@[^@]+", "replacement": "[EMAIL]" }
        ],
        "useAccessibilityLabelFallback": true
      }
      """)

    XCTAssertTrue(options.useAccessibilityLabelFallback)
    XCTAssertEqual(options.sensitiveRules.count, 4)

    guard case .strip(let stripText) = options.sensitiveRules[0] else {
      return XCTFail("expected .strip, got \(options.sensitiveRules[0])")
    }
    XCTAssertEqual(stripText, "password")

    guard case .redact(let redactText, let redactReplacement) = options.sensitiveRules[1] else {
      return XCTFail("expected .redact, got \(options.sensitiveRules[1])")
    }
    XCTAssertEqual(redactText, "SSN")
    XCTAssertEqual(redactReplacement, "[SSN]")

    guard case .stripRegex(let stripRegex) = options.sensitiveRules[2] else {
      return XCTFail("expected .stripRegex, got \(options.sensitiveRules[2])")
    }
    XCTAssertEqual(stripRegex.pattern, #"\d{16}"#)

    guard case .redactRegex(let redactRegex, let regexReplacement) = options.sensitiveRules[3]
    else {
      return XCTFail("expected .redactRegex, got \(options.sensitiveRules[3])")
    }
    XCTAssertEqual(redactRegex.pattern, "[^@]+@[^@]+")
    XCTAssertEqual(regexReplacement, "[EMAIL]")
  }

  /// Both fields are optional: a bridge that only wants wireframes turned on sends `{}`
  /// and must get exactly what `MPWireframesOptions()` gives a Swift caller.
  func test_emptyObjectDecodesToTheSwiftDefaults() throws {
    let options = try decodeOptions("{}")

    XCTAssertTrue(options.sensitiveRules.isEmpty)
    XCTAssertFalse(options.useAccessibilityLabelFallback)
  }

  /// `replacement` is optional, and must fall through to the same token the Swift
  /// default argument produces — and the same one Android uses.
  func test_omittedReplacementDecodesToTheSharedDefault() throws {
    let options = try decodeOptions(
      """
      {"sensitiveRules":[
        {"type":"redact","text":"SSN"},
        {"type":"redactRegex","pattern":"\\\\d+"}
      ]}
      """)

    XCTAssertEqual(MPSensitiveRule.defaultReplacement, "[REDACTED]")
    guard case .redact(_, let textReplacement) = options.sensitiveRules[0],
      case .redactRegex(_, let regexReplacement) = options.sensitiveRules[1]
    else {
      return XCTFail("unexpected rule variants: \(options.sensitiveRules)")
    }
    XCTAssertEqual(textReplacement, MPSensitiveRule.defaultReplacement)
    XCTAssertEqual(regexReplacement, MPSensitiveRule.defaultReplacement)
  }

  /// The three flags that mean the same thing in JavaScript (`i`, `m`, `s`), in
  /// `NSRegularExpression` and in Kotlin, so a bridge can pass a JS `RegExp` through
  /// unchanged.
  func test_regexFlagsMapOntoNSRegularExpressionOptions() throws {
    let options = try decodeOptions(
      """
      {"sensitiveRules":[{
        "type": "stripRegex",
        "pattern": "a.b",
        "caseInsensitive": true,
        "multiline": true,
        "dotMatchesAll": true
      }]}
      """)

    guard case .stripRegex(let regex) = options.sensitiveRules[0] else {
      return XCTFail("expected .stripRegex")
    }
    XCTAssertTrue(regex.options.contains(.caseInsensitive))
    XCTAssertTrue(regex.options.contains(.anchorsMatchLines))
    XCTAssertTrue(regex.options.contains(.dotMatchesLineSeparators))

    // Behavioral proof rather than option bookkeeping: dotMatchesAll lets `.` cross the
    // newline and caseInsensitive lets it match the capitals.
    let subject = "A\nB"
    XCTAssertEqual(
      regex.numberOfMatches(in: subject, range: NSRange(subject.startIndex..., in: subject)), 1)
  }

  func test_omittedRegexFlagsDecodeToABarePattern() throws {
    let options = try decodeOptions("""
      {"sensitiveRules":[{"type":"stripRegex","pattern":"a.b"}]}
      """)

    guard case .stripRegex(let regex) = options.sensitiveRules[0] else {
      return XCTFail("expected .stripRegex")
    }
    XCTAssertTrue(regex.options.isEmpty)
  }

  // MARK: - Encoding

  /// Encoding is the inverse of decoding, so the JSON a native Swift config produces is
  /// a payload a bridge could have sent.
  func test_rulesSurviveAnEncodeDecodeRoundTrip() throws {
    let original = MPWireframesOptions(
      sensitiveRules: [
        .strip(text: "password"),
        .redact(text: "SSN", replacement: "[SSN]"),
        .stripRegex(try NSRegularExpression(pattern: #"\d{16}"#, options: [.caseInsensitive])),
        .redactRegex(
          try NSRegularExpression(
            pattern: "a.b", options: [.anchorsMatchLines, .dotMatchesLineSeparators]),
          replacement: "[X]"),
      ],
      useAccessibilityLabelFallback: true)

    let decoded = try decoder.decode(
      MPWireframesOptions.self, from: try JSONEncoder().encode(original))

    XCTAssertTrue(decoded.useAccessibilityLabelFallback)
    XCTAssertEqual(decoded.sensitiveRules.count, 4)
    guard case .strip(let stripText) = decoded.sensitiveRules[0],
      case .redact(let redactText, let redactReplacement) = decoded.sensitiveRules[1],
      case .stripRegex(let stripRegex) = decoded.sensitiveRules[2],
      case .redactRegex(let redactRegex, let regexReplacement) = decoded.sensitiveRules[3]
    else {
      return XCTFail("variants changed across the round trip: \(decoded.sensitiveRules)")
    }
    XCTAssertEqual(stripText, "password")
    XCTAssertEqual(redactText, "SSN")
    XCTAssertEqual(redactReplacement, "[SSN]")
    XCTAssertEqual(stripRegex.pattern, #"\d{16}"#)
    XCTAssertEqual(stripRegex.options, [.caseInsensitive])
    XCTAssertEqual(redactRegex.pattern, "a.b")
    XCTAssertEqual(redactRegex.options, [.anchorsMatchLines, .dotMatchesLineSeparators])
    XCTAssertEqual(regexReplacement, "[X]")
  }

  /// The `type` tag is spelled the same way Android spells it. Asserted against the
  /// encoded text so a rename cannot pass by round-tripping against itself.
  func test_encodedTypeTokensMatchTheCrossPlatformSpelling() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys

    let cases: [(MPSensitiveRule, String)] = [
      (.redact(text: "a"), "redact"),
      (.strip(text: "a"), "strip"),
      (.redactRegex(try NSRegularExpression(pattern: "a")), "redactRegex"),
      (.stripRegex(try NSRegularExpression(pattern: "a")), "stripRegex"),
    ]

    for (rule, token) in cases {
      let json = String(decoding: try encoder.encode(rule), as: UTF8.self)
      XCTAssertTrue(json.contains("\"type\":\"\(token)\""), "expected type \(token) in \(json)")
    }
  }

  // MARK: - Failures are loud

  /// A rule the caller wrote to remove sensitive text must never fail open. Every
  /// malformed shape throws, which the bridge turns into a rejected `initialize` — loud,
  /// at integration time, instead of an SDK that quietly redacts nothing.
  func test_malformedRulesThrowRatherThanBeingDropped() {
    let malformed: [String: String] = [
      "unknown type": #"{"sensitiveRules":[{"type":"obliterate","text":"x"}]}"#,
      "redact without text": #"{"sensitiveRules":[{"type":"redact"}]}"#,
      "strip without text": #"{"sensitiveRules":[{"type":"strip"}]}"#,
      "stripRegex without pattern": #"{"sensitiveRules":[{"type":"stripRegex"}]}"#,
      "redactRegex without pattern": #"{"sensitiveRules":[{"type":"redactRegex"}]}"#,
      "uncompilable pattern": #"{"sensitiveRules":[{"type":"stripRegex","pattern":"a(b"}]}"#,
    ]

    for (label, payload) in malformed {
      XCTAssertThrowsError(try decodeOptions(payload), label)
    }
  }

  // MARK: - Through the config

  /// Wireframes reach React Native through the one config JSON the bridge already
  /// sends, so `wireframesOptions` has to survive `MPSessionReplayConfig` decoding — it
  /// was excluded from `CodingKeys` until RN needed it.
  func test_configJSONCarriesWireframesOptionsEndToEnd() throws {
    let json = """
      {
        "wifiOnly": true,
        "recordingSessionsPercent": 100,
        "autoMaskedViews": ["text"],
        "autoStartRecording": true,
        "flushInterval": 10,
        "enableLogging": false,
        "remoteSettingsMode": "disabled",
        "debugOptions": null,
        "enableSessionReplayOniOS26AndLater": true,
        "serverURL": "https://api.mixpanel.com",
        "wireframesOptions": {
          "sensitiveRules": [{ "type": "strip", "text": "password" }],
          "useAccessibilityLabelFallback": true
        }
      }
      """

    let config = try MPSessionReplayConfig.from(json: Data(json.utf8))

    let options = try XCTUnwrap(config.wireframesOptions)
    XCTAssertTrue(options.useAccessibilityLabelFallback)
    guard case .strip(let text) = try XCTUnwrap(options.sensitiveRules.first) else {
      return XCTFail("expected .strip")
    }
    XCTAssertEqual(text, "password")
  }

  /// Wireframes stay opt-in for every integration that does not ask for them: an
  /// existing React Native config JSON has no `wireframesOptions` key at all, and must
  /// leave capture off.
  func test_configJSONWithoutWireframesOptionsLeavesCaptureOff() throws {
    let json = """
      {
        "wifiOnly": true,
        "recordingSessionsPercent": 100,
        "autoMaskedViews": ["text"],
        "autoStartRecording": true,
        "flushInterval": 10,
        "enableLogging": false,
        "remoteSettingsMode": "disabled",
        "debugOptions": null,
        "enableSessionReplayOniOS26AndLater": true,
        "serverURL": "https://api.mixpanel.com"
      }
      """

    XCTAssertNil(try MPSessionReplayConfig.from(json: Data(json.utf8)).wireframesOptions)
  }
}
