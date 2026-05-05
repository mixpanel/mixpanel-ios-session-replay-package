//
//  SensitiveViewManager.swift
//  MixpanelSessionReplay
//
//  Created by Zihe Jia on 6/20/24.
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import CoreGraphics
import MapKit
import SwiftUI
import UIKit
import WebKit

/// A wrapper around `CGRect` that conforms to `Hashable` by considering only the `origin` and `size`.
struct HashableRect: Hashable {
    let origin: CGPoint
    let size: CGSize

    /// Initialize with a given `CGRect`.
    /// - Parameter rect: The original rectangle.
    init(_ rect: CGRect) {
        self.origin = rect.origin
        self.size = rect.size
    }

    /// Converts the `HashableRect` back to a standard `CGRect`.
    var cgRect: CGRect {
        return CGRect(origin: origin, size: size)
    }

    func contains(_ other: HashableRect) -> Bool {
        cgRect.contains(other.cgRect)
    }

    // MARK: - Hashable Conformance

    /// Custom hash function combining the individual components.
    /// - Parameter hasher: The hasher to use when combining the components.
    func hash(into hasher: inout Hasher) {
        // Combine the individual components of the origin and size.
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }

    /// Custom equality operator comparing the components.
    /// - Parameters:
    ///   - lhs: The left-hand side `HashableRect`.
    ///   - rhs: The right-hand side `HashableRect`.
    /// - Returns: `true` if the rectangles are equal, otherwise `false`.
    static func == (lhs: HashableRect, rhs: HashableRect) -> Bool {
        return lhs.origin.x == rhs.origin.x && lhs.origin.y == rhs.origin.y
            && lhs.size.width == rhs.size.width && lhs.size.height == rhs.size.height
    }
}

/// Describes why a region is masked or unmasked in the debug overlay.
///
/// Cases are ordered by priority (higher raw value = higher priority).
/// When multiple decisions apply to overlapping regions, the highest priority wins.
enum MaskDecision: Int, Comparable {
    case unmask = 0
    case auto = 1
    case mask = 2
    case textInput = 3

    static func < (lhs: MaskDecision, rhs: MaskDecision) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

typealias WeakViewsMap = NSMapTable<UIView, NSNumber>

extension WeakViewsMap {

    /// Inserts a UIView into the map, marking it as sensitive.
    func insert(_ view: UIView) {
        self.setObject(NSNumber(value: true), forKey: view)
    }

    /// Removes a UIView from the map, unmarking it as sensitive.
    func remove(_ view: UIView) {
        self.removeObject(forKey: view)
    }

    /// Checks if the specified UIView key exists in the map.
    func contains(_ key: UIView) -> Bool {
        return self.object(forKey: key) != nil
    }
}

class SensitiveViewManager {
    internal private(set) static var shared: SensitiveViewManager = SensitiveViewManager()

    /// Callback invoked when mask regions are computed, providing typed mask decisions
    var maskRegionsListener: (([HashableRect: MaskDecision], UIWindow?) -> Void)?

    var maskAllText: Bool = true
    var maskAllImages: Bool = true
    var maskAllWebViews: Bool = true
    var maskAllMapViews: Bool = true

    var sensitiveClasses: [AnyClass] = []

    private(set) var knownSensitiveViews: WeakViewsMap!
    var sensitiveTextFieldViews: WeakViewsMap!
    var sensitiveClassViews: WeakViewsMap!

    // MARK: Liquid glass UI unaffected SwiftUI Classes
    private let swiftUITextFieldClass: AnyClass? = NSClassFromString("SwiftUI.TextEditorTextView")
    private let swiftUIImageLayer: AnyClass? = NSClassFromString("SwiftUI.ImageLayer")

    // MARK: - Legacy SwiftUI Classes (iOS 18 and earlier)
    private let swiftUiTextClass: AnyClass? = NSClassFromString("SwiftUI.CGDrawingView")

    // MARK: - iOS 26+ Layer Classes
    /// iOS 26: SwiftUI Text is rendered directly to CGDrawingLayer (CALayer subclass)
    /// Class name: _TtC7SwiftUIP33_863CCF9D49B535DAEB1C7D61BEE53B5914CGDrawingLayer
    private let swiftUIiOS26TextLayerClass: AnyClass? = NSClassFromString(
        "_TtC7SwiftUIP33_863CCF9D49B535DAEB1C7D61BEE53B5914CGDrawingLayer")
    private let buttonLabelClass: AnyClass? = NSClassFromString("UIButtonLabel")

