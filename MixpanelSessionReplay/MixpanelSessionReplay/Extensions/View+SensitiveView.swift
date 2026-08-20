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

struct MixpanelReplaySensitiveModifier: ViewModifier {
    let isSensitive: Bool?

    func body(content: Content) -> some View {
        MixpanelSensitiveWrapper(isSensitive: isSensitive) {
            content
        }
    }
}

/// Wraps SwiftUI content in a UIHostingController to access the underlying UIView
/// and mark it as sensitive/non-sensitive for Mixpanel session replay
struct MixpanelSensitiveWrapper<Content: View>: UIViewControllerRepresentable {
    /// Sensitivity flag: true = mask view, false = show view, nil = not specified
    let isSensitive: Bool?
    /// The SwiftUI content to wrap
    let content: Content

    init(isSensitive: Bool?, @ViewBuilder content: () -> Content) {
        self.isSensitive = isSensitive
        self.content = content()
    }

    /// Creates the UIHostingController and sets the sensitivity flag on its view
    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let controller = UIHostingController(rootView: content)

        // Always set the sensitivity flag, even when nil, to prevent stale values
        controller.view.mpReplaySensitive = isSensitive
        // iOS 15 and below: disable autoresizing to respect SwiftUI layout
        if #available(iOS 16.0, *) {
            // sizeThatFits will handle sizing
        } else {
            controller.view.translatesAutoresizingMaskIntoConstraints = false
        }
        return controller
    }

    /// Updates the content and sensitivity flag when SwiftUI state changes
    func updateUIViewController(_ uiViewController: UIHostingController<Content>, context: Context) {
        // Update content when state changes
        uiViewController.rootView = content

        // Always update sensitivity flag, even when nil, to clear previous values
        uiViewController.view.mpReplaySensitive = isSensitive
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIHostingController<Content>, context: Context)
        -> CGSize?
    {
        return uiViewController.sizeThatFits(
            in: CGSize(
                width: proposal.width ?? .infinity,
                height: proposal.height ?? .infinity
            ))
    }
}

// Extension to make it easy to use
extension View {
    public func mpReplaySensitive(_ isSensitive: Bool?) -> some View {
        modifier(MixpanelReplaySensitiveModifier(isSensitive: isSensitive))
    }
}

class SensitiveViewWrapper: UIView {}

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
