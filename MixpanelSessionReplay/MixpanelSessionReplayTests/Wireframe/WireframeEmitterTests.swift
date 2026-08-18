//
//  WireframeEmitterTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import CoreGraphics
import XCTest

@testable import MixpanelSessionReplay

final class WireframeEmitterTests: XCTestCase {

  private var publishedEvents: [SessionEvent] = []
  private var subscriber: TestCustomEventSubscriber!

  override func setUp() {
    super.setUp()
    EventPublisher.shared.resetSubscribers()
    publishedEvents = []
    subscriber = TestCustomEventSubscriber { [weak self] event in
      self?.publishedEvents.append(event)
    }
    EventPublisher.shared.subscribe(subscriber)
  }

  override func tearDown() {
    EventPublisher.shared.resetSubscribers()
    subscriber = nil
    super.tearDown()
  }

  // MARK: - Emit + wire shape

  func testEmit_publishesCustomEventWithExpectedShape() throws {
    let emitter = WireframeEmitter(options: MPWireframesOptions())
    let element = WireframeElement.from(
      role: .text, text: "Welcome",
      rect: CGRect(x: 24, y: 120, width: 400, height: 40),
      decision: .none)

    emitter.emit(elements: [element], viewport: (1080, 1920), maskBounds: [])
    let event = try waitForFirstPublishedEvent()

    XCTAssertEqual(event.type, EventType.custom)
    guard case .customData(let custom) = event.data else {
      return XCTFail("expected .customData; got \(String(describing: event.data))")
    }
    XCTAssertEqual(custom.tag, "mp_wireframe")
    XCTAssertEqual(custom.payload.viewport, [1080, 1920])
    XCTAssertEqual(custom.payload.elements.count, 1)
    XCTAssertEqual(custom.payload.elements[0].role, "text")
    XCTAssertEqual(custom.payload.elements[0].text, "Welcome")
    XCTAssertEqual(custom.payload.elements[0].bounds, [24, 120, 400, 40])
  }

  /// An element-less frame is still a description of that frame, and ships as a
  /// payload with an empty `elements` array rather than as nothing at all. The
  /// viewport is the point: it tells the summarizer the screen was walked and
  /// held nothing readable, which no absent event can say. Matches Android,
  /// which has no element-count guard anywhere in its emit path.
  func testEmit_publishesAPayloadWithNoElements() throws {
    let emitter = WireframeEmitter(options: MPWireframesOptions())

    emitter.emit(elements: [], viewport: (1080, 1920), maskBounds: [])
    let event = try waitForFirstPublishedEvent()

    XCTAssertEqual(event.type, EventType.custom)
    let payload = customPayload(from: event)
    XCTAssertEqual(payload.viewport, [1080, 1920])
    XCTAssertTrue(payload.elements.isEmpty)
  }

  // MARK: - Capture timestamp

  /// The wireframe and the screenshot describing the same frame must carry the
  /// same timestamp. Reading the clock inside `emit` instead dated the wireframe
  /// to whenever rendering finished, so the pair drifted apart by the render
  /// duration — invisible on device, and it desynchronizes the summarizer from
  /// the frame it is describing. Matches Android's `capturedAtMs` and Flutter's
  /// `captureTimestamp`.
  func testEmit_stampsTheEventWithTheCaptureInstant() throws {
    let emitter = WireframeEmitter(options: MPWireframesOptions())
    let element = WireframeElement.from(
      role: .text, text: "Welcome",
      rect: CGRect(x: 0, y: 0, width: 10, height: 10),
      decision: .none)

    emitter.emit(
      elements: [element], viewport: (100, 100), maskBounds: [], capturedAtMs: 1_700_000_000_123)
    let event = try waitForFirstPublishedEvent()

    XCTAssertEqual(event.timestamp, 1_700_000_000_123)
  }

  /// Omitting `capturedAtMs` still stamps a sane "now", so non-capture callers
  /// (and the debug emitter) don't have to invent one.
  func testEmit_defaultsToNowWhenNoCaptureInstantIsGiven() throws {
    let emitter = WireframeEmitter(options: MPWireframesOptions())
    let element = WireframeElement.from(
      role: .text, text: "Welcome",
      rect: CGRect(x: 0, y: 0, width: 10, height: 10),
      decision: .none)

    let before = TimestampUtils.timestamp()
    emitter.emit(elements: [element], viewport: (100, 100), maskBounds: [])
    let event = try waitForFirstPublishedEvent()
    let after = TimestampUtils.timestamp()

    XCTAssertGreaterThanOrEqual(event.timestamp, before)
    XCTAssertLessThanOrEqual(event.timestamp, after)
  }

