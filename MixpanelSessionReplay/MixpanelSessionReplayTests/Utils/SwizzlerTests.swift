//
//  SwizzlerTests.swift
//  MixpanelSessionReplayTests
//
//  Created by Jared McFarland on 6/2/25.
//  Copyright © 2025 Mixpanel. All rights reserved.
//

import ObjectiveC.runtime
import UIKit
import XCTest

// Assuming your Swizzler code is in a module named "YourAppModule"
// If it's in your main app target, use: @testable import YourAppName
@testable import MixpanelSessionReplay

// MARK: - Mocks

// Mock for MPSessionReplay
class MockMPSessionReplay: MPSessionReplaying {
    var recordCalled = false
    var markScreenDirtyCalled = false
    var lastRecordTimestamp: Int64?
    var isRecording: Bool = false

    var recordExpectation: XCTestExpectation?
    var markScreenDirtyExpectation: XCTestExpectation?

    // Private serial queue for synchronizing access to expectation fulfillment logic
    private let expectationAccessQueue = DispatchQueue(label: "com.mixpanel.mockMPSessionReplay.expectationAccessQueue")

    func record(_ triggerTimestamp: Int64?) {
        // record() is typically called from main queue via dispatchRecord's asyncAfter.
        // If it could be called from other threads, similar sync would be needed.
        // For now, assuming main queue handles its serialization.
        print(
            "[MockMPSessionReplay DEBUG] record(timestamp: \(String(describing: triggerTimestamp))) called on \(self). Current recordExpectation: \(String(describing: self.recordExpectation))"
        )
        self.recordCalled = true
        self.lastRecordTimestamp = triggerTimestamp

        if let expectationToFulfill = self.recordExpectation {
            print("[MockMPSessionReplay DEBUG] Fulfilling recordExpectation: \(expectationToFulfill)")
            expectationToFulfill.fulfill()
            self.recordExpectation = nil
            print("[MockMPSessionReplay DEBUG] recordExpectation has been nilled out after fulfilling.")
        } else {
            print(
                "[MockMPSessionReplay DEBUG] No active recordExpectation to fulfill (it might have been nil or already fulfilled and nilled out)."
            )
        }
    }

    func markScreenDirty() {
        // Synchronize access to markScreenDirtyCalled and markScreenDirtyExpectation
        expectationAccessQueue.sync {
            // This flag can be set here; multiple sets to true are idempotent.
            self.markScreenDirtyCalled = true
            print(
                "[MockMPSessionReplay DEBUG] markScreenDirty() called on \(self) (SYNC BLOCK). Current markDirtyExpectation: \(String(describing: self.markScreenDirtyExpectation))"
            )

            if let expectationToFulfill = self.markScreenDirtyExpectation {
                print("[MockMPSessionReplay DEBUG] Fulfilling markDirtyExpectation: \(expectationToFulfill)")
                expectationToFulfill.fulfill()
                self.markScreenDirtyExpectation = nil
                print(
                    "[MockMPSessionReplay DEBUG] markDirtyExpectation has been nilled out after fulfilling (SYNC BLOCK)."
                )
            } else {
                print("[MockMPSessionReplay DEBUG] No active markDirtyExpectation to fulfill (SYNC BLOCK).")
            }
        }
    }

    func reset() {
        // Also synchronize reset as it modifies the expectations
        expectationAccessQueue.sync {
            print(
                "[MockMPSessionReplay DEBUG] reset() called on \(self) (SYNC BLOCK). Clearing flags and expectations.")
            recordCalled = false
            markScreenDirtyCalled = false
            lastRecordTimestamp = nil
            recordExpectation = nil
            markScreenDirtyExpectation = nil
        }
    }

    func prepareForTest(
        recordExpectation: XCTestExpectation? = nil, markScreenDirtyExpectation: XCTestExpectation? = nil
    ) {
        // This method is called from the main test thread, typically before any concurrent access.
        // The reset() call is now internally synchronized.
        print(
            "[MockMPSessionReplay DEBUG] prepareForTest called on \(self). Incoming recordExpectation: \(String(describing: recordExpectation)), Incoming markDirtyExpectation: \(String(describing: markScreenDirtyExpectation))"
        )
        self.reset()

        // These assignments are fine here as they happen before concurrent tasks typically start for a new test.
        // The critical part is that read-fulfill-write on the expectation itself is synchronized.
        self.recordExpectation = recordExpectation
        self.markScreenDirtyExpectation = markScreenDirtyExpectation
        print(
            "[MockMPSessionReplay DEBUG] prepareForTest finished. Current recordExpectation: \(String(describing: self.recordExpectation)), Current markDirtyExpectation: \(String(describing: self.markScreenDirtyExpectation))"
        )
    }
}

