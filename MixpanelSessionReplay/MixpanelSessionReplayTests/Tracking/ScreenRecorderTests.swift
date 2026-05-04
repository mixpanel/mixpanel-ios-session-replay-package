//
//  ScreenRecorderTests.swift
//  MixpanelSessionReplay
//
//  Created by Ketan on 04/03/25.
//  Copyright © 2025 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

class ScreenRecorderTests: XCTestCase {
    var recorder: ScreenRecorder!
    var mockWindow: UIWindow!

    override func setUp() {
        super.setUp()
        recorder = ScreenRecorder.shared
        mockWindow = UIWindow(frame: UIScreen.main.bounds)
    }

    override func tearDown() {
        recorder = nil
        mockWindow = nil
        super.tearDown()
    }

    // MARK: - getRendererForSize

    func testGetScreenRendererForSize_CreatesNewRendererWhenSizeChanges() {
        let size1 = CGSize(width: 100, height: 100)
        let size2 = CGSize(width: 200, height: 200)

        let renderer1 = recorder.getRenderer(isPresented: false, size: size1)
        let renderer2 = recorder.getRenderer(isPresented: false, size: size1)

        XCTAssertTrue(renderer1 === renderer2, "Renderer should not be recreated if size is the same")

        let renderer3 = recorder.getRenderer(isPresented: false, size: size2)
        XCTAssertFalse(renderer1 === renderer3, "Renderer should be recreated if size changes")
    }

    func testGetModalRendererForSize_CreatesNewRendererWhenSizeChanges() {
        let size1 = CGSize(width: 100, height: 100)
        let size2 = CGSize(width: 200, height: 200)

        let renderer1 = recorder.getRenderer(isPresented: true, size: size1)
        let renderer2 = recorder.getRenderer(isPresented: true, size: size1)

        XCTAssertTrue(
            renderer1 === renderer2, "Modal renderer should not be recreated if size is the same")

        let renderer3 = recorder.getRenderer(isPresented: true, size: size2)
        XCTAssertFalse(
            renderer1 === renderer3, "Modal renderer should be recreated if size changes")
    }

    func testGetModalRendererForSize_ReturnsModalRenderer() {
        let size = CGSize(width: 100, height: 100)

        // Get the modal renderer
        let modalRenderer = recorder.getRenderer(isPresented: true, size: size)
        XCTAssertNotNil(modalRenderer, "Modal renderer should be created")
    }

    func testGetScreenRendererForSize_UsesOpaqueFormat() {
        let size = CGSize(width: 100, height: 100)

        // Get the screen renderer (should use opaque format)
        let screenRenderer = recorder.getRenderer(isPresented: false, size: size)
        XCTAssertNotNil(screenRenderer, "Screen renderer should be created")
    }

    // MARK: - getViewFromUIViewController

    func testGetViewFromUIViewController_ReturnsSuperviewIfAvailable() {
        let parentView = UIView()
        let childVC = UIViewController()
        let childView = UIView()

        parentView.addSubview(childView)
        childVC.view = childView

        XCTAssertEqual(
            recorder.getViewFromUIViewController(vc: childVC), childView.superview,
            "Should return superview if available")
    }

    func testGetViewFromUIViewController_ReturnsViewIfSuperviewIsNil() {
        let vc = UIViewController()
        let view = UIView()
        vc.view = view

        XCTAssertEqual(
            recorder.getViewFromUIViewController(vc: vc), view, "Should return view if superview is nil")
    }

    // MARK: - getTopViewFor

    func testGetTopViewFor_UsesTabBarControllerIfNotPresented() {
        let tabBarController = UITabBarController()
        let expectedView = UIView()
        tabBarController.view = expectedView

        let result = recorder.getTopViewFor(
            viewController: tabBarController, isPresented: false, window: mockWindow)
        XCTAssertEqual(result, expectedView, "Should return tab bar controller's view")
    }

    func testGetTopViewFor_UsesNavigationControllerIfNotPresented() {
        let navController = UINavigationController()
        let expectedView = UIView()
        navController.view = expectedView

        let result = recorder.getTopViewFor(
            viewController: navController, isPresented: false, window: mockWindow)
        XCTAssertEqual(result, expectedView, "Should return navigation controller's view")
    }

    func testGetTopViewFor_UsesViewControllerIfPresented() {
        let viewController = UIViewController()
        let expectedView = UIView()
        viewController.view = expectedView

        let result = recorder.getTopViewFor(
            viewController: viewController, isPresented: true, window: mockWindow)
        XCTAssertEqual(result, expectedView, "Should return presented view controller's view")
    }

    func testGetTopViewFor_UsesWindowAsFallback() {
        let result = recorder.getTopViewFor(viewController: nil, isPresented: false, window: mockWindow)
        XCTAssertEqual(result, mockWindow, "Should return window as fallback if viewController is nil")
    }

    // MARK: - renderViewHierarchyAsImage

    func testRenderViewHierarchyAsImage_ReturnsNilForInvisibleView() {
        let window = UIWindow()
        let view = UIView()
        view.isHidden = true
        window.addSubview(view)

        let image = recorder.renderViewHierarchyAsImage(window: window)
        XCTAssertNil(image, "Should return nil if view is not visible")
    }

    func testRenderViewHierarchyAsImage_ReturnsImageIfViewIsVisible() {
        let window = UIWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.addSubview(view)
        window.isHidden = false
        let image = recorder.renderViewHierarchyAsImage(window: window)
        XCTAssertNotNil(image, "Should return an image if view is visible")
    }

    // MARK: - getTopViewFor (with isPresented flag)

    func testGetTopViewFor_ReturnsIsPresentedFalseForRegularView() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        let rootVC = UIViewController()
        let view = UIView(frame: window.bounds)
        rootVC.view = view
        window.rootViewController = rootVC
        window.makeKeyAndVisible()

        let result = recorder.getTopViewFor(window: window)

        XCTAssertNotNil(result.view, "View should be returned")
        XCTAssertNotNil(result.viewBounds, "View bounds should be returned")
        XCTAssertFalse(result.isPresented, "isPresented should be false for regular view")
    }

    func testGetTopViewFor_ReturnsNilForOutOfBoundsView() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        let rootVC = UIViewController()
        // Create view that's way outside window bounds
        let view = UIView(frame: CGRect(x: 10000, y: 10000, width: 100, height: 100))
        rootVC.view = view
        window.rootViewController = rootVC

        let result = recorder.getTopViewFor(window: window)

        XCTAssertNil(result.view, "View should be nil for out of bounds view")
        XCTAssertNil(result.viewBounds, "View bounds should be nil for out of bounds view")
    }

    // MARK: - Background Fill Color

    func testBackgroundFillColor_IsCorrectGray() {
        // Verify the background fill color is correct (203/255 for each RGB component)
        let expectedColor = UIColor(red: 203 / 255.0, green: 203 / 255.0, blue: 203 / 255.0, alpha: 1.0)

        XCTAssertEqual(
            recorder.backgroundFillColor, expectedColor,
            "Background fill color should be light gray (203/255)")
    }

    // MARK: - captureScreenshot
    func testCaptureScreenshot_ReturnsNilIfWindowIsNil() {
        let result = recorder.captureScreenshot()
        XCTAssertNil(result, "Should return nil if no window is available")
    }
}