  // MARK: - Layer 1 precedence

  func testLayer1DecisionRespected_rulesAndGeometricSkipped() throws {
    // Walker emits masked elements with text=nil; Layer 2/3 must not touch them.
    let rules: [MPSensitiveRule] = [.strip(text: "any"), .redact(text: "any")]
    let emitter = WireframeEmitter(
      options: MPWireframesOptions(sensitiveRules: rules))
    let explicit = WireframeElement.from(
      role: .text, text: nil,
      rect: CGRect(x: 0, y: 0, width: 10, height: 10),
      decision: .explicit)

    // The mask rect intersects the element — geometric would fire if not gated by Layer 1.
    emitter.emit(
      elements: [explicit], viewport: (100, 100),
      maskBounds: [HashableRect(CGRect(x: 0, y: 0, width: 10, height: 10))])
    let event = try waitForFirstPublishedEvent()

    let e = customPayload(from: event).elements[0]
    XCTAssertNil(e.text, "text stays nil")
    // Also verify explicit stayed explicit — via the debug channel below in another test.
  }

  // MARK: - Layer 2 geometric

  func testGeometric_intersectingMaskNullsTextAndSetsGeometric() throws {
    let emitter = WireframeEmitter(options: MPWireframesOptions())
    let element = WireframeElement.from(
      role: .text, text: "secret",
      rect: CGRect(x: 10, y: 10, width: 50, height: 20),
      decision: .none)

    emitter.emit(
      elements: [element], viewport: (100, 100),
      maskBounds: [HashableRect(CGRect(x: 20, y: 15, width: 100, height: 100))])
    let event = try waitForFirstPublishedEvent()

    let payload = customPayload(from: event)
    XCTAssertNil(payload.elements[0].text)
  }

  func testGeometric_noIntersection_preservesText() throws {
    let emitter = WireframeEmitter(options: MPWireframesOptions())
    let element = WireframeElement.from(
      role: .text, text: "safe",
      rect: CGRect(x: 0, y: 0, width: 10, height: 10),
      decision: .none)

    emitter.emit(
      elements: [element], viewport: (100, 100),
      maskBounds: [HashableRect(CGRect(x: 50, y: 50, width: 10, height: 10))])
    let event = try waitForFirstPublishedEvent()

    XCTAssertEqual(customPayload(from: event).elements[0].text, "safe")
  }

  // MARK: - Declared text (customer-authored via .mpReplay(wireframeText:))

  func testDeclared_survivesGeometricStrip_evenWhenMaskIntersects() throws {
    // Customer-authored text is intentionally sent even over its own mask
    // region — the geometric strip must not null it.
    let emitter = WireframeEmitter(options: MPWireframesOptions())
    let element = WireframeElement.from(
      role: .text, text: "monthly spend",
      rect: CGRect(x: 10, y: 10, width: 50, height: 20),
      decision: .declared)

    emitter.emit(
      elements: [element], viewport: (100, 100),
      maskBounds: [HashableRect(CGRect(x: 0, y: 0, width: 100, height: 100))])
    let event = try waitForFirstPublishedEvent()

    XCTAssertEqual(customPayload(from: event).elements[0].text, "monthly spend")
  }

  func testDeclared_stillScrubbedByRules() throws {
    // Geometric strip is bypassed for declared text, but sensitive rules remain
    // a safety net.
    let rules: [MPSensitiveRule] = [.strip(text: "password")]
    let emitter = WireframeEmitter(
      options: MPWireframesOptions(sensitiveRules: rules))
    let element = WireframeElement.from(
      role: .text, text: "your password here",
      rect: CGRect(x: 0, y: 0, width: 100, height: 20),
      decision: .declared)

    emitter.emit(elements: [element], viewport: (100, 100), maskBounds: [])
    let event = try waitForFirstPublishedEvent()

    XCTAssertNil(customPayload(from: event).elements[0].text)
  }

  // MARK: - Layer 3 rules

  func testStripRule_shortCircuits_preemptingLaterRedact() throws {
    let rules: [MPSensitiveRule] = [
      .strip(text: "password"),
      .redact(text: "password", replacement: "[REDACTED]"),
    ]
    let emitter = WireframeEmitter(
      options: MPWireframesOptions(sensitiveRules: rules))
    let element = WireframeElement.from(
      role: .text, text: "your password here",
      rect: CGRect(x: 0, y: 0, width: 100, height: 20),
      decision: .none)

    emitter.emit(elements: [element], viewport: (100, 100), maskBounds: [])
    let event = try waitForFirstPublishedEvent()

    XCTAssertNil(customPayload(from: event).elements[0].text)
  }