    enum SensitiveViewState {
        case sensitiveTextField
        case sensitive
        case safe
        case unknown
    }

    private init() {
        // NOTE: iOS 26 introduces layer-based rendering for SwiftUI
        // Text views no longer create UIViews (CGDrawingView), instead they render to CGDrawingLayer

        knownSensitiveViews = WeakViewsMap.weakToWeakObjects()
        sensitiveClassViews = WeakViewsMap.weakToWeakObjects()
        sensitiveTextFieldViews = WeakViewsMap.weakToWeakObjects()
    }

    static func reset() {
        SensitiveViewManager.shared = SensitiveViewManager()
    }

    func clearCache() {
        knownSensitiveViews.removeAllObjects()
        sensitiveClassViews.removeAllObjects()
        sensitiveTextFieldViews.removeAllObjects()
    }

    func isSensitiveView(view: UIView) -> SensitiveViewState {
        if view.mpReplaySensitive == true {
            return .sensitive
        }

        // Check text field cache first to maintain .sensitiveTextField return type
        if sensitiveTextFieldViews.contains(view) {
            return .sensitiveTextField
        }

        if knownSensitiveViews.contains(view) || sensitiveClassViews.contains(view) {
            return .sensitive
        }

        // Text fields are always sensitive, so check before !isSensitive
        if isTextField(view: view) {
            sensitiveTextFieldViews.insert(view)
            return .sensitiveTextField
        }

        // If mpReplaySensitive is false, view is manually marked as safe
        if view.mpReplaySensitive == false {
            return .safe
        }

        if maskAllText, isLabel(view: view) {
            knownSensitiveViews.insert(view)
            return .sensitive
        }

        if maskAllImages, isImage(view: view) {
            knownSensitiveViews.insert(view)
            return .sensitive
        }

        if maskAllWebViews, isWebView(view: view) {
            knownSensitiveViews.insert(view)
            return .sensitive
        }

        if maskAllMapViews, isMapView(view: view) {
            knownSensitiveViews.insert(view)
            return .sensitive
        }

        if sensitiveClasses.contains(where: { view.isKind(of: $0) }) {
            sensitiveClassViews.insert(view)
            return .sensitive
        }

        return .unknown
    }

    // Legacy text/label detection
    func isLabel(view: UIView) -> Bool {
        if view.isKind(of: UILabel.self) || view.isKind(of: UITextView.self) {
            return true
        }

        // Legacy: SwiftUI CGDrawingView (iOS 18 and earlier)
        if let swiftUiTextClass, type(of: view) == swiftUiTextClass {
            return true
        }

        return false
    }

    // Legacy SwiftUI Image Detection
    func isImage(view: UIView) -> Bool {
        if view.isKind(of: UIImageView.self) {
            return true
        }

        // Check for SwiftUI image layer
        if let swiftUIImageLayer, type(of: view.layer) == swiftUIImageLayer {
            return true
        }

        return false
    }

    func isTextField(view: UIView) -> Bool {
        if view.isKind(of: UITextField.self) {
            return true
        }

        // Check for SwiftUI text editor text view
        if let swiftUITextFieldClass, view.isKind(of: swiftUITextFieldClass) {
            return true
        }

        return false
    }

    func isWebView(view: UIView) -> Bool {
        return view.isKind(of: WKWebView.self)
    }

    func isMapView(view: UIView) -> Bool {
        return view.isKind(of: MKMapView.self)
    }

    // MARK: - iOS 26 Layer-Based Detection

    /// Checks if a CALayer is a text-rendering layer (iOS 26+)
    /// In iOS 26, SwiftUI Text views render directly to CGDrawingLayer instead of creating UIViews
    func isTextLayer(_ layer: CALayer) -> Bool {
        // Check for iOS 26 CGDrawingLayer by class
        if let swiftUIiOS26TextLayerClass, layer.isKind(of: swiftUIiOS26TextLayerClass) {
            return true
        }

        // Check for SwiftUI UILabelLayer delegate
        if let buttonLabelClass, layer.delegate?.isKind(of: buttonLabelClass) == true {
            return true
        }

        return false
    }

