//
//  ScreenRecorder.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//
import SwiftUI
import UIKit

/// A rendered frame plus the wall-clock instant its pixels came off the renderer.
///
/// The instant is read at the render, not at the trigger that asked for it, so the frame
/// reports **when it was on screen** rather than when something decided to capture it.
/// Mirrors Android's `RenderedFrame.capturedAtMs`; Flutter's equivalent is
/// `captureTimestamp` in `screenshot_capturer.dart`.
struct RenderedFrame {
    let image: UIImage
    let capturedAtMs: Int64
}

/// A compressed frame, still carrying its ``RenderedFrame/capturedAtMs``, so the value
/// survives JPEG compression on its way to `RawScreenshotEvent.timestamp`. Mirrors
/// Android's `CapturedScreenshot`.
struct CapturedScreenshot {
    let data: Data
    let capturedAtMs: Int64
}

class ScreenRecorder {
    static let shared = ScreenRecorder()

    /// Present when wireframes are enabled. Emits an rrweb Custom event with
    /// the current wireframe elements alongside each screenshot capture.
    var wireframeEmitter: WireframeEmitter?

    /// How each frame is rendered; mirrored from `MPSessionReplayConfig.captureMethod`
    /// by the instance that owns the recording.
    var captureMethod: MPCaptureMethod = .viewHierarchy

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

    /// Renders `window` and stamps the result with the instant the pixels came off the
    /// renderer, which is also the instant handed to the wireframe emitter — so the
    /// `mp_wireframe` event and the screenshot event describing one frame agree, and both
    /// report when the screen was actually shown.
    ///
    /// The clock is deliberately read **here** rather than accepted from the caller. The
    /// caller's trigger time is earlier by the render duration (a full-window
    /// `drawHierarchy` plus the whole wireframe walk run inside the renderer block), and on
    /// a touch-triggered capture it is the touch's own timestamp — which would make the
    /// frame tie exactly with the touch event that produced it. The service's sampler is
    /// touch-gated, so a tie leaves "which screen did this tap act on" to be resolved by
    /// sort stability rather than by the data. Stamping at the render puts the frame
    /// strictly after its touch, matching Android and Flutter.
    func renderViewHierarchyAsImage(window: UIWindow) -> RenderedFrame? {
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

        let emitter = wireframeEmitter
        var wireframes: [WireframeElement] = []
        var sensitiveFrames: [HashableRect: MaskDecision] = [:]

        let image = renderer.image { context in
            context.cgContext.interpolationQuality = .none

            if isPresented {
                // Fill entire canvas with BLACK (hides everything outside modal)
                context.cgContext.setFillColor(UIColor.black.cgColor)
                context.cgContext.fill(CGRect(origin: .zero, size: window.bounds.size))

                // Fill the modal view area with Grey (iOS blur background color) to create opaque background.
                context.cgContext.setFillColor(backgroundFillColor.cgColor)
                context.cgContext.fill(viewBounds)
            }

            let (frames, elements) = SensitiveViewManager.shared.walkHierarchy(in: view, window: window)
            sensitiveFrames = frames
            wireframes = elements

            draw(view, at: viewBounds, in: context.cgContext)

            // Apply masking to sensitive frames with LIGHT GRAY
            context.cgContext.setFillColor(UIColor.lightGray.cgColor)
            for (hashableRect, _) in sensitiveFrames {
                context.cgContext.fill(hashableRect.cgRect)
            }
        }

        // Read immediately after the render block, the way Android reads it straight after
        // `createBitmapFromView`. Everything above — the walk and the draw — is the work
        // that separates the trigger from the pixels.
        let capturedAtMs = TimestampUtils.timestamp()

        // Emitted whenever collection is on, including for a frame that produced no
        // elements. An empty `elements` array is meaningful — it says the frame was
        // described and had nothing readable on it, which is different from no
        // wireframe at all. Suppressing it would leave a screenshot the summarizer
        // can't distinguish from one we simply failed to describe. Matches Android.
        if let emitter {
            emitter.emit(
                elements: wireframes,
                viewport: (Int(window.bounds.width), Int(window.bounds.height)),
                maskBounds: Set(sensitiveFrames.keys),
                capturedAtMs: capturedAtMs)
        }

        return RenderedFrame(image: image, capturedAtMs: capturedAtMs)
    }