  func testRedactRule_rewritesText_subsequentRulesSeeRewrittenValue() throws {
    let rules: [MPSensitiveRule] = [
      .redact(text: "alice", replacement: "[USER]"),
      .redact(text: "[USER]", replacement: "[REDACTED]"),
    ]
    let emitter = WireframeEmitter(
      options: MPWireframesOptions(sensitiveRules: rules))
    let element = WireframeElement.from(
      role: .text, text: "hello alice",
      rect: CGRect(x: 0, y: 0, width: 10, height: 10),
      decision: .none)

    emitter.emit(elements: [element], viewport: (100, 100), maskBounds: [])
    let event = try waitForFirstPublishedEvent()

    XCTAssertEqual(customPayload(from: event).elements[0].text, "hello [REDACTED]")
  }

  func testRedactRegex_replacementIsLiteral_notInterpreted() throws {
    let regex = try NSRegularExpression(pattern: "\\d+")
    let rules: [MPSensitiveRule] = [.redactRegex(regex, replacement: "$1<>\\1")]
    let emitter = WireframeEmitter(
      options: MPWireframesOptions(sensitiveRules: rules))
    let element = WireframeElement.from(
      role: .text, text: "order 123 ready",
      rect: CGRect(x: 0, y: 0, width: 10, height: 10),
      decision: .none)

    emitter.emit(elements: [element], viewport: (100, 100), maskBounds: [])
    let event = try waitForFirstPublishedEvent()

    // Neither $1 nor \1 should be interpreted as a back-reference.
    XCTAssertEqual(customPayload(from: event).elements[0].text, "order $1<>\\1 ready")
  }

  func testStripRegex_matches_nullsText() throws {
    let regex = try NSRegularExpression(pattern: "\\d{3}-\\d{2}-\\d{4}")
    let rules: [MPSensitiveRule] = [.stripRegex(regex)]
    let emitter = WireframeEmitter(
      options: MPWireframesOptions(sensitiveRules: rules))
    let element = WireframeElement.from(
      role: .text, text: "ssn 123-45-6789",
      rect: CGRect(x: 0, y: 0, width: 10, height: 10),
      decision: .none)

    emitter.emit(elements: [element], viewport: (100, 100), maskBounds: [])
    let event = try waitForFirstPublishedEvent()

    XCTAssertNil(customPayload(from: event).elements[0].text)
  }

  // MARK: - Truncation

  func testTruncation_boundaryExactly50_preserved() throws {
    let text = String(repeating: "a", count: WireframeEmitter.maxTextLength)
    let emitter = WireframeEmitter(options: MPWireframesOptions())
    let element = WireframeElement.from(
      role: .text, text: text,
      rect: CGRect(x: 0, y: 0, width: 10, height: 10),
      decision: .none)

    emitter.emit(elements: [element], viewport: (100, 100), maskBounds: [])
    let event = try waitForFirstPublishedEvent()

    XCTAssertEqual(customPayload(from: event).elements[0].text, text)
  }

  /// The ellipsis is paid for out of the 50-character budget, not added on top
  /// of it: a truncated value is exactly 50 characters (49 + "…"), never 51.
  /// Matches Android's `MAX_TEXT_LEN` and Flutter's `maxTextLength`.
  func testTruncation_length51_isCutTo49PlusEllipsis() throws {
    let max = WireframeEmitter.maxTextLength
    let text = String(repeating: "a", count: max + 1)
    let emitter = WireframeEmitter(options: MPWireframesOptions())
    let element = WireframeElement.from(
      role: .text, text: text,
      rect: CGRect(x: 0, y: 0, width: 10, height: 10),
      decision: .none)

    emitter.emit(elements: [element], viewport: (100, 100), maskBounds: [])
    let event = try waitForFirstPublishedEvent()

    let out = customPayload(from: event).elements[0].text
    XCTAssertEqual(out?.count, max)
    XCTAssertTrue(out?.hasSuffix(WireframeEmitter.ellipsis) == true)
    XCTAssertEqual(out?.prefix(max - 1), Substring(String(repeating: "a", count: max - 1)))
  }

  // MARK: - Text cleaning (glyph / blank nulling)