    /// Checks if a CALayer is an image-rendering layer (iOS 26+)
    func isImageLayer(_ layer: CALayer) -> Bool {
        // 1. MOST SPECIFIC: Known SwiftUI class (exact match)
        //    Fast pointer comparison, catches specific iOS <26 SwiftUI case
        if let swiftUIImageLayer, type(of: layer) == swiftUIImageLayer {
            return true
        }

        // 2. SPECIFIC: UIKit images with actual content
        //    Common in UIKit apps, checks both type and content
        if layer.contents != nil, layer.delegate is UIImageView {
            return true
        }

        return false
    }

    func addSensitiveClass(_ someClass: AnyClass) {
        if !sensitiveClasses.contains(where: { $0 === someClass }) {
            sensitiveClasses.append(someClass)
        }
    }

    func removeSensitiveClass(_ someClass: AnyClass) {
        sensitiveClasses.removeAll { $0 === someClass }
        var viewsToRemove: [UIView] = []
        for key in sensitiveClassViews.keyEnumerator() {
            if let keyView = key as? UIView, keyView.isKind(of: someClass) {
                viewsToRemove.append(keyView)
            }
        }
        for view in viewsToRemove {
            sensitiveClassViews.remove(view)
        }
    }

    /// Returns visible sensitive regions within a view hierarchy that should be masked during session replay.
    ///
    /// Performs a unified traversal of both UIView and CALayer hierarchies to detect:
    /// - Text views and labels (UILabel, UITextView, iOS 26+ SwiftUI Text)
    /// - Images (UIImageView, iOS 26+ SwiftUI Image)
    /// - Input fields (UITextField, text editors)
    /// - Web views and map views
    /// - Custom sensitive classes
    ///
    /// Respects views explicitly marked as safe via `mpReplaySensitive = false`.
    ///
    /// - Parameters:
    ///   - rootView: The root view to traverse
    ///   - window: The window providing coordinate space for frame conversion
    /// - Returns: Set of rectangles in window coordinates representing sensitive content to mask
    func getSensitiveFrames(in rootView: UIView, window: UIView) -> [HashableRect: MaskDecision] {
        var maskDecisions = [HashableRect: MaskDecision]()
        var safeFrames = Set<HashableRect>()

        // Single unified traversal
        traverseViewAndLayers(
            rootView,
            window: window,
            maskDecisions: &maskDecisions,
            safeFrames: &safeFrames)

        // Remove regions contained within safe frames, except text inputs which always stay
        if !safeFrames.isEmpty {
            maskDecisions = maskDecisions.filter { (rect, decision) in
                decision == .textInput || !safeFrames.contains { $0.contains(rect) }
            }
        }

        // Only add unmask entries and notify when a debug listener is active
        if let listener = maskRegionsListener {
            // Build a separate dictionary for the listener that includes unmask entries
            // so the debug overlay can visualize safe regions without polluting the
            // production return value
            var debugDecisions = maskDecisions
            for safeFrame in safeFrames {
                addOrUpdate(&debugDecisions, rect: safeFrame, decision: .unmask)
            }
            listener(debugDecisions, window as? UIWindow)
        }

        return maskDecisions
    }

    /// Adds or updates a mask decision, keeping the higher priority decision.
    private func addOrUpdate(
        _ decisions: inout [HashableRect: MaskDecision], rect: HashableRect, decision: MaskDecision
    ) {
        if let existing = decisions[rect] {
            if decision > existing {
                decisions[rect] = decision
            }
        } else {
            decisions[rect] = decision
        }
    }