    /// Draws `view` into `cgContext` at `viewBounds` — its frame in window coordinates —
    /// with the configured capture method.
    func draw(_ view: UIView, at viewBounds: CGRect, in cgContext: CGContext) {
        switch captureMethod {
            case .viewHierarchy:
                view.drawHierarchy(in: viewBounds, afterScreenUpdates: false)
            case .layerTree:
                // The presentation tree is drawn rather than the model tree: it holds the
                // values of any animation in flight, as the screen shows them, and it is
                // the tree the masks are measured on (`SensitiveViewManager.getFrame`), so
                // a view mid-animation and its mask land in the same place.
                let tree = view.layer.presentation() ?? view.layer
                // Snapshotted pickers' presentation copies are hidden for the render, so the
                // frame shows what is behind them instead of what `render(in:)` makes of
                // them. Shadows are left out too: `render(in:)` blurs each one on the CPU,
                // and SwiftUI's `.shadow` on a stack puts one on every element in it — nine
                // on one card, which took a render from 16 ms to 63 ms on an iPhone 14 —
                // while a frame without a soft shadow reads the same. Only copies are
                // touched: the model tree, and so the screen, never changes.
                let snapshots = pickerSnapshots(in: view, tree: tree, at: viewBounds)
                var hidden: [CALayer] = []
                var shadowed: [(layer: CALayer, opacity: Float)] = []
                if tree !== view.layer {
                    for snapshot in snapshots {
                        snapshot.copy.isHidden = true
                        hidden.append(snapshot.copy)
                    }
                    shadowed = shadowedLayers(in: tree).map { ($0, $0.shadowOpacity) }
                    for copy in shadowed {
                        copy.layer.shadowOpacity = 0
                    }
                }
                // `render(in:)` draws at the layer's own origin, so the context is moved
                // to where the view sits in the window first — the same placement
                // `drawHierarchy(in:)` gives the snapshot.
                cgContext.saveGState()
                cgContext.translateBy(x: viewBounds.origin.x, y: viewBounds.origin.y)
                tree.render(in: cgContext)
                cgContext.restoreGState()
                for copy in hidden {
                    copy.isHidden = false
                }
                for copy in shadowed {
                    copy.layer.shadowOpacity = copy.opacity
                }
                for snapshot in snapshots {
                    drawSnapshot(of: snapshot.view, at: snapshot.rect, in: cgContext)
                }
        }
    }

    /// Views whose content `CALayer.render(in:)` cannot draw — a picker's wheel is built
    /// from 3D transforms, which it flattens — so `.layerTree` draws them with
    /// `drawHierarchy(in:afterScreenUpdates:)` over the rest of the frame. Snapshotting only
    /// those views keeps the capture cheap: about 10 ms for a wheel date picker on an
    /// iPhone 14, against about 65 ms for the whole window.
    static let snapshottedViewTypes: [UIView.Type] = [UIPickerView.self]

    /// The pickers to snapshot under `view`, with each one's presentation copy in `tree` and
    /// the rect to draw it in, in window coordinates.
    ///
    /// The rect comes from the presentation copy, where the picker is on screen at this
    /// instant — the same place its mask is measured — so a picker caught mid-animation is
    /// drawn under its mask. A picker that something drawn after it paints over (a popover,
    /// a toast) is left to `render(in:)`: a snapshot is drawn over the whole frame and would
    /// cover it. Without a presentation tree there is nothing to place a snapshot by, and
    /// no picker is snapshotted.
    func pickerSnapshots(in view: UIView, tree: CALayer, at viewBounds: CGRect)
        -> [(view: UIView, copy: CALayer, rect: CGRect)]
    {
        guard tree !== view.layer else { return [] }
        return snapshottedViews(in: view).compactMap { picker in
            let modelRect = picker.layer.convert(picker.layer.bounds, to: view.layer)
            guard !isPainted(over: modelRect, after: picker.layer, in: view.layer),
                let copy = presentationCopy(of: picker.layer, in: tree, under: view.layer)
            else { return nil }
            let rect = copy.convert(copy.bounds, to: tree).offsetBy(dx: viewBounds.minX, dy: viewBounds.minY)
            return (picker, copy, rect)
        }
    }

    /// Whether a layer drawn after `layer` in `root`'s tree — a later sibling of it or of one
    /// of its ancestors, or anything inside one — draws something over `rect`, in `root`'s
    /// coordinates.
    func isPainted(over rect: CGRect, after layer: CALayer, in root: CALayer) -> Bool {
        var current = layer
        while current !== root, let parent = current.superlayer {
            let siblings = parent.sublayers ?? []
            if let index = siblings.firstIndex(where: { $0 === current }) {
                for later in siblings[(index + 1)...] where paints(later, over: rect, in: root) {
                    return true
                }
            }
            current = parent
        }
        return false
    }

