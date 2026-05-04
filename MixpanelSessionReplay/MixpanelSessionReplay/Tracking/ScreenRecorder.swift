//
//  ScreenRecorder.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//
import SwiftUI
import UIKit

class ScreenRecorder {
    static let shared = ScreenRecorder()

    var mainScreenRendererFormat: UIGraphicsImageRendererFormat
    var presentedScreenRendererFormat: UIGraphicsImageRendererFormat

    /// Renderer for view controller screen capture
    private var mainScreenRenderer: UIGraphicsImageRenderer?
    /// Render for modal view controller screen capture
    private var presentedScreenRenderer: UIGraphicsImageRenderer?
    private var mainScreenRendererCurrentSize: CGSize = .zero
    private var presentedScreenRendererCurrentSize: CGSize = .zero

    private var window: UIWindow?
    let backgroundFillColor = UIColor(red: 203 / 255.0, green: 203 / 255.0, blue: 203 / 255.0, alpha: 1.0)

    private init() {
        mainScreenRendererFormat = UIGraphicsImageRendererFormat()
        mainScreenRendererFormat.scale = 1.0
        mainScreenRendererFormat.opaque = true
        mainScreenRendererFormat.preferredRange = .standard

        presentedScreenRendererFormat = UIGraphicsImageRendererFormat()
        presentedScreenRendererFormat.scale = 1.0
        presentedScreenRendererFormat.opaque = false
        presentedScreenRendererFormat.preferredRange = .standard
    }

    func getRenderer(isPresented: Bool, size: CGSize) -> UIGraphicsImageRenderer? {
        if isPresented {
            if presentedScreenRenderer == nil || size != presentedScreenRendererCurrentSize {
                presentedScreenRenderer = UIGraphicsImageRenderer(size: size, format: presentedScreenRendererFormat)
                presentedScreenRendererCurrentSize = size
            }
            return presentedScreenRenderer
        } else {
            if mainScreenRenderer == nil || size != mainScreenRendererCurrentSize {
                mainScreenRenderer = UIGraphicsImageRenderer(size: size, format: mainScreenRendererFormat)
                mainScreenRendererCurrentSize = size
            }
            return mainScreenRenderer
        }
    }

    func getViewFromUIViewController(vc: UIViewController) -> UIView? {
        // Try the vc.view.superview first, use vc.view as fallback in case superview is found null
        return vc.view?.superview ?? vc.view
    }

    func getTopViewFor(viewController: UIViewController?, isPresented: Bool, window: UIWindow)
        -> UIView?
    {
        if !isPresented, let tabBarController = viewController?.tabBarController {
            // Use tab bar controller instead of view controller to capture the tab bar
            return getViewFromUIViewController(vc: tabBarController)
        } else if !isPresented, let navController = viewController?.navigationController {
            // Use navigation controller instead of viewcontroller to capture nav bar
            return getViewFromUIViewController(vc: navController)
        } else if let vc = viewController {
            // If the viewController isPresented (modal presentation of vc or alert)
            // or the navigation controller is not found
            return getViewFromUIViewController(vc: vc)
        } else {
            // In case, vc is found nil, use the window as fallback
            Logger.debug(message: "vc is found nil, using window as fallback")
            return window
        }
    }

    /// Get the top view for the given window. This will return the view of the top most view controller.
    /// - Parameter window: UIWindow object
    /// - Returns: return the top view and the view bounds with reference to the screen
    func getTopViewFor(window: UIWindow) -> (view: UIView?, viewBounds: CGRect?, isPresented: Bool) {
        // Get the visible top view controller
        let res = ViewUtils.getVisibleViewController(window.rootViewController)
        // Get the topview for the view controller
        guard
            var view: UIView = getTopViewFor(
                viewController: res.viewController, isPresented: res.isPresented, window: window)
        else {
            return (nil, nil, false)
        }
        // Get the frame with respect to window, to see if its within the screen bounds
        var viewBounds = view.convert(view.bounds, to: window)

        // If not within the screen bounds or isPresented && modal vc is animating
        if !UIScreen.main.bounds.contains(viewBounds)
            || (res.isPresented
                && (res.viewController?.isBeingPresented == true
                    || res.viewController?.isBeingDismissed == true))
        {
            // This case will mostly happen for the modally presented vcs
            // during the dismiss and present animation the view goes out of the screen
            if res.isPresented {
                // Use the view of presentingViewController i.e. parent vc as fallback here.
                guard
                    let parentView = getTopViewFor(
                        viewController: res.viewController?.presentingViewController, isPresented: false,
                        window: window)
                else {
                    return (nil, nil, res.isPresented)
                }
                view = parentView
                // Recreate the frame
                viewBounds = view.convert(view.bounds, to: window)
                Logger.warn(message: "Ignored blank view, picked parent vc instead")
            } else {
                // Skip taking screenshot if the view is not within screen bounds.
                Logger.debug(message: "view out of bounds")
                return (nil, nil, res.isPresented)
            }
        }
        return (view, viewBounds, res.isPresented)
    }

    func renderViewHierarchyAsImage(window: UIWindow) -> UIImage? {
        let (view, viewBounds, isPresented) = getTopViewFor(window: window)

        guard let renderer = getRenderer(isPresented: isPresented, size: window.bounds.size) else {
            Logger.error(message: "Failed to get renderer")
            return nil
        }

        guard let view, let viewBounds else {
            Logger.warn(message: "Skipped screenshot: view is out of screen")
            return nil
        }

        guard view.isVisible() else {
            Logger.warn(message: "Skipped screenshot: view found is not visible")
            return nil
        }

        return renderer.image { context in
            context.cgContext.interpolationQuality = .none

            if isPresented {
                // Fill entire canvas with BLACK (hides everything outside modal)
                context.cgContext.setFillColor(UIColor.black.cgColor)
                context.cgContext.fill(CGRect(origin: .zero, size: window.bounds.size))

                // Fill the modal view area with Grey (iOS blur background color) to create opaque background.
                context.cgContext.setFillColor(backgroundFillColor.cgColor)
                context.cgContext.fill(viewBounds)
            }

            let sensitiveFrames = SensitiveViewManager.shared.getSensitiveFrames(in: view, window: window)

            view.drawHierarchy(in: viewBounds, afterScreenUpdates: false)

            // Apply masking to sensitive frames with LIGHT GRAY
            context.cgContext.setFillColor(UIColor.lightGray.cgColor)
            for (hashableRect, _) in sensitiveFrames {
                context.cgContext.fill(hashableRect.cgRect)
            }
        }
    }

    func captureScreenshot() -> Data? {
        guard let currentWindow = ViewUtils.getCurrentWindow() else { return nil }

        if let image = renderViewHierarchyAsImage(window: currentWindow) {
            if let compressedData = image.jpegData(compressionQuality: ImageSettings.jpegCompressionRate) {
                return compressedData
            }
            Logger.warn(message: "Failed to compress image to jpeg")
            return nil
        }
        Logger.warn(message: "Failed to render window as image")
        return nil
    }
}