    /// Unified traversal that handles both UIView hierarchy and CALayer hierarchy in a single pass
    ///
    /// This method efficiently combines:
    /// - UIView hierarchy traversal (for UIKit and iOS <26 SwiftUI)
    /// - CALayer hierarchy traversal (for iOS 26+ SwiftUI rendered directly to layers)
    ///
    /// By traversing both simultaneously, we avoid redundant work and maintain correct precedence:
    /// 1. Check if view itself is sensitive/safe (UIView level)
    /// 2. If not handled at view level, check the view's layer subtree for iOS 26+ SwiftUI content
    /// 3. Recurse into subviews
    ///
    private func traverseViewAndLayers(
        _ view: UIView,
        window: UIView,
        maskDecisions: inout [HashableRect: MaskDecision],
        safeFrames: inout Set<HashableRect>
    ) {
        // Skip invisible views
        guard view.isVisible() else { return }

        // MARK: - Check UIView level first (UIKit + legacy SwiftUI)
        switch isSensitiveView(view: view) {
            case .safe:
                // View is explicitly marked as safe - capture frame and stop traversal
                if let hashableRect = hashableFrame(for: view.layer, in: window) {
                    safeFrames.insert(hashableRect)
                }
                return  // Don't process subviews or sublayers

            case .sensitiveTextField:
                // Text fields are always sensitive and cannot be overridden by safe parents
                if let hashableRect = hashableFrame(for: view.layer, in: window) {
                    addOrUpdate(&maskDecisions, rect: hashableRect, decision: .textInput)
                }
                return  // Don't process subviews or sublayers

            case .sensitive:
                // Determine if this is an auto-detected or manually marked sensitive view
                if let hashableRect = hashableFrame(for: view.layer, in: window) {
                    let decision: MaskDecision = (view.mpReplaySensitive == true) ? .mask : .auto
                    addOrUpdate(&maskDecisions, rect: hashableRect, decision: decision)
                }
                return  // Don't process subviews or sublayers

            case .unknown:
                // View itself is not sensitive/safe, continue checking
                break
        }

        // MARK: - Check Layer subtree for iOS 26+ SwiftUI content
        // Only traverse layers if we're on iOS 26+ and the view itself wasn't sensitive
        if #available(iOS 26.0, *) {
            // Check direct sublayers (not the view's own layer, which we already handled)
            // This catches SwiftUI Text/Image rendered directly to layers
            if let sublayers = view.layer.sublayers {
                for sublayer in sublayers {
                    traverseLayer(
                        sublayer,
                        window: window,
                        maskDecisions: &maskDecisions,
                        safeFrames: &safeFrames)
                }
            }
        }

        // MARK: - Recurse into subviews
        for subview in view.subviews {
            traverseViewAndLayers(
                subview,
                window: window,
                maskDecisions: &maskDecisions,
                safeFrames: &safeFrames)
        }
    }

    /// Traverses a layer hierarchy for iOS 26+ SwiftUI content rendered directly to layers
    ///
    /// This handles the case where SwiftUI Text/Image is rendered to CGDrawingLayer/ImageLayer
    /// without creating a corresponding UIView in the hierarchy.
    @available(iOS 26.0, *)
    private func traverseLayer(
        _ layer: CALayer,
        window: UIView,
        maskDecisions: inout [HashableRect: MaskDecision],
        safeFrames: inout Set<HashableRect>
    ) {

        // Skip this layer if it's not visible
        guard layer.isVisible() else {
            return
        }

        var isSensitive = false

        // Check if this is a text-rendering layer (iOS 26 SwiftUI Text)
        if maskAllText, isTextLayer(layer) {
            isSensitive = true
        } else if maskAllImages, isImageLayer(layer) {  // Check if this is an image-rendering layer (iOS 26 SwiftUI Image)
            isSensitive = true
        }

        if isSensitive {
            if let frame = hashableFrame(for: layer, in: window) {
                addOrUpdate(&maskDecisions, rect: frame, decision: .auto)
            }
            return
        }

        // Recurse into sublayers
        for sublayer in layer.sublayers ?? [] {
            traverseLayer(
                sublayer,
                window: window,
                maskDecisions: &maskDecisions,
                safeFrames: &safeFrames)
        }
    }

    func getFrame(for layer: CALayer, in window: UIView) -> CGRect? {
        // Use presentation layer for accurate frame during animations
        let targetLayer = layer.presentation() ?? layer

        // Convert layer bounds to window coordinates
        let frameInWindow = targetLayer.convert(targetLayer.bounds, to: window.layer)

        // Check if visible in window bounds
        guard window.bounds.intersects(frameInWindow) else { return nil }

        // Filter out very small layers (likely not actual content)
        guard frameInWindow.width > 1 && frameInWindow.height > 1 else { return nil }

        return frameInWindow
    }

    /// Retrieves the frame for the given view within the specified window,
    /// and wraps it as a `HashableRect`, if the frame is available.
    /// - Parameters:
    ///   - view: The view for which to retrieve the frame.
    ///   - window: The reference window used to calculate the frame.
    /// - Returns: A `HashableRect` if the frame is retrieved successfully; otherwise, `nil`.
    func hashableFrame(for layer: CALayer, in window: UIView) -> HashableRect? {
        if let frame = getFrame(for: layer, in: window) {
            return HashableRect(frame)
        } else {
            return nil
        }
    }
}