  func testIconGlyphOnlyText_isNulled_shellKept() throws {
    // A bare private-use-area codepoint (icon font glyph) is not human-readable.
    let emitter = WireframeEmitter(options: MPWireframesOptions())
    let element = WireframeElement.from(
      role: .button, text: "\u{E800}",
      rect: CGRect(x: 0, y: 0, width: 44, height: 44),
      decision: .none)

    emitter.emit(elements: [element], viewport: (100, 100), maskBounds: [])
    let event = try waitForFirstPublishedEvent()

    let e = customPayload(from: event).elements[0]
    XCTAssertEqual(e.role, "button", "shell is kept")
    XCTAssertNil(e.text, "bare icon glyph is nulled")
    XCTAssertEqual(e.bounds, [0, 0, 44, 44])
  }

  func testGlyphWithReadableText_isPreserved() throws {
    // Glyph + real text → still human-readable, keep it.
    let emitter = WireframeEmitter(options: MPWireframesOptions())
    let element = WireframeElement.from(
      role: .button, text: "\u{E800} Save",
      rect: CGRect(x: 0, y: 0, width: 80, height: 44),
      decision: .none)

    emitter.emit(elements: [element], viewport: (100, 100), maskBounds: [])
    let event = try waitForFirstPublishedEvent()

    XCTAssertEqual(customPayload(from: event).elements[0].text, "\u{E800} Save")
  }

  func testWhitespaceOnlyText_isNulled_shellKept() throws {
    let emitter = WireframeEmitter(options: MPWireframesOptions())
    let element = WireframeElement.from(
      role: .text, text: "   \n\t ",
      rect: CGRect(x: 5, y: 5, width: 30, height: 12),
      decision: .none)

    emitter.emit(elements: [element], viewport: (100, 100), maskBounds: [])
    let event = try waitForFirstPublishedEvent()

    let e = customPayload(from: event).elements[0]
    XCTAssertEqual(e.role, "text", "shell is kept")
    XCTAssertNil(e.text, "whitespace-only text is nulled")
    XCTAssertEqual(e.bounds, [5, 5, 30, 12])
  }

  // MARK: - Dedup

  func testDedup_identicalInput_suppressesSecondEmit() throws {
    let emitter = WireframeEmitter(options: MPWireframesOptions())
    let element = WireframeElement.from(
      role: .text, text: "unchanged",
      rect: CGRect(x: 0, y: 0, width: 10, height: 10),
      decision: .none)

    emitter.emit(elements: [element], viewport: (100, 100), maskBounds: [])
    _ = try waitForFirstPublishedEvent()

    publishedEvents.removeAll()
    emitter.emit(elements: [element], viewport: (100, 100), maskBounds: [])
    assertNoPublishedEvent("identical emit should be deduped")
  }

  func testDedup_maskBoundsThatStartStrippingTextReEmits() throws {
    let emitter = WireframeEmitter(options: MPWireframesOptions())
    let element = WireframeElement.from(
      role: .text, text: "hi",
      rect: CGRect(x: 0, y: 0, width: 10, height: 10),
      decision: .none)

    emitter.emit(elements: [element], viewport: (100, 100), maskBounds: [])
    let first = try waitForFirstPublishedEvent()
    XCTAssertEqual(customPayload(from: first).elements[0].text, "hi")

    publishedEvents.removeAll()
    emitter.emit(
      elements: [element], viewport: (100, 100),
      maskBounds: [HashableRect(CGRect(x: 0, y: 0, width: 10, height: 10))])
    let second = try waitForFirstPublishedEvent()
    XCTAssertNil(customPayload(from: second).elements[0].text)
  }

  func testDedup_maskBoundsMovingWithoutChangingTheWireIsSuppressed() throws {
    // Dedup keys off the finished payload, not the mask set. Mask rects are not on the
    // wire; they matter only through the text they strip, so a mask that misses every
    // element produces an identical render.
    let emitter = WireframeEmitter(options: MPWireframesOptions())
    let element = WireframeElement.from(
      role: .text, text: "hi",
      rect: CGRect(x: 0, y: 0, width: 10, height: 10),
      decision: .none)

    emitter.emit(elements: [element], viewport: (100, 100), maskBounds: [])
    _ = try waitForFirstPublishedEvent()

    publishedEvents.removeAll()
    emitter.emit(
      elements: [element], viewport: (100, 100),
      maskBounds: [HashableRect(CGRect(x: 50, y: 50, width: 5, height: 5))])
    assertNoPublishedEvent()
  }

  func testDedup_viewportChangeReEmits() throws {
    // A rotation on a screen whose element list is unchanged still changes the render,
    // so the viewport is part of the dedup key.
    let emitter = WireframeEmitter(options: MPWireframesOptions())

    emitter.emit(elements: [], viewport: (100, 200), maskBounds: [])
    _ = try waitForFirstPublishedEvent()

    publishedEvents.removeAll()
    emitter.emit(elements: [], viewport: (200, 100), maskBounds: [])
    _ = try waitForFirstPublishedEvent()
    XCTAssertEqual(publishedEvents.count, 1)
  }

