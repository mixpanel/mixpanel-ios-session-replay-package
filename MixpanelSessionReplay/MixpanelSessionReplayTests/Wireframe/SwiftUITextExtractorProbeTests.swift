//
//  SwiftUITextExtractorProbeTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import UIKit
import XCTest

@testable import MixpanelSessionReplay

// Fixtures use `@objc dynamic var` on NSObject/UIView subclasses so Swift
// synthesizes real Objective-C ivars matching the extractor's allowlist.
// Note: use `NSString` (not `String`) so the ivar encoding is `@"NSString"`;
// Swift-native `String` is a value type and would not satisfy the `@` gate.

final class FixtureWithObjectTextIvar: NSObject {
  @objc dynamic var text: NSString = "hello"
}

final class FixtureWithValueTypeTextIvar: NSObject {
  @objc dynamic var text: Int = 42
}

final class FixtureWithoutAllowlistedIvar: NSObject {
  @objc dynamic var caption: NSString = "hello"
}

final class FixtureViewWithValueTypeText: UIView {
  @objc dynamic var text: Int = 42
}

final class SwiftUITextExtractorProbeTests: XCTestCase {

  override func setUp() {
    super.setUp()
    SwiftUITextExtractor.shared.probe(classes: [FixtureWithObjectTextIvar.self])
  }

  // MARK: - probe(classes:)

  func testProbe_enables_whenAllowlistedObjectIvarPresent() {
    SwiftUITextExtractor.shared.probe(classes: [FixtureWithObjectTextIvar.self])
    XCTAssertTrue(SwiftUITextExtractor.shared.ivarStrategyEnabled)
  }

  func testProbe_disables_whenAllowlistedIvarIsValueType() {
    SwiftUITextExtractor.shared.probe(classes: [FixtureWithValueTypeTextIvar.self])
    XCTAssertFalse(SwiftUITextExtractor.shared.ivarStrategyEnabled)
  }

  func testProbe_disables_whenNoAllowlistedIvarPresent() {
    SwiftUITextExtractor.shared.probe(classes: [FixtureWithoutAllowlistedIvar.self])
    XCTAssertFalse(SwiftUITextExtractor.shared.ivarStrategyEnabled)
  }

  func testProbe_disables_whenEmptyClassList() {
    SwiftUITextExtractor.shared.probe(classes: [])
    XCTAssertFalse(SwiftUITextExtractor.shared.ivarStrategyEnabled)
  }

  func testProbe_enables_whenAnyClassPasses() {
    SwiftUITextExtractor.shared.probe(classes: [
      FixtureWithoutAllowlistedIvar.self,
      FixtureWithValueTypeTextIvar.self,
      FixtureWithObjectTextIvar.self,
    ])
    XCTAssertTrue(SwiftUITextExtractor.shared.ivarStrategyEnabled)
  }

  // MARK: - Runtime crash safety

  /// Without the inline `ivar_getTypeEncoding` gate in `ivarText(from:)`,
  /// this test crashes: `object_getIvar` would read `Int` bytes at the ivar
  /// offset and hand them back as an `id` pointer, which is then bridged to
  /// Swift as `Any?` and dereferenced. The gate skips the read entirely.
  func testExtractText_doesNotCrash_whenAllowlistedIvarIsValueType() {
    // Force the strategy on so the outer guard doesn't short-circuit — this
    // exercises the *inner* type-encoding check specifically.
    SwiftUITextExtractor.shared.probe(classes: [FixtureWithObjectTextIvar.self])
    XCTAssertTrue(SwiftUITextExtractor.shared.ivarStrategyEnabled)

    let view = FixtureViewWithValueTypeText()
    _ = SwiftUITextExtractor.shared.extractText(from: view)
  }
}
