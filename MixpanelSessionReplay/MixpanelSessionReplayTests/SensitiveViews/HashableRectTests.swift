//
//  HashableRectTests.swift
//  MixpanelSessionReplay
//
//  Created by Ketan on 04/03/25.
//  Copyright © 2025 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

class HashableRectTests: XCTestCase {

    func testInitialization() {
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        let hashableRect = HashableRect(rect)

        XCTAssertEqual(hashableRect.origin, rect.origin, "Origin should be correctly set")
        XCTAssertEqual(hashableRect.size, rect.size, "Size should be correctly set")
    }

    func testCGRectConversion() {
        let rect = CGRect(x: 5, y: 15, width: 25, height: 35)
        let hashableRect = HashableRect(rect)

        XCTAssertEqual(hashableRect.cgRect, rect, "Converted CGRect should match the original")
    }

    func testHashableEquality() {
        let rect1 = HashableRect(CGRect(x: 0, y: 0, width: 50, height: 50))
        let rect2 = HashableRect(CGRect(x: 0, y: 0, width: 50, height: 50))
        let rect3 = HashableRect(CGRect(x: 10, y: 10, width: 50, height: 50))

        XCTAssertEqual(rect1, rect2, "Equal rectangles should be considered equal")
        XCTAssertNotEqual(rect1, rect3, "Different rectangles should not be equal")
    }

    func testHashableBehavior() {
        let rect1 = HashableRect(CGRect(x: 10, y: 20, width: 30, height: 40))
        let rect2 = HashableRect(CGRect(x: 10, y: 20, width: 30, height: 40))
        let rect3 = HashableRect(CGRect(x: 15, y: 25, width: 35, height: 45))

        let set: Set<HashableRect> = [rect1, rect3]

        XCTAssertTrue(set.contains(rect2), "Set should contain equivalent rectangle")
        XCTAssertFalse(
            set.contains(HashableRect(CGRect(x: 0, y: 0, width: 100, height: 100))),
            "Set should not contain different rectangle")
    }
}
