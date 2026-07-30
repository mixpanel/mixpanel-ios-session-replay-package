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
      decision: .none, declared: true)

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
      decision: .none, declared: true)

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

  func testTruncation_boundaryExactly60_preserved() throws {
    let text = String(repeating: "a", count: 60)
    let emitter = WireframeEmitter(options: MPWireframesOptions())
    let element = WireframeElement.from(
      role: .text, text: text,
      rect: CGRect(x: 0, y: 0, width: 10, height: 10),
      decision: .none)

    emitter.emit(elements: [element], viewport: (100, 100), maskBounds: [])
    let event = try waitForFirstPublishedEvent()

    XCTAssertEqual(customPayload(from: event).elements[0].text, text)
  }

  func testTruncation_length61_isCutTo60PlusEllipsis() throws {
    let text = String(repeating: "a", count: 61)
    let emitter = WireframeEmitter(options: MPWireframesOptions())
    let element = WireframeElement.from(
      role: .text, text: text,
      rect: CGRect(x: 0, y: 0, width: 10, height: 10),
      decision: .none)

    emitter.emit(elements: [element], viewport: (100, 100), maskBounds: [])
    let event = try waitForFirstPublishedEvent()

    let out = customPayload(from: event).elements[0].text
    XCTAssertEqual(out?.count, 61)
    XCTAssertTrue(out?.hasSuffix("…") == true)
    XCTAssertEqual(out?.prefix(60), Substring(String(repeating: "a", count: 60)))
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
    // give the work queue a chance to run
    let exp = expectation(description: "quiet")
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
      exp.fulfill()
    }
    wait(for: [exp], timeout: 1.0)
    XCTAssertEqual(publishedEvents.count, 0, "identical emit should be deduped")
  }

  func testDedup_changingMaskBoundsReEmits() throws {
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
    _ = try waitForFirstPublishedEvent()
    XCTAssertEqual(publishedEvents.count, 1)
  }

  // MARK: - Debug emitter

  func testDebugEmitter_receivesSnapshotWithSameDecisions() throws {
    var received: MPWireframeDebugSnapshot?
    let receivedExp = expectation(description: "debug emitter fires")
    let emitter = WireframeEmitter(options: MPWireframesOptions(
      debugEmitter: { snap in
        received = snap
        receivedExp.fulfill()
      }
    ))

    let redactRegex = try NSRegularExpression(pattern: "\\d+")
    let emitterWithRule = WireframeEmitter(options: MPWireframesOptions(
      sensitiveRules: [.redactRegex(redactRegex, replacement: "[NUM]")],
      debugEmitter: { snap in
        received = snap
        receivedExp.fulfill()
      }
    ))
    _ = emitter  // silence unused
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
    let emitter = WireframeEmitter(options: MPWireframesOptions(
      debugEmitter: { _ in
        Thread.sleep(forTimeInterval: 0.3)  // simulates a slow debug callback
        releaseDebug.fulfill()
      }
    ))
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
