//
//  WireframeClassifier.swift
//  MixpanelSessionReplay
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import UIKit

/// Answers the two questions a wireframe element is made of: *what kind of thing is
/// this view* (``role(for:)``) and *what does it say* (``text(for:role:)``).
///
/// Deliberately knows nothing about masking. Masking decides which pixels ship;
/// this decides how a view is described, and the walk in
/// ``SensitiveViewManager/walkHierarchy(in:window:)`` is what combines the two. A
/// view can be masked and still described (see ``MPMaskDecision/declared``), so
/// keeping the two apart is what lets the AI summary hear about a redacted form
/// without its contents leaking.
struct WireframeClassifier {

    /// Shared with ``SensitiveViewManager`` so the two sides cannot disagree about
    /// what a given SwiftUI render class is — they did once, and a SwiftUI image was
    /// masked on iOS 18 but never described.
    let renderClasses: SwiftUIRenderClasses

    /// Mirrors ``MPWireframesOptions/useAccessibilityLabelFallback``. Governs tier 3
    /// of the text chain only; masking is unaffected. When false, an element with no
    /// rendered text of its own ships as a textless `role + bounds` shell rather than
    /// borrowing its `accessibilityLabel`.
    var useAccessibilityLabelFallback: Bool = false

    /// Map a UIView to a wireframe role. `nil` for views we do not emit
    /// (containers, layout wrappers, MKMapView, etc.).
    func role(for view: UIView) -> WireframeRole? {
        // Order matters: UIButton before UILabel (UIButton contains a UILabel
        // titleLabel; we want the button, not its inner label).
        if view is UIButton { return .button }
        if view is UITextField { return .input }
        // Every `UITextView` is an input, editable or not — see
        // ``SensitiveViewManager/isTextInput(view:)`` for why, and for the Android and
        // Flutter behaviour this matches.
        if view is UITextView { return .input }
        if view is UILabel { return .text }
        if view is UIImageView { return .image }
        // No role for a `WKWebView`, deliberately. Web content renders out of process and the
        // SDK can read none of it, so any role here would be a guess: `.text` shipped a textless
        // full-screen `text` shell, which reads as "text we failed to extract" rather than "not
        // our content". Android's `classifyAndroidView` has no `WebView` branch either, and
        // Flutter does not classify platform views, so emitting nothing is also the parity
        // behaviour. Masking is unaffected — `maskAllWebViews` still paints over the pixels.
        if let textEditorTextView = renderClasses.textEditorTextView,
            view.isKind(of: textEditorTextView)
        {
            return .input
        }
        // A pre-iOS-26 SwiftUI `Image` is identified by its *backing layer* class, not
        // its view class — the same test `isImage(view:)` already makes for masking.
        // Without this the two sides disagreed: the image was masked but never
        // described, so a SwiftUI screen summarized as [text, text] on iOS 18 and
        // [text, image, text] on iOS 26, where the layer walk classifies it. Masking
        // was correct throughout; only the wireframe lost the element.
        if let imageLayer = renderClasses.imageLayer, type(of: view.layer) == imageLayer { return .image }
        if let colorShapeLayer = renderClasses.colorShapeLayer, type(of: view.layer) == colorShapeLayer {
            return .image
        }
        if let drawingView = renderClasses.drawingView, type(of: view) == drawingView { return .text }
        // React Native draws its own text and (on the legacy architecture) its own
        // images, so none of the UIKit checks above see them.
        if let reactNativeRole = ReactNativeWireframeSupport.role(for: view) {
            return reactNativeRole
        }
        // Last: a role the developer declared through accessibility. Intent, not inference —
        // and the only signal available for a control that is a plain view, which is what
        // React Native's `Pressable`/`TouchableOpacity` produce.
        return accessibilityRole(for: view)
    }

