//
//  View+WireframeText.swift
//  MixpanelSessionReplay
//
//  Opt-in text capture for SwiftUI content.
//
//  Apple does not expose a public API for reading rendered text from SwiftUI's
//  private drawing views. The SDK cannot semantically extract the string
//  content of a `Text("Welcome")` at snapshot time.
//
//  `.mpWireframeText(_:)` gives developers an explicit way to declare the
//  visible text that should appear in the wireframe event for a SwiftUI
//  element. It plants a plain UIView as a `.background` on the SwiftUI view
//  (same pattern used by `.mpReplaySensitive`), stores the label as an
//  associated object, and the wireframe walker reads it during traversal.
//
//  All-public API: `.background`, `UIViewRepresentable`, associated objects.
//  No private class references, no reflection into SwiftUI internals.
//

import ObjectiveC
import SwiftUI
import UIKit

/// Plain UIView planted behind SwiftUI content to carry the wireframe text
/// label. Identified by class so the walker can distinguish it from
/// `SensitiveViewWrapper` and other backgrounds.
class WireframeTextWrapper: UIView {}

struct WireframeTextWrapperRepresentable: UIViewRepresentable {
    let onCreate: (WireframeTextWrapper) -> Void

    func makeUIView(context: Context) -> WireframeTextWrapper {
        let wrapper = WireframeTextWrapper()
        onCreate(wrapper)
        return wrapper
    }

    func updateUIView(_ uiView: WireframeTextWrapper, context: Context) {
        onCreate(uiView)
    }
}

struct WireframeTextModifier: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content
            .background(
                WireframeTextWrapperRepresentable { wrapper in
                    wrapper.mpWireframeText = self.text
                }
            )
    }
}

extension View {
    /// Declares the visible text of this SwiftUI view for wireframe capture.
    ///
    /// Apple does not expose a public API for reading rendered strings from
    /// SwiftUI's internal drawing views, so wireframes for SwiftUI-rendered
    /// content otherwise ship with `text=nil`. Use this modifier on the
    /// Text/Button/etc. whose content you want to appear in the wireframe.
    ///
    /// The declared string is what the wireframe event carries — it does not
    /// have to match what SwiftUI renders. Use it to expose analytical labels
    /// (e.g. `"submit-cta"`) or to redact sensitive content by declaring a
    /// placeholder (e.g. `"[email]"`).
    ///
    /// ```swift
    /// Text("Welcome").mpWireframeText("Welcome")
    /// Button("Continue") { … }.mpWireframeText("Continue")
    /// ```
    public func mpWireframeText(_ text: String) -> some View {
        self.modifier(WireframeTextModifier(text: text))
    }
}

private var mpWireframeTextKey: UInt8 = 0

extension UIView {
    /// Wireframe text label attached by `.mpWireframeText(_:)`. The walker
    /// reads this to synthesize a wireframe element for SwiftUI content that
    /// otherwise cannot be extracted.
    public var mpWireframeText: String? {
        get { objc_getAssociatedObject(self, &mpWireframeTextKey) as? String }
        set {
            objc_setAssociatedObject(
                self, &mpWireframeTextKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
