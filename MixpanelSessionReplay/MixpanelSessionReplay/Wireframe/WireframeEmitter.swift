//
//  WireframeEmitter.swift
//  MixpanelSessionReplay
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import CoreGraphics
import Foundation

/// Runs Layer 2 (geometric leak-prevention) and Layer 3 (sensitive rules) on
/// wireframe elements produced by the view walker (Layer 1), dedups against
/// the previous emit, serializes as an rrweb Custom event, and publishes it
/// to the session replay stream.
final class WireframeEmitter {
  static let tag = "mp_wireframe"

  /// Maximum characters on the wire for an element's text, **including** the
  /// ellipsis appended when it is cut. Matches Android's `MAX_TEXT_LEN`,
  /// Flutter's `WireframeConstants.maxTextLength`, and the service's
  /// `MAX_ELEMENT_TEXT` budget.
  static let maxTextLength = 50

  /// Appended when text is truncated. Paid for out of ``maxTextLength``, not
  /// added on top of it — so a truncated value is exactly `maxTextLength`
  /// characters, never one more.
  static let ellipsis = "…"

  private let sensitiveRules: [MPSensitiveRule]
  private let debugEmitter: ((MPWireframeDebugSnapshot) -> Void)?

  private let workQueue = DispatchQueue(
    label: "com.mixpanel.session.replay.wireframe", qos: .utility)
  private let debugQueue = DispatchQueue(
    label: "com.mixpanel.session.replay.wireframe.debug", qos: .utility)

  private let hashLock = ReadWriteLock(label: "com.mixpanel.session.replay.wireframe.hash")
  private var lastElementsHash: Int?
  private var lastMaskHash: Int?

  /// - Parameters:
  ///   - options: The wireframe capture options. `wireframesOptions` is the
  ///     single switch that turns capture on.
  ///   - debugEmitter: `DebugOptions.wireframeEmitter`. Only *observes* the
  ///     capture this emitter performs — passing it alone never starts one.
  init(
    options: MPWireframesOptions,
    debugEmitter: ((MPWireframeDebugSnapshot) -> Void)? = nil
  ) {
    self.sensitiveRules = Array(options.sensitiveRules)
    self.debugEmitter = debugEmitter
  }

  /// Hop off the main thread and run Layers 2+3, dedup, serialize, and
  /// publish. Safe to call from any thread. Returns immediately.
  ///
  /// - Parameter capturedAtMs: Wall-clock instant the frame this wireframe
  ///   describes was captured. Callers in the capture path must pass the same
  ///   value the screenshot event is stamped with, so the pair describes one
  ///   moment; reading the clock here instead would date the wireframe to
  ///   whenever rendering happened to finish. Matches Android's
  ///   `WireframeEmitter.emit(capturedAtMs)` and Flutter's `captureTimestamp`.
  func emit(
    elements: [WireframeElement],
    viewport: (width: Int, height: Int),
    maskBounds: Set<HashableRect>,
    capturedAtMs: Int64 = TimestampUtils.timestamp()
  ) {
    workQueue.async { [weak self] in
      self?.processAndPublish(
        elements: elements,
        viewport: viewport,
        maskBounds: maskBounds,
        timestamp: capturedAtMs
      )
    }
  }

  /// Reset dedup state so the next emit publishes even if identical.
  /// Useful when tearing down or switching sessions.
  func resetDedup() {
    hashLock.write {
      self.lastElementsHash = nil
      self.lastMaskHash = nil
    }
  }

  #if DEBUG
    /// Test-only seam. Runs Layers 2+3 (geometric leak-prevention + sensitive
    /// rules) and applies the same wire text cleaning + truncation that
    /// `processAndPublish` ships, returning the final elements with `decision`
    /// preserved. Lets golden tests assert the *whole* pipeline — including
    /// **why** an element's text was dropped — rather than only the stripped
    /// wire DTO, which carries no decision. Never called in production;
    /// synchronous and side-effect-free (no publish, no dedup mutation).
    /// Mirrors Android's `WireframeEmitter.processForTesting(elements:maskBounds:)`.
    func processedElementsForTesting(
      elements: [WireframeElement],
      maskBounds: Set<HashableRect>
    ) -> [WireframeElement] {
      elements.map { element in
        var processed = applyMaskingPipeline(element, maskBounds: maskBounds)
        processed.text = wireText(for: processed)
        return processed
      }
    }
  #endif

