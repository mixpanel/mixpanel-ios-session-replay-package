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

extension View {
    /// Marks a SwiftUI view as sensitive (masked) or explicitly safe.
    ///
    /// - Parameter isSensitive: Pass `true` to mask the view — an opaque
    ///   rectangle is drawn over it in the recording and its pixels are not
    ///   captured. Pass `false` to explicitly opt the view out of automatic
    ///   masking.
    ///
    /// This controls **pixels only**. To declare the text recorded for the view
    /// in the `mp_wireframe` event, use ``SwiftUI/View/mpWireframeText(_:)`` —
    /// the two concerns are orthogonal and chain:
    ///
    /// ```swift
    /// Image("avatar").mpReplaySensitive(true).mpWireframeText("profile photo")
    /// ```
    public func mpReplaySensitive(_ isSensitive: Bool) -> some View {
        self.modifier(MPReplayModifier(sensitive: isSensitive, wireframeText: nil))
    }
}

private var mpReplaySensitiveKey: UInt8 = 0

extension UIView {
    /// Marks this view as sensitive (masked) or explicitly safe.
    ///
    /// Controls **pixels only**. To declare the text recorded for the view in
    /// the `mp_wireframe` event, set ``mpWireframeText`` — the two concerns are
    /// orthogonal.
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