class MockTouchEventProcessor: TouchEventProcessing {
    func processTouchEvent(_ event: UIEvent) {}
}

// MARK: - Helper Test Classes

class TestViewController: UIViewController {
    var originalViewDidAppearCalled = false
    var originalViewDidDisappearCalled = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)  // This will call the swizzled chain if UIViewController is swizzled
        originalViewDidAppearCalled = true
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)  // Swizzled chain
        originalViewDidDisappearCalled = true
    }

    func resetTestFlags() {
        originalViewDidAppearCalled = false
        originalViewDidDisappearCalled = false
    }
}

class TestView: UIView {
    var originalLayoutSubviewsCalled = false

    override func layoutSubviews() {
        super.layoutSubviews()  // Swizzled chain
        originalLayoutSubviewsCalled = true
    }

    func resetTestFlags() {
        originalLayoutSubviewsCalled = false
    }
}

// MARK: - SwizzlerTests

class SwizzlerTests: XCTestCase {

    var mockMPSessionReplay: MockMPSessionReplay!
    var mockTouchProcessor: MockTouchEventProcessor!

    var originalAppMPSessionReplay: MPSessionReplaying?
    var originalAppTouchProcessor: TouchEventProcessing!

    override func setUp() {
        super.setUp()

        Swizzler.shared.unswizzle()
        // Save original dependencies
        originalAppMPSessionReplay = Swizzler.shared.sessionReplay
        originalAppTouchProcessor = Swizzler.shared.touchProcessor

        // Create new mock instances for each test
        mockMPSessionReplay = MockMPSessionReplay()
        mockTouchProcessor = MockTouchEventProcessor()

        // Inject mocks
        Swizzler.shared.testOverride_sessionReplay = mockMPSessionReplay
        Swizzler.shared.testOverride_touchProcessor = mockTouchProcessor  // Inject instance
    }

    override func tearDown() {
        // Restore original dependencies
        Swizzler.shared.testOverride_sessionReplay = originalAppMPSessionReplay
        Swizzler.shared.testOverride_touchProcessor = originalAppTouchProcessor

        // Nil out properties
        mockMPSessionReplay = nil
        mockTouchProcessor = nil

        originalAppMPSessionReplay = nil
        originalAppTouchProcessor = nil

        Swizzler.shared.unswizzle()
        super.tearDown()
    }

    // MARK: - SwizzledMethod Tests