  // MARK: - Private

  private func processAndPublish(
    elements: [WireframeElement],
    viewport: (width: Int, height: Int),
    maskBounds: Set<HashableRect>,
    timestamp: Int64
  ) {
    let elementsHash = hashElements(elements)
    let maskHash = maskBounds.hashValue

    var shouldPublish = true
    hashLock.read {
      if self.lastElementsHash == elementsHash && self.lastMaskHash == maskHash {
        shouldPublish = false
      }
    }
    guard shouldPublish else { return }

    let processed = elements.map { element in
      applyMaskingPipeline(element, maskBounds: maskBounds)
    }

    let payload = WireframePayload(
      viewport: [viewport.width, viewport.height],
      elements: processed.map { element in
        WireframeElementJson(
          role: element.role.wireName,
          text: wireText(for: element),
          bounds: [element.x, element.y, element.w, element.h]
        )
      }
    )

    let sessionEvent = SessionEvent(
      type: EventType.custom,
      data: .customData(SessionCustomEventData(tag: WireframeEmitter.tag, payload: payload)),
      timestamp: timestamp
    )
    EventPublisher.shared.publishCustomEvent(sessionEvent)

    hashLock.write {
      self.lastElementsHash = elementsHash
      self.lastMaskHash = maskHash
    }

    if let debugEmitter {
      let snapshot = MPWireframeDebugSnapshot(
        timestamp: timestamp,
        viewport: [viewport.width, viewport.height],
        elements: processed.map { element in
          MPWireframeDebugSnapshot.DebugElement(
            role: element.role.wireName,
            text: wireText(for: element),
            bounds: [element.x, element.y, element.w, element.h],
            maskDecision: element.decision
          )
        }
      )
      debugQueue.async {
        debugEmitter(snapshot)
      }
    }
  }

  private func applyMaskingPipeline(
    _ element: WireframeElement,
    maskBounds: Set<HashableRect>
  ) -> WireframeElement {
    // Layer 1 already decided — trust it. `.declared` is the one decision that
    // continues through the pipeline: Layer 3 substituted the text, but the
    // sensitive rules still run over it.
    guard element.decision == .none || element.decision == .declared else {
      return element
    }
    guard let originalText = element.text, !originalText.isEmpty else {
      return element
    }

    // Customer-declared text (`.mpReplay(wireframeText:)`) is authored, not
    // scraped, and is intentionally sent even when the view is masked. Skip the
    // geometric strip — otherwise the view's own mask region would null it —
    // but still run the configured sensitive rules below as a safety net.
    if !element.isDeclared {
      if let geometric = applyGeometricStrip(element, maskBounds: maskBounds) {
        return geometric
      }
    }

    return applyRules(element, text: originalText)
  }

  private func applyGeometricStrip(
    _ element: WireframeElement,
    maskBounds: Set<HashableRect>
  ) -> WireframeElement? {
    guard !maskBounds.isEmpty else { return nil }
    let elementRect = CGRect(x: element.x, y: element.y, width: element.w, height: element.h)
    for rect in maskBounds where rect.cgRect.intersects(elementRect) {
      var stripped = element
      stripped.text = nil
      stripped.decision = .geometric
      return stripped
    }
    return nil
  }