    /// Whether `layer`, or anything inside it, draws something over `rect`. Transparent
    /// containers — a SwiftUI host spanning the screen — don't count; only what draws.
    private func paints(_ layer: CALayer, over rect: CGRect, in root: CALayer) -> Bool {
        guard !layer.isHidden, layer.opacity > 0.01 else { return false }
        let frame = layer.convert(layer.bounds, to: root)
        if frame.intersects(rect), drawsSomething(layer) {
            return true
        }
        if layer.masksToBounds, !frame.intersects(rect) {
            return false
        }
        return (layer.sublayers ?? []).contains { paints($0, over: rect, in: root) }
    }

    private func drawsSomething(_ layer: CALayer) -> Bool {
        if layer.contents != nil || layer.borderWidth > 0 {
            return true
        }
        if let color = layer.backgroundColor, color.alpha > 0.01 {
            return true
        }
        if let shape = layer as? CAShapeLayer {
            return shape.fillColor != nil || shape.strokeColor != nil
        }
        return layer is CATextLayer
    }

    /// Draws `view`'s own snapshot over the frame in `rect`. The snapshot is taken into a
    /// transparent image first and composited from there: `drawHierarchy` straight into the
    /// frame's opaque context would write the view's clear areas as black instead of
    /// leaving the page behind it.
    func drawSnapshot(of view: UIView, at rect: CGRect, in cgContext: CGContext) {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = cgContext.userSpaceToDeviceSpaceTransform.a
        let snapshot = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
        guard let image = snapshot.cgImage else { return }
        cgContext.saveGState()
        // `CGContext.draw` places an image bottom-up; the frame's context is top-down.
        cgContext.translateBy(x: rect.minX, y: rect.maxY)
        cgContext.scaleBy(x: 1, y: -1)
        cgContext.draw(image, in: CGRect(origin: .zero, size: rect.size))
        cgContext.restoreGState()
    }

    /// The visible views under `root` of a ``snapshottedViewTypes`` type, outermost only.
    func snapshottedViews(in root: UIView) -> [UIView] {
        guard !root.isHidden, root.alpha > 0.01 else { return [] }
        if Self.snapshottedViewTypes.contains(where: { root.isKind(of: $0) }) {
            return [root]
        }
        return root.subviews.flatMap { snapshottedViews(in: $0) }
    }

    /// The layers under `root`, itself included, that cast a shadow.
    func shadowedLayers(in root: CALayer) -> [CALayer] {
        var layers: [CALayer] = root.shadowOpacity > 0 ? [root] : []
        for sublayer in root.sublayers ?? [] {
            layers += shadowedLayers(in: sublayer)
        }
        return layers
    }

    /// The copy of `layer` in the presentation tree `tree`, the copy of `root`: found by
    /// following `layer`'s path of sublayer indexes down from `root`, which a presentation
    /// copy shares with its model.
    func presentationCopy(of layer: CALayer, in tree: CALayer, under root: CALayer) -> CALayer? {
        var path: [Int] = []
        var current = layer
        while current !== root {
            guard let parent = current.superlayer,
                let index = parent.sublayers?.firstIndex(where: { $0 === current })
            else { return nil }
            path.append(index)
            current = parent
        }
        var copy = tree
        for index in path.reversed() {
            guard let sublayers = copy.sublayers, index < sublayers.count else { return nil }
            copy = sublayers[index]
        }
        return copy.model() === layer ? copy : nil
    }

    /// Renders and compresses the current window, carrying the frame's capture instant
    /// through compression so the screenshot event can be stamped with it.
    func captureScreenshot() -> CapturedScreenshot? {
        guard let currentWindow = ViewUtils.getCurrentWindow() else { return nil }

        if let frame = renderViewHierarchyAsImage(window: currentWindow) {
            if let compressedData = frame.image.jpegData(
                compressionQuality: ImageSettings.jpegCompressionRate)
            {
                return CapturedScreenshot(data: compressedData, capturedAtMs: frame.capturedAtMs)
            }
            Logger.warn(message: "Failed to compress image to jpeg")
            return nil
        }
        Logger.warn(message: "Failed to render window as image")
        return nil
    }
}