    func testSwizzledMethodEqualityAndHashability() {
        guard
            let method1_vda = class_getInstanceMethod(
                UIViewController.self,
                #selector(UIViewController.viewDidAppear(_:))),
            let method2_vda = class_getInstanceMethod(
                UIViewController.self,
                #selector(UIViewController.viewDidAppear(_:))),
            let method_vdd = class_getInstanceMethod(
                UIViewController.self,
                #selector(UIViewController.viewDidDisappear(_:)))
        else {
            XCTFail(
                "Failed to get method instances for testing SwizzledMethod.")
            return
        }

        let swizzledVDA1 = SwizzledMethod(
            method: method1_vda, className: UIViewController.self)
        let swizzledVDA2 = SwizzledMethod(
            method: method2_vda, className: UIViewController.self)
        let swizzledVDD = SwizzledMethod(
            method: method_vdd, className: UIViewController.self)
        let swizzledVDA_Subclass = SwizzledMethod(
            method: method1_vda, className: TestViewController.self)

        XCTAssertEqual(
            swizzledVDA1, swizzledVDA2,
            "SwizzledMethods for the same method and class should be equal.")
        XCTAssertEqual(
            swizzledVDA1.hashValue, swizzledVDA2.hashValue,
            "Hash values for equal SwizzledMethods should be the same.")

        XCTAssertNotEqual(
            swizzledVDA1, swizzledVDD,
            "SwizzledMethods for different methods should not be equal.")
        XCTAssertNotEqual(
            swizzledVDA1, swizzledVDA_Subclass,
            "SwizzledMethods for the same method but different classes should not be equal."
        )
    }

    // MARK: - UIViewController Lifecycle Swizzling

    func
        testSwizzleViewDidAppear_WhenSessionStarted_CallsOriginalAndCustomLogic()
    {
        let viewController = TestViewController()
        mockMPSessionReplay.isRecording = true

        let recordExpectation = expectation(
            description: "MPSessionReplay.record() should be called")
        mockMPSessionReplay.prepareForTest(recordExpectation: recordExpectation)

        Swizzler.swizzleViewControllerLifecycle()
        viewController.viewDidAppear(true)

        waitForExpectations(timeout: 5.0) { error in
            XCTAssertNil(
                error,
                "Expectation failed: \(error?.localizedDescription ?? "unknown error")"
            )
            XCTAssertTrue(viewController.originalViewDidAppearCalled)
            XCTAssertTrue(self.mockMPSessionReplay.recordCalled)
            XCTAssertNil(
                self.mockMPSessionReplay.lastRecordTimestamp,
                "Timestamp should be nil as passed by dispatchRecord")
        }
    }

    func testSwizzleViewDidAppear_WhenSessionNotStarted_CallsOriginalOnly() {
        let viewController = TestViewController()
        mockMPSessionReplay.isRecording = false

        mockMPSessionReplay.prepareForTest()

        Swizzler.swizzleViewControllerLifecycle()
        viewController.viewDidAppear(true)

        let _ = XCTWaiter.wait(
            for: [XCTestExpectation(description: "Short wait")], timeout: 0.2)

        XCTAssertTrue(viewController.originalViewDidAppearCalled)
        XCTAssertFalse(self.mockMPSessionReplay.recordCalled)  // Check instance mock
    }

    func testUnswizzleViewControllerLifecycle_RestoresOriginalBehavior() {
        let viewController = TestViewController()
        mockMPSessionReplay.isRecording = true

        Swizzler.swizzleViewControllerLifecycle()
        viewController.resetTestFlags()
        mockMPSessionReplay.prepareForTest()

        Swizzler.shared.unswizzle()

        viewController.viewDidAppear(true)
        viewController.viewDidDisappear(true)

        let _ = XCTWaiter.wait(
            for: [XCTestExpectation(description: "Short wait")], timeout: 0.2)

        XCTAssertTrue(viewController.originalViewDidAppearCalled)
        XCTAssertTrue(viewController.originalViewDidDisappearCalled)
        XCTAssertFalse(self.mockMPSessionReplay.recordCalled)
    }

    // MARK: - UIView layoutSubviews Swizzling

    func testSwizzleLayoutSubviews_WhenSessionStarted_CallsOriginalAndCustomLogic() {
        let testView = TestView()
        mockMPSessionReplay.isRecording = true

        let markDirtyExpectation = expectation(
            description: "MPSessionReplay.markScreenDirty() should be called")
        mockMPSessionReplay.prepareForTest(
            markScreenDirtyExpectation: markDirtyExpectation)

        Swizzler.swizzleLayoutSubviews()
        testView.layoutSubviews()

        waitForExpectations(timeout: 5.0) { error in
            XCTAssertNil(error)
            XCTAssertTrue(testView.originalLayoutSubviewsCalled)
            XCTAssertTrue(self.mockMPSessionReplay.markScreenDirtyCalled)
        }
    }

    func testSwizzleLayoutSubviews_WhenSessionNotStarted_CallsOriginalOnly() {
        let testView = TestView()
        mockMPSessionReplay.isRecording = false

        mockMPSessionReplay.prepareForTest()

        Swizzler.swizzleLayoutSubviews()
        testView.layoutSubviews()

        let _ = XCTWaiter.wait(
            for: [XCTestExpectation(description: "Short wait")], timeout: 0.2)
        XCTAssertTrue(testView.originalLayoutSubviewsCalled)
        XCTAssertFalse(self.mockMPSessionReplay.markScreenDirtyCalled)  // Check instance mock
    }

    func testSwizzleLayoutSubviews_CallsMarkScreenDirty() {
        let testView = TestView()
        mockMPSessionReplay.isRecording = true

        let markDirtyExpectation = expectation(
            description: "MPSessionReplay.markScreenDirty() should be called")
        mockMPSessionReplay.prepareForTest(
            markScreenDirtyExpectation: markDirtyExpectation)

        Swizzler.swizzleLayoutSubviews()
        testView.layoutSubviews()

        waitForExpectations(timeout: 5.0) { error in
            XCTAssertNil(error)
            XCTAssertTrue(testView.originalLayoutSubviewsCalled)
            XCTAssertTrue(self.mockMPSessionReplay.markScreenDirtyCalled)
        }
    }

    func testUnswizzleLayoutSubviews_RestoresOriginalBehavior() {
        let testView = TestView()
        mockMPSessionReplay.isRecording = true

        // Verify swizzling is working
        let markDirtyExpectation = expectation(description: "MPSessionReplay.markScreenDirty() called")
        mockMPSessionReplay.prepareForTest(markScreenDirtyExpectation: markDirtyExpectation)

        Swizzler.swizzleLayoutSubviews()
        testView.layoutSubviews()

        wait(for: [markDirtyExpectation], timeout: 5.0)

        // Small delay to ensure sync block completes after expectation fulfillment
        Thread.sleep(forTimeInterval: 0.01)

        XCTAssertTrue(self.mockMPSessionReplay.markScreenDirtyCalled)

        // Reset state and test unswizzling
        testView.resetTestFlags()
        mockMPSessionReplay.prepareForTest()

        Swizzler.shared.unswizzle()
        testView.layoutSubviews()

        // Replace XCTWaiter hack with simple sleep (verifying no async call happens)
        Thread.sleep(forTimeInterval: 0.1)

        XCTAssertTrue(testView.originalLayoutSubviewsCalled)
        XCTAssertFalse(self.mockMPSessionReplay.markScreenDirtyCalled)
    }

    // MARK: - UIApplication sendEvent Swizzling

    func testSwizzleSendEvent_ChangesIMPAndCachesOriginal() {
        // 1. Arrange: Capture original state BEFORE swizzling
        guard
            let sendEventMethod = class_getInstanceMethod(
                UIApplication.self, #selector(UIApplication.sendEvent(_:)))
        else {
            XCTFail("Could not get UIApplication.sendEvent method.")
            return
        }
        let originalIMPBeforeSwizzle = method_getImplementation(sendEventMethod)

        // 2. Act: Swizzle the method
        Swizzler.swizzleSendEvent()

        let impAfterSwizzle = method_getImplementation(sendEventMethod)

        // 3. Assert: Method implementation was changed
        XCTAssertNotEqual(
            impAfterSwizzle, originalIMPBeforeSwizzle,
            "Method IMP should have changed after swizzling. If this fails, swizzling itself failed."
        )

        // 4. Assert: Original implementation was cached correctly by Swizzler
        let swizzledMethodKey = SwizzledMethod(
            method: sendEventMethod, className: UIApplication.self)
        guard
            let cachedOriginalIMP = Swizzler.shared.originalImplementation(
                of: swizzledMethodKey)
        else {
            XCTFail(
                "Original IMP for sendEvent should have been cached by Swizzler."
            )
            return
        }
        XCTAssertEqual(
            cachedOriginalIMP, originalIMPBeforeSwizzle,
            "The cached original IMP should match the implementation from before swizzling."
        )
    }

    func testUnswizzleSendEvent_RestoresOriginalBehavior() {
        guard
            let sendEventMethod = class_getInstanceMethod(
                UIApplication.self, #selector(UIApplication.sendEvent(_:)))
        else {
            XCTFail("Could not get UIApplication.sendEvent method.")
            return
        }
        let originalIMPBeforeSwizzle = method_getImplementation(sendEventMethod)

        // Swizzle
        Swizzler.swizzleSendEvent()
        let impAfterSwizzle = method_getImplementation(sendEventMethod)
        XCTAssertNotEqual(
            impAfterSwizzle, originalIMPBeforeSwizzle,
            "IMP should change after swizzling.")

        // Unswizzle
        Swizzler.shared.unswizzle()
        let impAfterUnswizzle = method_getImplementation(sendEventMethod)

        // Assert: IMP is restored
        XCTAssertEqual(
            impAfterUnswizzle, originalIMPBeforeSwizzle,
            "IMP should be restored to original after unswizzling.")
    }

    // MARK: - Cache and Unswizzle All

    func testSwizzle_storesOriginalImplementationInCache() {
        guard
            let method = class_getInstanceMethod(
                UIViewController.self,
                #selector(UIViewController.viewDidAppear(_:)))
        else {
            XCTFail("Failed to get viewDidAppear method.")
            return
        }
        let originalIMP = method_getImplementation(method)
        let swizzledMethodKey = SwizzledMethod(
            method: method, className: UIViewController.self)

        // Ensure cache is initially empty or doesn't contain this specific original IMP for this key
        // (Note: Swizzler.shared is a singleton, so cache might persist if not cleared in setUp/tearDown properly,
        //  but unswizzle in setUp should handle the method restoration part)
        XCTAssertNil(
            Swizzler.shared.originalImplementation(of: swizzledMethodKey),
            "Cache should be clear for this method at start or IMP shouldn't match if it was a different swizzle."
        )

        // Act
        Swizzler.swizzleViewControllerLifecycle()  // This swizzles viewDidAppear and viewDidDisappear

        // Assert
        let cachedIMP = Swizzler.shared.originalImplementation(
            of: swizzledMethodKey)
        XCTAssertNotNil(
            cachedIMP, "Original IMP for viewDidAppear should be cached.")
        XCTAssertEqual(
            cachedIMP, originalIMP,
            "The cached IMP should be the original method implementation.")
    }

    func testUnswizzle_restoresAllSwizzledMethods() {
        // Setup: Swizzle multiple methods
        Swizzler.swizzleViewControllerLifecycle()  // Swizzles viewDidAppear, viewDidDisappear
        Swizzler.swizzleLayoutSubviews()  // Swizzles layoutSubviews

        guard
            let vdaMethod = class_getInstanceMethod(
                UIViewController.self,
                #selector(UIViewController.viewDidAppear(_:))),
            let lsMethod = class_getInstanceMethod(
                UIView.self, #selector(UIView.layoutSubviews))
        else {
            XCTFail("Failed to get methods for unswizzle all test.")
            return
        }

        let originalVDAImp = Swizzler.shared.originalImplementation(
            of: SwizzledMethod(
                method: vdaMethod, className: UIViewController.self))
        let originalLSImp = Swizzler.shared.originalImplementation(
            of: SwizzledMethod(method: lsMethod, className: UIView.self))

        XCTAssertNotNil(originalVDAImp, "Original VDA IMP should be cached.")
        XCTAssertNotNil(originalLSImp, "Original LS IMP should be cached.")

        let currentVDAImp = method_getImplementation(vdaMethod)
        let currentLSImp = method_getImplementation(lsMethod)

        XCTAssertNotEqual(
            currentVDAImp, originalVDAImp, "VDA IMP should be swizzled.")
        XCTAssertNotEqual(
            currentLSImp, originalLSImp, "LS IMP should be swizzled.")

        // Act: Unswizzle all
        Swizzler.shared.unswizzle()

        // Assert: Implementations are restored
        let restoredVDAImp = method_getImplementation(vdaMethod)
        let restoredLSImp = method_getImplementation(lsMethod)

        XCTAssertEqual(
            restoredVDAImp, originalVDAImp,
            "viewDidAppear implementation should be restored to original.")
        XCTAssertEqual(
            restoredLSImp, originalLSImp,
            "layoutSubviews implementation should be restored to original.")
    }
}

// MARK: - Extension to make SwizzledMethod init accessible for tests if needed
// If SwizzledMethod's init is fileprivate and you are in a different module,
// you might need to make it internal or provide a testable initializer.
// However, the tests above primarily verify caching behavior via Swizzler's own methods
// or by reconstructing the SwizzledMethod key if method and class are known.

// Note: The original SwizzledMethod init is fileprivate.
// For the `testSwizzledMethodEqualityAndHashability` and cache key construction,
// this test suite assumes it can create SwizzledMethod instances.
// If `SwizzledMethod` is in the same module as tests (e.g. using `@testable import`),
// `fileprivate` allows access from within the same file or same module tests.
// If it's truly inaccessible, those specific test lines creating SwizzledMethod directly
// would need adjustment, perhaps by testing cache access more indirectly or by modifying
// SwizzledMethod's initializer visibility for testing (e.g. to `internal`).
// The current structure of `Swizzler.shared.originalImplementation(of: SwizzledMethod)` requires
// constructing a `SwizzledMethod` key.
