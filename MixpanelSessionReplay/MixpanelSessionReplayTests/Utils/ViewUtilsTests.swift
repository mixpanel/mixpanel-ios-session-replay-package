//
//  ViewUtils.swift
//  MixpanelSessionReplay
//
//  Created by Ketan on 03/03/25.
//  Copyright © 2025 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

class ViewUtilsTests: XCTestCase {

    var window: UIWindow!

    override func setUp() {
        super.setUp()
        window = UIWindow()
        window.makeKeyAndVisible()
    }

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    func testGetVisibleViewInWindow() {
        let rootViewController = UIViewController()
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()

        let visibleView = ViewUtils.getVisibleViewInWindow(window)
        XCTAssertNotNil(visibleView, "Visible view should not be nil")
        XCTAssertEqual(
            visibleView, rootViewController.view, "Visible view should be the rootViewController's view")
    }

    func testGetVisibleViewInWindow_NoRootViewController() {
        window.rootViewController = nil
        let visibleView = ViewUtils.getVisibleViewInWindow(window)
        XCTAssertNil(visibleView, "Visible view should be nil when there is no rootViewController")
    }

    func testGetVisibleViewController() {
        let rootViewController = UIViewController()

        let result = ViewUtils.getVisibleViewController(rootViewController)
        XCTAssertEqual(
            result.viewController, rootViewController, "Should return the root view controller")
        XCTAssertFalse(result.isPresented, "isPresented should be false for non-modal views")
    }

    func testGetVisibleViewController_NavigationController() {
        let rootViewController = UIViewController()
        let navController = UINavigationController(rootViewController: rootViewController)

        let result = ViewUtils.getVisibleViewController(navController)

        XCTAssertEqual(
            result.viewController, rootViewController,
            "Should return the top view controller in navigation stack")
    }

    func testGetVisibleViewController_TabBarController() {
        let rootViewController = UIViewController()
        let tabController = UITabBarController()
        tabController.viewControllers = [rootViewController]

        let result = ViewUtils.getVisibleViewController(tabController)
        XCTAssertEqual(
            result.viewController, rootViewController,
            "Should return the selected view controller in tab bar")
        XCTAssertFalse(result.isPresented, "isPresented should be false")
    }

    func testGetVisibleViewController_PresentedViewController() {
        let modalViewController = UIViewController()
        let rootViewController = UIViewController()
        let navController = UINavigationController(rootViewController: rootViewController)
        window.rootViewController = navController
        window.makeKeyAndVisible()
        rootViewController.present(modalViewController, animated: false)

        let result = ViewUtils.getVisibleViewController(navController)
        XCTAssertEqual(
            result.viewController, modalViewController, "Should return the presented view controller")
        XCTAssertTrue(result.isPresented, "isPresented should be true for modal views")
    }
}
