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
    /// Retained for source compatibility. New code should prefer the unified
    /// `.mpReplay(sensitive:text:)`, which is the single entry point for all
    /// Mixpanel SwiftUI replay annotations. This forwards to it.
    public func mpReplaySensitive(_ isSensitive: Bool) -> some View {
        self.mpReplay(sensitive: isSensitive)
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
