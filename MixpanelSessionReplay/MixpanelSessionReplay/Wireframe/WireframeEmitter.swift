//
//  WireframeEmitter.swift
//  MixpanelSessionReplay
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

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

  /// Bumped by ``resetDedup()``; identifies the recording session a frame was
  /// captured in.
  ///
  /// ``emit(elements:viewport:maskBounds:capturedAtMs:)`` stamps each frame with
  /// the epoch current at capture time, and ``processAndPublish`` drops any frame
  /// whose stamp is stale. Without it the reset races the work queue: a frame
  /// queued by the outgoing session can finish *after* the reset and restore the
  /// old hash, so the new session's first frame — identical, because the screen
  /// never changed — is deduped away again, which is exactly what the reset
  /// exists to prevent. Dropping the stale frame is also the right outcome on its
  /// own: it describes a screen from a replay that has already ended, and
  /// `startRecording` triggers a fresh capture immediately.
  private var dedupEpoch: UInt64 = 0

  /// Hash of the last published payload, or `nil` when no frame has been
  /// published since the last ``resetDedup()`` — i.e. whether the next identical
  /// frame would dedup.
  ///
  /// Exposed so the session-boundary reset can be asserted at the
  /// `startRecording` call site rather than only on ``resetDedup()`` itself; a
  /// test that calls `resetDedup()` directly cannot catch the call site being
  /// dropped.
  var currentPayloadHash: Int? {
    var hash: Int?
    hashLock.read { hash = self.lastPayloadHash }
    return hash
  }

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
    // Stamped here, at capture time, not inside the queued work — the point is to
    // record which session this frame belongs to before a reset can intervene.
    var epoch: UInt64 = 0
    hashLock.read { epoch = self.dedupEpoch }
    workQueue.async { [weak self] in
      self?.processAndPublish(
        elements: elements,
        viewport: viewport,
        maskBounds: maskBounds,
        timestamp: capturedAtMs,
        epoch: epoch
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
  ///
  /// Ordered against in-flight work through ``dedupEpoch``, so a frame the outgoing
  /// session already queued cannot land after the reset and restore its hash.
  func resetDedup() {
    hashLock.write {
      self.lastPayloadHash = nil
      self.dedupEpoch &+= 1
    }
  }

  // MARK: - Pipeline

  /// Runs Layers 2 and 4 (geometric leak-prevention + sensitive rules) over one
  /// element, returning it with `text` and `decision` updated. `internal` rather
  /// than `private` so tests can drive the same code production does instead of
  /// a test-only entry point.
  func applyMaskingPipeline(
    _ element: WireframeElement,
    maskBounds: Set<HashableRect>
  ) -> WireframeElement {
    // Layer 1 already decided — trust it. `.declared` is the one decision that
    // continues through the pipeline: Layer 3 substituted the text, but the
    // sensitive rules still run over it.
    guard element.decision == .none || element.decision == .declared else {
      return element
    }
    // No text to scrub: skip both layers. The only emptiness check in the
    // pipeline — a rule's own search text needs none, see `applyRules`.
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

  /// Final text an element ships with: normalization then truncation.
  ///
  /// Declared text skips normalization — it is authored by the developer, not
  /// scraped, so it is taken verbatim rather than second-guessed for blankness
  /// or glyph content. It is still truncated. Mirrors Flutter's
  /// `_cleanText` / `_truncate` ordering.
  ///
  /// `internal` for the same reason as ``applyMaskingPipeline(_:maskBounds:)``.
  func wireText(for element: WireframeElement) -> String? {
    let cleaned = element.isDeclared ? element.text : cleanTextForWire(element.text)
    return cleaned.flatMap(truncateForWire)
  }

  // MARK: - Private

  private func processAndPublish(
    elements: [WireframeElement],
    viewport: (width: Int, height: Int),
    maskBounds: Set<HashableRect>,
    timestamp: Int64,
    epoch: UInt64
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

    // Compare and claim under one write barrier: a `read` to test followed by a
    // `write` to store leaves a window where a concurrent `resetDedup()` lands in
    // between and gets overwritten by the frame it was meant to clear.
    let payloadHash = payload.hashValue
    var shouldPublish = false
    hashLock.write {
      // Stale frame: captured before the session boundary, so it describes a
      // replay that has already ended. Dropping it also keeps it from restoring
      // this hash over the reset.
      guard epoch == self.dedupEpoch else { return }
      guard self.lastPayloadHash != payloadHash else { return }
      self.lastPayloadHash = payloadHash
      shouldPublish = true
    }
    guard shouldPublish else { return }

    let sessionEvent = SessionEvent(
      type: EventType.custom,
      data: .customData(SessionCustomEventData(tag: WireframeEmitter.tag, payload: payload)),
      timestamp: timestamp
    )
    EventPublisher.shared.publishCustomEvent(sessionEvent)

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

  /// Runs Layer 4: the configured ``MPSensitiveRule``s, in declared order.
  ///
  /// A rule declared with empty search text is inert, and needs no guard of its
  /// own to be: Foundation's `range(of:)` reports no match for an empty search
  /// string, and `replacingOccurrences(of:)` returns the receiver unchanged.
  /// `WireframeEmitterTests.testEmptyRuleText_isInert_ratherThanMatchingEverything`
  /// pins that, since it is the reason nothing here has to check.
  ///
  /// The rule's search text is named `ruleText` rather than shadowing `text`: the
  /// two are different strings — `text` is the element's own content, `ruleText`
  /// is the pattern being looked for in it.
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
      case .strip(let ruleText):
        if current.range(of: ruleText, options: .caseInsensitive) != nil {
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
      case .redact(let ruleText, let replacement):
        if current.range(of: ruleText, options: .caseInsensitive) != nil {
          current = current.replacingOccurrences(
            of: ruleText, with: replacement, options: .caseInsensitive)
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