    /// Role implied by a view's accessibility traits, or `nil` if it declares none we honor.
    ///
    /// Reads the trait *bitmask*, never a string, so nothing developer-authored can reach the
    /// `role` field — see ``WireframeRole``. UIKit collapses most of React Native's
    /// `accessibilityRole` values to `UIAccessibilityTraitNone`, so button, link and header are
    /// all that is distinguishable here; Android reads its full role enum and reports more.
    /// That asymmetry is deliberate.
    ///
    /// Ordered most specific first, which matters because these are a bitmask and React Native
    /// composes them: its switch trait is `0x20000000000001`, whose low bit *is*
    /// `UIAccessibilityTraitButton` (that is how iOS surfaces a switch to VoiceOver). Testing
    /// `.button` first would therefore report every switch as a button. `imagebutton` sets
    /// image|button and is deliberately left as a button, because the action is what a summary
    /// cares about.
    ///
    /// Note the trait is only present when the view is an accessibility element: React Native
    /// applies `accessibilityRole` to traits for a view that is `accessible`, which `Pressable`
    /// and `TouchableOpacity` default to but a hand-written `<View>` does not.
    func accessibilityRole(for view: UIView) -> WireframeRole? {
        let traits = view.accessibilityTraits
        // React Native's composite switch trait — not a UIKit constant, so it is spelled out.
        let switchTrait = UIAccessibilityTraits(rawValue: 0x0020_0000_0000_0001)
        if traits.contains(switchTrait) { return .switch }
        if traits.contains(.button) { return .button }
        if traits.contains(.link) { return .link }
        if traits.contains(.header) { return .header }
        return nil
    }

    // No text absorption, deliberately.
    //
    // An earlier pass borrowed a roled container's descendants' text so the control would not
    // ship textless. It was wrong twice over: the goldens showed it swallowing nested controls
    // (`role_nested_control` reported one `button: "Cupcake Add"` and lost the inner button), and
    // once an accessibility-derived role stopped closing the subtree the label was already there
    // as a sibling element with bounds inside the control. A summary can associate the two by
    // geometry; it cannot recover an element that was never emitted.

    /// Tiers 2 and 3 of the text precedence chain: the view's own rendered text,
    /// then — only when ``useAccessibilityLabelFallback`` is on — its
    /// `accessibilityLabel`. Tier 1 (declared text) is resolved by the caller,
    /// which never reaches this method when declared text is present.
    func text(for view: UIView, role: WireframeRole) -> String? {
        switch role {
            case .input:
                return nil
            case .image:
                return accessibilityFallback(for: view)
            case .button, .link, .header, .checkbox, .switch, .radio, .tab:
                // A real UIButton knows its own title.
                if let button = view as? UIButton {
                    if let title = button.currentTitle, !title.isEmpty { return title }
                    if let title = button.titleLabel?.text, !title.isEmpty { return title }
                }
                // An accessibility-derived role deliberately gets *no* text.
                //
                // Those roles land on containers, and React Native gives an accessible container
                // an `accessibilityLabel` synthesized by concatenating its descendants. Reading
                // it duplicated the label: the container reported "Log in" and the `<Text>`
                // inside it emitted "Log in" again, because such a role does not close the
                // subtree. Worse, that synthesized label is the same
                // swallow-the-subtree-into-one-string behaviour this deliberately avoids.
                //
                // So the control ships as a textless shell with its label beside it, bounds
                // nested inside — the same shape Android produces.
                if accessibilityRole(for: view) != nil { return nil }
                return accessibilityFallback(for: view)
            case .text:
                if let label = view as? UILabel {
                    if let text = label.text, !text.isEmpty { return text }
                }
                // SwiftUI text (iOS <=18 `SwiftUI.CGDrawingView`): emit the
                // role + bounds shell with no text. SwiftUI doesn't expose its
                // rendered Text reliably (it lives on `_UIHostingView._rootView`,
                // not this leaf render view), and we deliberately do not read it
                // via private reflection. The accessibility fallback below is
                // skipped on purpose; developers label these with
                // `.mpWireframeText(_:)`.
                if let drawingView = renderClasses.drawingView, type(of: view) == drawingView {
                    return nil
                }
                // React Native paragraph text. Tier 2, not the label tier — see
                // `ReactNativeWireframeSupport.renderedText(for:)`.
                if let reactNativeText = ReactNativeWireframeSupport.renderedText(for: view) {
                    return reactNativeText
                }
                return accessibilityFallback(for: view)
        }
    }

    /// Last-resort text source, honoring ``useAccessibilityLabelFallback``. An
    /// accessibility label is not drawn on screen, so a customer who cannot vet
    /// what their labels hold can switch this tier off and ship bare
    /// `role + bounds` shells instead.
    private func accessibilityFallback(for view: UIView) -> String? {
        guard useAccessibilityLabelFallback else { return nil }
        let label = view.accessibilityLabel
        return (label?.isEmpty == false) ? label : nil
    }
}
