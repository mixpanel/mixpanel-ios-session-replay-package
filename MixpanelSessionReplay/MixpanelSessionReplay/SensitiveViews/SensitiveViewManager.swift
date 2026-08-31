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

    /// When true, `walkHierarchy(in:window:)` returns a populated
    /// wireframe element list. When false, wireframe collection is a no-op
    /// (the existing masking pass runs unchanged).
    var wireframeCollectionEnabled: Bool = false

    var sensitiveClasses: [AnyClass] = []

    private(set) var knownSensitiveViews: WeakViewsMap!
    var sensitiveTextInputViews: WeakViewsMap!
    var sensitiveClassViews: WeakViewsMap!

    /// The private SwiftUI/UIKit render classes the type predicates below match
    /// against, shared with ``wireframeClassifier`` so masking and description cannot
    /// disagree about what a given class is.
    let renderClasses = SwiftUIRenderClasses()

    /// Decides a view's wireframe role and text. Separate from masking on purpose —
    /// see ``WireframeClassifier``.
    var wireframeClassifier: WireframeClassifier

    enum SensitiveViewState {
        case sensitiveTextInput
        case sensitive
        case safe
        case unknown
    }

    private init() {
        knownSensitiveViews = WeakViewsMap.weakToWeakObjects()
        sensitiveClassViews = WeakViewsMap.weakToWeakObjects()
        sensitiveTextInputViews = WeakViewsMap.weakToWeakObjects()
        wireframeClassifier = WireframeClassifier(renderClasses: renderClasses)
    }

    static func reset() {
        SensitiveViewManager.shared = SensitiveViewManager()
    }

    func clearCache() {
        knownSensitiveViews.removeAllObjects()
        sensitiveClassViews.removeAllObjects()
        sensitiveTextInputViews.removeAllObjects()
    }

    func isSensitiveView(view: UIView) -> SensitiveViewState {
        if view.mpReplaySensitive == true {
            return .sensitive
        }

        // Check the text-input cache first so the .sensitiveTextInput state survives
        if sensitiveTextInputViews.contains(view) {
            return .sensitiveTextInput
        }

        if knownSensitiveViews.contains(view) || sensitiveClassViews.contains(view) {
            return .sensitive
        }

        // Text inputs are always sensitive, so check before the safe/auto branches
        if isTextInput(view: view) {
            sensitiveTextInputViews.insert(view)
            return .sensitiveTextInput
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
        if view.isKind(of: UILabel.self) {
            return true
        }

        // Legacy: SwiftUI CGDrawingView (iOS 18 and earlier)
        if let drawingView = renderClasses.drawingView, type(of: view) == drawingView {
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
        if let imageLayer = renderClasses.imageLayer, type(of: view.layer) == imageLayer {
            return true
        }

        // SF Symbols: rendered as a shape layer, not an image layer.
        if let colorShapeLayer = renderClasses.colorShapeLayer, type(of: view.layer) == colorShapeLayer {
            return true
        }

        return false
    }

    /// Whether `view` is a text input, and therefore always masked.
    ///
    /// Classified by *type*, never by `isEditable`. `UITextView` is iOS's multi-line
    /// text input, and a read-only one very often holds text the user themselves typed
    /// — a saved note, a message body, a bio rendered back for review. Reading its
    /// `isEditable` flag would make masking depend on a presentation detail the
    /// developer can flip at runtime, so the safe default is to treat every
    /// `UITextView` as an input.
    ///
    /// This matches the other platforms, which also key on type alone: Android tests
    /// `EditText::class.java.isAssignableFrom(view)` with no editability check (a
    /// disabled or `TYPE_NULL` field is still `TEXT_ENTRY`), and Flutter tests
    /// `renderObject is RenderEditable`, which catches a read-only `SelectableText`.
    ///
    /// Being a text input rather than auto-masked text, the result survives both
    /// escape hatches — `maskAllText = false` and an `mpReplaySensitive = false`
    /// ancestor — because neither was meant to expose what a user typed. Android
    /// enforces the same thing by seeding `EditText` into its sensitive classes
    /// permanently.
    func isTextInput(view: UIView) -> Bool {
        if view.isKind(of: UITextField.self) || view.isKind(of: UITextView.self) {
            return true
        }

        // SwiftUI `TextEditor` renders into a private text view.
        if let textEditorTextView = renderClasses.textEditorTextView,
            view.isKind(of: textEditorTextView)
        {
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
        if let drawingLayer = renderClasses.drawingLayer, layer.isKind(of: drawingLayer) {
            return true
        }

        // Check for SwiftUI UILabelLayer delegate
        if let buttonLabel = renderClasses.buttonLabel, layer.delegate?.isKind(of: buttonLabel) == true {
            return true
        }

        return false
    }

    /// Checks if a CALayer is an image-rendering layer (iOS 26+)
    func isImageLayer(_ layer: CALayer) -> Bool {
        // 1. MOST SPECIFIC: Known SwiftUI class (exact match)
        //    Fast pointer comparison, catches specific iOS <26 SwiftUI case
        if let imageLayer = renderClasses.imageLayer, type(of: layer) == imageLayer {
            return true
        }

        // SF Symbols: rendered as a shape layer, not an image layer. See
        // ``SwiftUIRenderClasses/colorShapeLayer``.
        if let colorShapeLayer = renderClasses.colorShapeLayer, type(of: layer) == colorShapeLayer {
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

    // MARK: - Frame conversion

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