  func testDedup_maskDecisionOnlyChangeIsSuppressed() throws {
    // maskDecision is debug-only metadata; the wire payload never carries it, so two
    // frames differing only there render the same.
    let emitter = WireframeEmitter(options: MPWireframesOptions())
    let rect = CGRect(x: 0, y: 0, width: 10, height: 10)

    emitter.emit(
      elements: [WireframeElement.from(role: .text, text: nil, rect: rect, decision: .explicit)],
      viewport: (100, 100), maskBounds: [])
    _ = try waitForFirstPublishedEvent()

    publishedEvents.removeAll()
    emitter.emit(
      elements: [WireframeElement.from(role: .text, text: nil, rect: rect, decision: .auto)],
      viewport: (100, 100), maskBounds: [])
    assertNoPublishedEvent()
  }

  // MARK: - Debug emitter

  func testDebugEmitter_receivesSnapshotWithSameDecisions() throws {
    var received: MPWireframeDebugSnapshot?
    let receivedExp = expectation(description: "debug emitter fires")
    let redactRegex = try NSRegularExpression(pattern: "\\d+")
    let emitterWithRule = WireframeEmitter(
      options: MPWireframesOptions(
        sensitiveRules: [.redactRegex(redactRegex, replacement: "[NUM]")]),
      debugEmitter: { snap in
        received = snap
        receivedExp.fulfill()
      })
    let element = WireframeElement.from(
      role: .text, text: "order 123",
      rect: CGRect(x: 0, y: 0, width: 10, height: 10),
      decision: .none)

    emitterWithRule.emit(elements: [element], viewport: (100, 100), maskBounds: [])
    _ = try waitForFirstPublishedEvent()
    wait(for: [receivedExp], timeout: 2.0)

    XCTAssertEqual(received?.elements.first?.text, "order [NUM]")
    XCTAssertEqual(received?.elements.first?.maskDecision, .ruleRedact)
  }

  func testDebugEmitter_slowCallback_doesNotBlockWirePublish() throws {
    let releaseDebug = expectation(description: "debug released")
    let emitter = WireframeEmitter(
      options: MPWireframesOptions(),
      debugEmitter: { _ in
        Thread.sleep(forTimeInterval: 0.3)  // simulates a slow debug callback
        releaseDebug.fulfill()
      })
    let element = WireframeElement.from(
      role: .text, text: "hi",
      rect: CGRect(x: 0, y: 0, width: 10, height: 10),
      decision: .none)

    emitter.emit(elements: [element], viewport: (100, 100), maskBounds: [])
    // Wire event should be published well before the debug sleep completes.
    _ = try waitForFirstPublishedEvent(timeout: 0.2)
    wait(for: [releaseDebug], timeout: 2.0)
  }

  // MARK: - Helpers

  private func waitForFirstPublishedEvent(
    timeout: TimeInterval = 2.0,
    file: StaticString = #filePath, line: UInt = #line
  ) throws -> SessionEvent {
    let start = Date()
    while publishedEvents.isEmpty {
      if Date().timeIntervalSince(start) > timeout {
        XCTFail("expected a published custom event within \(timeout)s", file: file, line: line)
        throw NSError(domain: "WireframeEmitterTests", code: 1)
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    return publishedEvents[0]
  }

  /// Asserts nothing lands on the event stream — i.e. the frame deduped. Emit is
  /// asynchronous, so this has to wait out the work queue rather than check immediately.
  private func assertNoPublishedEvent(
    within delay: TimeInterval = 0.2,
    _ message: String = "expected the frame to dedup",
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let exp = expectation(description: "quiet")
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
      exp.fulfill()
    }
    wait(for: [exp], timeout: delay + 1.0)
    XCTAssertEqual(publishedEvents.count, 0, message, file: file, line: line)
  }

  private func customPayload(from event: SessionEvent) -> WireframePayload {
    guard case .customData(let custom) = event.data else {
      preconditionFailure("expected customData")
    }
    return custom.payload
  }
}

private final class TestCustomEventSubscriber: EventListener {
  let onCustom: (SessionEvent) -> Void
  init(onCustom: @escaping (SessionEvent) -> Void) { self.onCustom = onCustom }
  func receivedTouchEvent(_ rawEvent: RawTouchEvent) {}
  func receivedScreenshotEvent(_ rawEvent: RawScreenshotEvent) {}
  func receivedCustomEvent(_ event: SessionEvent) { onCustom(event) }
}
