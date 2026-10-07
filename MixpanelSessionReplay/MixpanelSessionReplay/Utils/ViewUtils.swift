//
//  ViewUtils.swift
//  MixpanelSessionReplay
//
//  Created by Jared McFarland on 10/30/24.
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation
import UIKit

struct ViewUtils {
    static func getVisibleViewInWindow(_ window: UIWindow) -> UIView? {
        if let rootViewController = window.rootViewController {
            let visibleViewController = getVisibleViewController(rootViewController)
            return visibleViewController.viewController?.view
        }
        return nil
    }

    /// You will get the view controller that is displayed on the screen and is on the top. For modally presented view controllers, it will return the
    /// `isPresented` as true.
    /// - Parameters:
    ///   - controller: you can pass the rootViewController here
    ///   - isPresented: Do not send this value, the value is defaulted to false. Do not send it as true.
    /// - Returns: returns the top view controller and a flag which tells if the that view controller is presented
    static func getVisibleViewController(_ controller: UIViewController?, isPresented: Bool = false)
        -> (viewController: UIViewController?, isPresented: Bool)
    {
        if let presented = controller?.presentedViewController {
            return getVisibleViewController(presented, isPresented: true)
        } else if let navigationController = controller as? UINavigationController {
            // Private UINavigationController subclasses (e.g. UIPrintPanelViewController) may not
            // implement .visibleViewController, causing an unrecognized selector crash.
            // Guard with responds(to:) before accessing the property.
            guard navigationController.responds(to: #selector(getter: UINavigationController.visibleViewController))
            else {
                return (controller, isPresented)
            }
            return getVisibleViewController(navigationController.visibleViewController, isPresented: isPresented)
        } else if let tabController = controller as? UITabBarController,
            let selected = tabController.selectedViewController
        {
            return getVisibleViewController(selected, isPresented: isPresented)
        } else if let splitController = controller as? UISplitViewController {
            // Private UISplitViewController subclasses may not implement .viewControllers.
            // Chain the responds(to:) check with the nil guard to avoid a crash on access.
            guard splitController.responds(to: #selector(getter: UISplitViewController.viewControllers)),
                let lastViewController = splitController.viewControllers.last
            else {
                return (controller, isPresented)
            }
            return getVisibleViewController(lastViewController, isPresented: isPresented)
        } else if let pageController = controller as? UIPageViewController {
            // Private UIPageViewController subclasses may not implement .viewControllers.
            // Guard with responds(to:) before accessing the property.
            guard pageController.responds(to: #selector(getter: UIPageViewController.viewControllers)) else {
                return (controller, isPresented)
            }
            let currentPage = pageController.viewControllers?.first
            return getVisibleViewController(currentPage, isPresented: isPresented)
        }
        return (controller, isPresented)
    }

    static func getCurrentWindow() -> UIWindow? {
        if let windowScene = UIApplication.shared.connectedScenes.first(where: {
            $0.activationState == .foregroundActive
        }) as? UIWindowScene {
            if #available(iOS 15.0, *) {
                if let keyWindow = windowScene.keyWindow {
                    return keyWindow
                }
            }
            for window in windowScene.windows where window.isKeyWindow {
                return window
            }
        }
        return nil
    }

    static func isViewInCurrentWindow(_ view: UIView) -> Bool {
        return view.window === ViewUtils.getCurrentWindow()
    }

    static func isDescendantOfVisibleView(_ view: UIView) -> Bool {
        if let currentWindow = ViewUtils.getCurrentWindow() {
            if let visibleView = ViewUtils.getVisibleViewInWindow(currentWindow) {
                return view.isDescendant(of: visibleView)
            }
            return view.isDescendant(of: currentWindow)
        }
        return false
    }

    /// Retrieves all app-owned key windows.
    /// - Returns: Array of UIWindow instances that belong to the app (excludes system windows)
    static func getAllWindows() -> [UIWindow] {
        var windows: [UIWindow] = []

        if #available(iOS 15.0, *) {
            // Use modern API for iOS 15+
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    windows.append(contentsOf: windowScene.windows)
                }
            }
        } else {
            // Fallback for older iOS versions
            windows = UIApplication.shared.windows
        }

        // Filter to only app-owned key windows
        return windows.filter { $0.isKeyWindow && isAppOwnedWindow($0) }
    }

    /// Determines if a window is owned by the app (not a system window)
    /// - Parameter window: The window to check
    /// - Returns: true if the window is app-owned, false for system windows
    static func isAppOwnedWindow(_ window: UIWindow) -> Bool {
        // Filter out system windows (keyboard, alerts, text effects, etc.)
        // System windows typically have windowLevel > .normal
        guard window.windowLevel == .normal else {
            return false
        }

        if #available(iOS 15.0, *) {
            // Ensure window belongs to an app-owned UIWindowScene
            // System scenes (like keyboard) are not activation scenes
            guard let windowScene = window.windowScene,
                windowScene.activationState != .unattached
            else {
                return false
            }
        }

        return true
    }
}
