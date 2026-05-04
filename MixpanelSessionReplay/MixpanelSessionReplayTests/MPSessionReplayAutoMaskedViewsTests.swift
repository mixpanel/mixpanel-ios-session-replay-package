//
//  MPSessionReplayAutoMaskedViewsTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

class MPSessionReplayAutoMaskedViewsTests: BaseTests {

    override func setUp() {
        super.setUp()
        // Reset singleton to ensure clean state for each test
        SensitiveViewManager.reset()
    }

    override func tearDown() {
        super.tearDown()
        // Reset singleton after each test
        SensitiveViewManager.reset()
    }

    // MARK: - Initialization

    func testAutoMaskedViews_InitialConfiguration() {
        var config = MPSessionReplayConfig()
        config.autoMaskedViews = [.text, .image]

        let instance = MPSessionReplayInstance(
            token: "test-token",
            distinctId: "test-distinct-id",
            config: config
        )

        XCTAssertTrue(SensitiveViewManager.shared.maskAllText)
        XCTAssertTrue(SensitiveViewManager.shared.maskAllImages)
        XCTAssertFalse(SensitiveViewManager.shared.maskAllWebViews)
        XCTAssertFalse(SensitiveViewManager.shared.maskAllMapViews)
        XCTAssertEqual(instance.config.autoMaskedViews, [.text, .image])
    }

    // MARK: - Runtime Updates

    func testAutoMaskedViews_RuntimeUpdateChangesSettings() {
        var config = MPSessionReplayConfig()
        config.autoMaskedViews = [.text]
        config.recordingSessionsPercent = 0.0

        let instance = MPSessionReplayInstance(
            token: "test-token",
            distinctId: "test-distinct-id",
            config: config
        )

        XCTAssertTrue(SensitiveViewManager.shared.maskAllText)
        XCTAssertFalse(SensitiveViewManager.shared.maskAllImages)

        XCTAssertEqual(instance.autoMaskedViews, [.text])

        instance.autoMaskedViews = [.image, .web]

        XCTAssertFalse(SensitiveViewManager.shared.maskAllText)
        XCTAssertTrue(SensitiveViewManager.shared.maskAllImages)
        XCTAssertTrue(SensitiveViewManager.shared.maskAllWebViews)
        XCTAssertEqual(instance.autoMaskedViews, [.image, .web])
        XCTAssertEqual(instance.config.autoMaskedViews, [.image, .web])
    }

    func testAutoMaskedViews_ClearAll() {
        var config = MPSessionReplayConfig()
        config.autoMaskedViews = [.text, .image, .web, .map]
        config.recordingSessionsPercent = 0.0

        let instance = MPSessionReplayInstance(
            token: "test-token",
            distinctId: "test-distinct-id",
            config: config
        )
        XCTAssertTrue(SensitiveViewManager.shared.maskAllText)
        XCTAssertTrue(SensitiveViewManager.shared.maskAllImages)
        XCTAssertTrue(SensitiveViewManager.shared.maskAllWebViews)
        XCTAssertTrue(SensitiveViewManager.shared.maskAllMapViews)

        instance.autoMaskedViews = []
        let expectation = self.expectation(description: "Final state")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertFalse(SensitiveViewManager.shared.maskAllText)
        XCTAssertFalse(SensitiveViewManager.shared.maskAllImages)
        XCTAssertFalse(SensitiveViewManager.shared.maskAllWebViews)
        XCTAssertFalse(SensitiveViewManager.shared.maskAllMapViews)
    }

    // MARK: - Cache Invalidation (Critical Test)

    func testAutoMaskedViews_CacheClearedOnUpdate() {
        var config = MPSessionReplayConfig()
        config.autoMaskedViews = [.text]
        config.recordingSessionsPercent = 0.0

        let instance = MPSessionReplayInstance(
            token: "test-token",
            distinctId: "test-distinct-id",
            config: config
        )

        // Populate caches
        let label = UILabel()
        let imageView = UIImageView()
        let textField = UITextField()
        let customView = UIView()

        SensitiveViewManager.shared.knownSensitiveViews.insert(label)
        SensitiveViewManager.shared.knownSensitiveViews.insert(imageView)
        SensitiveViewManager.shared.sensitiveTextFieldViews.insert(textField)
        SensitiveViewManager.shared.sensitiveClassViews.insert(customView)

        XCTAssertTrue(SensitiveViewManager.shared.knownSensitiveViews.contains(label))
        XCTAssertTrue(SensitiveViewManager.shared.sensitiveTextFieldViews.contains(textField))
        XCTAssertTrue(SensitiveViewManager.shared.sensitiveClassViews.contains(customView))

        // Update masking - should clear all caches
        instance.autoMaskedViews = [.web]

        // Wait for main thread execution
        let expectation = self.expectation(description: "Cache cleared")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertFalse(SensitiveViewManager.shared.knownSensitiveViews.contains(label))
        XCTAssertFalse(SensitiveViewManager.shared.knownSensitiveViews.contains(imageView))
        XCTAssertFalse(SensitiveViewManager.shared.sensitiveTextFieldViews.contains(textField))
        XCTAssertFalse(SensitiveViewManager.shared.sensitiveClassViews.contains(customView))
    }

    // MARK: - Config Sync

    func testAutoMaskedViews_ConfigStaysInSync() {
        var config = MPSessionReplayConfig()
        config.autoMaskedViews = [.text]
        config.recordingSessionsPercent = 0.0

        let instance = MPSessionReplayInstance(
            token: "test-token",
            distinctId: "test-distinct-id",
            config: config
        )

        XCTAssertEqual(instance.config.autoMaskedViews, [.text])

        instance.autoMaskedViews = [.image, .web]

        XCTAssertEqual(instance.config.autoMaskedViews, [.image, .web])
    }

    // MARK: - Thread Safety

    func testAutoMaskedViews_UpdateFromBackgroundThread() {
        var config = MPSessionReplayConfig()
        config.autoMaskedViews = [.text]
        config.recordingSessionsPercent = 0.0

        let instance = MPSessionReplayInstance(
            token: "test-token",
            distinctId: "test-distinct-id",
            config: config
        )

        let expectation = self.expectation(description: "Background thread update")

        DispatchQueue.global().async {
            instance.autoMaskedViews = [.image]

            DispatchQueue.main.async {
                XCTAssertTrue(SensitiveViewManager.shared.maskAllImages)
                XCTAssertFalse(SensitiveViewManager.shared.maskAllText)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Multiple Updates

    func testAutoMaskedViews_MultipleRapidUpdates() {
        var config = MPSessionReplayConfig()
        config.autoMaskedViews = []
        config.recordingSessionsPercent = 0.0

        let instance = MPSessionReplayInstance(
            token: "test-token",
            distinctId: "test-distinct-id",
            config: config
        )

        instance.autoMaskedViews = [.text]
        instance.autoMaskedViews = [.image]
        instance.autoMaskedViews = [.text, .image, .web, .map]

        let expectation = self.expectation(description: "Final state")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(SensitiveViewManager.shared.maskAllText)
        XCTAssertTrue(SensitiveViewManager.shared.maskAllImages)
        XCTAssertTrue(SensitiveViewManager.shared.maskAllWebViews)
        XCTAssertTrue(SensitiveViewManager.shared.maskAllMapViews)
        XCTAssertEqual(instance.config.autoMaskedViews, [.text, .image, .web, .map])
    }
}
