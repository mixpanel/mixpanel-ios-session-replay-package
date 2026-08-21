//
//  View+SensitiveView.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import ObjectiveC
import SwiftUI
import UIKit

protocol SensitiveView {
    var frameRelativeToWindow: CGRect? { get }
}

extension UIView {
    /// Finds the view controller that manages this view.
    ///
    /// - Returns: The nearest `UIViewController` in the responder chain, or `nil` if none is found.
    func parentViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let currentResponder = responder {
            if let viewController = currentResponder as? UIViewController {
                return viewController
            }
            responder = currentResponder.next
        }
        return nil
    }

    func isVisible() -> Bool {
        if isHidden || alpha == 0 || frame == .zero {
            return false
        }
        return true
    }
}

extension UIView: SensitiveView {
    public var frameRelativeToWindow: CGRect? {
        guard let window = self.window else {
            return nil
        }

        // Convert the view's bounds to the window's coordinate system
        return self.convert(self.bounds, to: window)
    }
}

/// Creates an invisible marker view as a sibling to mark the parent view as sensitive/safe
/// Uses .background() to create a sibling relationship without wrapping or affecting layout
struct MixpanelSensitiveMarker: UIViewRepresentable {
    /// Sensitivity flag: true = mask view, false = show view, nil = not specified
    let isSensitive: Bool?

    func makeCoordinator() -> MarkerState {
        MarkerState()
    }

    func makeUIView(context: Context) -> UIView {
        let marker = UIView(frame: .zero)
        marker.isHidden = true  // Invisible - doesn't affect layout or rendering
        marker.isUserInteractionEnabled = false  // Doesn't intercept touches
        return marker
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let state = context.coordinator

        // Clear previous parent if it changed (prevents stale metadata)
        if let previousParent = state.markedParent, previousParent !== uiView.superview {
            previousParent.mpReplaySensitive = nil
        }

        // Mark the current parent view (which contains both the marker and actual content)
        // This allows traversal into the content's children normally
        uiView.superview?.mpReplaySensitive = isSensitive

        // Track the parent we just marked for future cleanup
        state.markedParent = uiView.superview
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: MarkerState) {
        // Clean up: clear the sensitivity flag when marker is removed
        // This prevents stale metadata when views are conditionally shown/hidden
        coordinator.markedParent?.mpReplaySensitive = nil
        coordinator.markedParent = nil
    }

    /// Tracks the parent view that has been marked with sensitivity metadata
    /// Used for cleanup when the marker is removed or moves to a different parent
    class MarkerState {
        weak var markedParent: UIView?
    }
}

struct MixpanelReplaySensitiveModifier: ViewModifier {
    let isSensitive: Bool?

    func body(content: Content) -> some View {
        content.background(MixpanelSensitiveMarker(isSensitive: isSensitive))
    }
}

extension View {
    public func mpReplaySensitive(_ isSensitive: Bool?) -> some View {
        modifier(MixpanelReplaySensitiveModifier(isSensitive: isSensitive))
    }
}

private var mpReplaySensitiveKey: UInt8 = 0

extension UIView {
    public var mpReplaySensitive: Bool? {
        get { objc_getAssociatedObject(self, &mpReplaySensitiveKey) as? Bool }
        set {
            objc_setAssociatedObject(
                self, &mpReplaySensitiveKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

extension CALayer {
    // Note: Unlike UIView.isVisible(), we don't check bounds here
    // because some layers (e.g., UIBarButton) may have zero bounds
    // but still represent visible content. Frame size filtering
    // happens later in getFrame(for:in:)
    func isVisible() -> Bool {
        if !isHidden && opacity > 0 {
            return true
        }
        return false
    }
}
