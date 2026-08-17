//
//  WireframeGoldenTestUtils.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//
//  Coordinate/golden snapshot testing for the wireframe pipeline, mirroring the
//  Flutter gold standard (`test/utils/golden_test_utils.dart`). We run the same
//  production path that ships `mp_wireframe` events —
//  `SensitiveViewManager.collectFramesAndWireframes(in:window:)` (Layer 1) →
//  `WireframeEmitter` Layers 2+3 — then serialize the result to a JSON golden.
//  An accidental text leak or a coordinate regression then surfaces as a
//  one-line diff in review.
//
//  Format matches the Flutter and Android harnesses (2-space indent, arrays
//  expanded one value per line, key order role/text/bounds/maskDecision, `text`
//  as the JSON literal `null` when absent, no trailing newline) so a reviewer can
//  eyeball parity across platforms. Coordinates differ per platform, so the files
//  themselves are never shared — only the shape is.
//
//  `maskDecision` prints ``MPMaskDecision``'s raw value, which is the same
//  SCREAMING_SNAKE spelling a developer sees through
//  ``DebugOptions/wireframeEmitter`` — matching Android. (Flutter's goldens print
//  its Dart `.name`, lowerCamel, even though its debug snapshot is
//  SCREAMING_SNAKE; each platform's goldens show that platform's native spelling.)
//

import CoreGraphics
import UIKit
import XCTest

@testable import MixpanelSessionReplay

/// Directory holding the checked-in golden JSON files, resolved from this source
/// file's location so it works regardless of the test runner's working
/// directory (and supports auto-creating a missing golden in the source tree).
private func wireframeGoldenDirectory() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Golden")
}

/// Runs the full wireframe pipeline over a laid-out view tree and asserts the
/// serialized result matches the named golden file, creating it on first run.
///
/// - Parameters:
///   - root: The subtree the walker traverses (matches production's `view`).
///   - window: The coordinate-reference view; element bounds are window-relative.
///     A plain `UIView` with manually set frames gives deterministic integer
///     coordinates; a real `UIWindow` is only needed for real SwiftUI layout.
///   - rules: Sensitive rules applied in Layer 3, in declared order.
///   - useAccessibilityLabelFallback: Mirrors
///     ``MPWireframesOptions/useAccessibilityLabelFallback``. Applied to the
///     manager for the duration of the walk, exactly as
///     `MPSessionReplayInstance` does at init.
///   - name: Golden filename, e.g. `"wireframe_text_plain.json"`.
func assertWireframeGolden(
  manager: SensitiveViewManager,
  root: UIView,
  window: UIView,
  rules: [MPSensitiveRule] = [],
  useAccessibilityLabelFallback: Bool = true,
  golden name: String,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  manager.useAccessibilityLabelFallback = useAccessibilityLabelFallback
  let (frames, elements) = manager.collectFramesAndWireframes(in: root, window: window)
  let emitter = WireframeEmitter(
    options: MPWireframesOptions(
      sensitiveRules: rules,
      useAccessibilityLabelFallback: useAccessibilityLabelFallback))
  let processed = emitter.processedElementsForTesting(
    elements: elements, maskBounds: Set(frames.keys))
  let viewport = [Int(window.bounds.width), Int(window.bounds.height)]
  assertWireframeGolden(
    processed, viewport: viewport, golden: name, file: file, line: line)
}

/// Asserts a pre-collected element list against a golden. Prefer the
/// `manager:root:window:` overload; this exists for tests that need to
/// post-process the element list first.
func assertWireframeGolden(
  _ processed: [WireframeElement],
  viewport: [Int],
  golden name: String,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  let actual = wireframeGoldenJSON(viewport: viewport, elements: processed)
  let directory = wireframeGoldenDirectory()
  let fileManager = FileManager.default
  if !fileManager.fileExists(atPath: directory.path) {
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  let url = directory.appendingPathComponent(name)

  guard let expected = try? String(contentsOf: url, encoding: .utf8) else {
    // First run: write the golden so it can be reviewed and committed. Mirrors
    // Flutter's create-and-pass convention.
    do {
      try actual.write(to: url, atomically: true, encoding: .utf8)
      print("📸 Created wireframe golden: \(name)")
    } catch {
      XCTFail("Failed to create wireframe golden \(name): \(error)", file: file, line: line)
    }
    return
  }

  XCTAssertEqual(
    actual,
    expected,
    """
    Wireframe golden mismatch for \(name).
    Delete MixpanelSessionReplayTests/Wireframe/Golden/\(name) to regenerate.
    """,
    file: file,
    line: line
  )
}

/// Serializes a processed element list to the cross-platform golden JSON.
/// Hand-built rather than `JSONEncoder` so key order and array layout exactly
/// match Dart's `JsonEncoder.withIndent('  ')` and Android's hand-built
/// equivalent. No trailing newline (matches both).
func wireframeGoldenJSON(viewport: [Int], elements: [WireframeElement]) -> String {
  var lines: [String] = []
  lines.append("{")
  lines.append("  \"viewport\": [")
  for (index, value) in viewport.enumerated() {
    lines.append("    \(value)\(index == viewport.count - 1 ? "" : ",")")
  }
  lines.append("  ],")

  if elements.isEmpty {
    lines.append("  \"elements\": []")
  } else {
    lines.append("  \"elements\": [")
    for (index, element) in elements.enumerated() {
      lines.append("    {")
      lines.append("      \"role\": \(jsonStringLiteral(element.role.wireName)),")
      lines.append("      \"text\": \(element.text.map(jsonStringLiteral) ?? "null"),")
      lines.append("      \"bounds\": [")
      lines.append("        \(element.x),")
      lines.append("        \(element.y),")
      lines.append("        \(element.w),")
      lines.append("        \(element.h)")
      lines.append("      ],")
      lines.append("      \"maskDecision\": \(jsonStringLiteral(element.decision.rawValue))")
      lines.append(index == elements.count - 1 ? "    }" : "    },")
    }
    lines.append("  ]")
  }

  lines.append("}")
  return lines.joined(separator: "\n")
}

/// Minimal JSON string escaper. Emits non-ASCII (e.g. the "…" truncation
/// ellipsis) verbatim to match Dart's default `JsonEncoder` behavior.
private func jsonStringLiteral(_ string: String) -> String {
  var out = "\""
  for scalar in string.unicodeScalars {
    switch scalar {
    case "\"": out += "\\\""
    case "\\": out += "\\\\"
    case "\n": out += "\\n"
    case "\r": out += "\\r"
    case "\t": out += "\\t"
    default:
      if scalar.value < 0x20 {
        out += String(format: "\\u%04x", scalar.value)
      } else {
        out.unicodeScalars.append(scalar)
      }
    }
  }
  out += "\""
  return out
}