  private func applyRules(_ element: WireframeElement, text: String) -> WireframeElement {
    var current = text
    var redacted = false
    for rule in sensitiveRules {
      switch rule {
      case .stripRegex(let regex):
        if hasMatch(regex, in: current) {
          var stripped = element
          stripped.text = nil
          stripped.decision = .ruleStrip
          return stripped
        }
      case .strip(let text):
        if !text.isEmpty, current.range(of: text, options: .caseInsensitive) != nil {
          var stripped = element
          stripped.text = nil
          stripped.decision = .ruleStrip
          return stripped
        }
      case .redactRegex(let regex, let replacement):
        if hasMatch(regex, in: current) {
          current = replaceLiteral(regex: regex, in: current, replacement: replacement)
          redacted = true
        }
      case .redact(let text, let replacement):
        if !text.isEmpty, current.range(of: text, options: .caseInsensitive) != nil {
          current = current.replacingOccurrences(
            of: text, with: replacement, options: .caseInsensitive)
          redacted = true
        }
      }
    }
    if redacted {
      var rewritten = element
      rewritten.text = current
      rewritten.decision = .ruleRedact
      return rewritten
    }
    return element
  }

  private func hasMatch(_ regex: NSRegularExpression, in string: String) -> Bool {
    let range = NSRange(string.startIndex..<string.endIndex, in: string)
    return regex.firstMatch(in: string, options: [], range: range) != nil
  }

  /// Runs a regex replace where the replacement string is emitted verbatim —
  /// `$1`, `\1`, etc. are NOT interpreted as back-references. Matches the
  /// contract Android's `regex.replace(current) { rule.replacement }` locks in.
  private func replaceLiteral(
    regex: NSRegularExpression, in string: String, replacement: String
  ) -> String {
    let escaped = NSRegularExpression.escapedTemplate(for: replacement)
    let mutable = NSMutableString(string: string)
    let range = NSRange(location: 0, length: mutable.length)
    regex.replaceMatches(in: mutable, options: [], range: range, withTemplate: escaped)
    return mutable as String
  }

  /// Final text an element ships with: normalization then truncation.
  ///
  /// Declared text skips normalization — it is authored by the developer, not
  /// scraped, so it is taken verbatim rather than second-guessed for blankness
  /// or glyph content. It is still truncated. Mirrors Flutter's
  /// `_cleanText` / `_truncate` ordering.
  private func wireText(for element: WireframeElement) -> String? {
    let cleaned = element.isDeclared ? element.text : cleanTextForWire(element.text)
    return cleaned.flatMap(truncateForWire)
  }

  /// Normalize an unmasked element's text for the wire *without dropping the
  /// element*: blank/whitespace-only text and bare icon-font glyphs become
  /// `nil`, but the role + bounds shell is always kept (Wireframe Capture
  /// Contract). Masked elements already carry `nil` text and pass through.
  /// Mirrors Flutter's `_cleanText` and the Android equivalent so all three
  /// platforms null the same content.
  private func cleanTextForWire(_ text: String?) -> String? {
    guard let text else { return nil }
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
    if !WireframeEmitter.isHumanReadable(text) { return nil }
    return text
  }

  /// True if `text` contains at least one character outside the Unicode
  /// private-use area (U+E000–U+F8FF), where icon fonts place their glyphs.
  /// A string that fails this check is a bare icon glyph, not human-readable
  /// content. Matches Flutter's `wireframeTextIsHumanReadable`.
  static func isHumanReadable(_ text: String) -> Bool {
    for scalar in text.unicodeScalars {
      if scalar.value < 0xE000 || scalar.value > 0xF8FF { return true }
    }
    return false
  }

  /// Caps text at ``maxTextLength`` characters *including* the ellipsis, so the
  /// wire value never exceeds the ERD's 50-character limit. The ellipsis is
  /// kept — it tells the summarizer the label was cut rather than ending
  /// mid-word — but it is paid for out of the budget, not added on top of it.
  /// Matches Android's `truncate` and Flutter's `_truncate`.
  private func truncateForWire(_ text: String) -> String? {
    guard !text.isEmpty else { return nil }
    if text.count <= WireframeEmitter.maxTextLength { return text }
    let idx = text.index(text.startIndex, offsetBy: WireframeEmitter.maxTextLength - 1)
    return String(text[..<idx]) + WireframeEmitter.ellipsis
  }

  private func hashElements(_ elements: [WireframeElement]) -> Int {
    var hasher = Hasher()
    for element in elements {
      hasher.combine(element)
    }
    return hasher.finalize()
  }
}
