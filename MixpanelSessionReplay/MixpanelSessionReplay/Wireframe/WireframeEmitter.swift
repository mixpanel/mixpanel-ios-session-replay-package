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

  /// Hash of the last published ``WireframePayload`` — i.e. of exactly the bytes
  /// that went on the wire, after geometric masking, sensitive rules,
  /// glyph/blank normalization, and truncation.
  ///
  /// Hashing the *finished* payload rather than the raw walker output is
  /// deliberate. The ERD defines dedup as "identical renders collapse to one",
  /// and only the payload determines the render. Raw elements are a strictly
  /// worse key: text that differs upstream but processes to the same wire value
  /// — a masked field being typed into, a value the same redact rule rewrites
  /// each frame — re-emits a byte-identical event on every capture, which is
  /// exactly the churn dedup exists to kill. Raw elements also miss truncation,
  /// which happens at serialization here.
  ///
  /// This subsumes the old separate mask-bounds hash. Mask rects are not on the
  /// wire; they matter only through the text they strip, which is already baked
  /// into the payload. A mask that moves without changing any element's text
  /// produces an identical render and should dedup. Matches Android's
  /// `lastPayloadHash` and Flutter's `_lastPayloadHash`.
  private var lastPayloadHash: Int?

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

  /// Hop off the main thread and run Layers 2 and 4, dedup, serialize, and
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
  ///
  /// Dedup is scoped to a *recording session*, but this emitter is built once per SDK
  /// lifetime and survives a stop/start cycle — so the boundary has to be announced.
  /// `MPSessionReplayInstance.startRecording` calls this right after
  /// `SessionManager.generateNewSession()`, which is the only place a new replay id is
  /// minted. Without it, a background/foreground onto an unchanged screen compares the
  /// new replay's first frame against the *previous* replay's last one and dedups it
  /// away, shipping an opening screenshot with no `mp_wireframe` to describe it.
  func resetDedup() {
    hashLock.write {
      self.lastPayloadHash = nil
    }
  }

  #if DEBUG
    /// Test-only seam: whether a previous emit's payload hash is still held, i.e.
    /// whether the next identical frame would dedup. Exists so the session-boundary
    /// reset can be asserted at the `startRecording` call site rather than only on
    /// ``resetDedup()`` itself — a test that calls `resetDedup()` directly cannot
    /// catch the call site being dropped.
    var hasDedupStateForTesting: Bool {
      var held = false
      hashLock.read { held = self.lastPayloadHash != nil }
      return held
    }
  #endif

  #if DEBUG
    /// Test-only seam. Runs Layers 2 and 4 (geometric leak-prevention + sensitive
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
    // Process first, dedup on the result. A deduped frame costs one pipeline
    // pass — rect intersection and regex over a few hundred elements, on a
    // utility queue — which is negligible next to the JPEG compression running
    // alongside it, and buys a key that reflects what actually ships.
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

    let payloadHash = payload.hashValue
    var shouldPublish = true
    hashLock.read {
      if self.lastPayloadHash == payloadHash {
        shouldPublish = false
      }
    }
    guard shouldPublish else { return }

    let sessionEvent = SessionEvent(
      type: EventType.custom,
      data: .customData(SessionCustomEventData(tag: WireframeEmitter.tag, payload: payload)),
      timestamp: timestamp
    )
    EventPublisher.shared.publishCustomEvent(sessionEvent)

    hashLock.write {
      self.lastPayloadHash = payloadHash
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

    // Customer-declared text (`.mpWireframeText(_:)`) is authored, not
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
}
