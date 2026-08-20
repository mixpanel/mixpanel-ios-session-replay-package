//
//  View+MPReplay.swift
//  MixpanelSessionReplay
//
//  The shared SwiftUI plumbing behind Mixpanel's replay annotations, plus the
//  `.mpWireframeText(_:)` entry point.
//
//  There are two SwiftUI annotations and they are deliberately separate, one
//  concern each:
//
//    - `.mpReplaySensitive(_:)`  controls masking (see View+SensitiveView.swift).
//        `true`  covers the view with an opaque rectangle in the recording (the
//                pixels are not captured).
//        `false` opts the view out of automatic masking.
//    - `.mpWireframeText(_:)`    declares the text recorded for the view in the
//        wireframe event. Apple does not expose a public API for reading
//        rendered strings from SwiftUI's internal drawing views, so SwiftUI
//        content otherwise ships with no text.
//
//  The two are orthogonal and chain: `wireframeText` is authored by the
//  developer, not scraped from the screen, so it is sent even when the view is
//  sensitive — masking hides the pixels, the declared text still describes the
//  view for the AI summary. It is therefore the developer's responsibility to
//  ensure the declared text is not itself sensitive; if it could be, omit it.
//
//  Implementation: both modifiers plant an `MPReplayWrapper` UIView as a
//  `.background` on the SwiftUI view, carrying the sensitivity flag and/or the
//  declared text as associated objects. The wireframe walker reads them during
//  traversal. Chaining both plants two wrappers; they are leaf views at
//  identical bounds, and only the text-bearing one emits a wireframe element, so
//  the output matches annotating with either alone. No private class references,
//  no reflection into SwiftUI internals.
//

import ObjectiveC
import SwiftUI
import UIKit

/// Marker UIView planted behind SwiftUI content by `.mpReplaySensitive(_:)` and
/// `.mpWireframeText(_:)`. Identified by class so the walker can distinguish a
/// Mixpanel annotation from an ordinary background and read its declared text.
class MPReplayWrapper: UIView {}

struct MPReplayWrapperRepresentable: UIViewRepresentable {
    let onUpdate: (MPReplayWrapper) -> Void

    func makeUIView(context: Context) -> MPReplayWrapper {
        let wrapper = MPReplayWrapper()
        onUpdate(wrapper)
        return wrapper
    }

    func updateUIView(_ uiView: MPReplayWrapper, context: Context) {
        onUpdate(uiView)
    }
}

/// Shared implementation for both public SwiftUI annotations. Each public
/// modifier sets exactly one of the two fields; the other stays `nil`.
struct MPReplayModifier: ViewModifier {
    let sensitive: Bool?
    let wireframeText: String?

    func body(content: Content) -> some View {
        content.background(
            MPReplayWrapperRepresentable { wrapper in
                wrapper.mpReplaySensitive = self.sensitive
                wrapper.mpWireframeText = self.wireframeText
            }
        )
    }
}

extension View {
    /// Declares the text recorded for this view in the `mp_wireframe` event.
    ///
    /// Apple exposes no public API for reading rendered strings out of SwiftUI's
    /// drawing views, so SwiftUI content ships as textless shells unless you
    /// label it here. The declared string does not have to match what SwiftUI
    /// renders — use it for analytical labels (`"submit-cta"`) or to describe
    /// otherwise opaque content (a `Canvas` chart).
    ///
    /// Masking and declared text are **orthogonal** — this modifier has no
    /// bearing on which pixels are captured, and `.mpReplaySensitive(_:)` has no
    /// bearing on the declared text. Chain them freely.
    ///
    /// - Parameter text: The text to record for this view. Blank strings are
    ///   ignored.
    ///
    ///   **This text is sent even when the view is masked** — masking hides the
    ///   pixels, while the declared text still describes the view for the AI
    ///   summary. Because it is authored by you (not read from the screen), it is
    ///   your responsibility to ensure `text` is not itself sensitive; if it
    ///   could be, omit it.
    ///
    /// ```swift
    /// Text("Welcome").mpWireframeText("Welcome")
    /// Button("Continue") { … }.mpWireframeText("Continue")
    /// Image("avatar").mpReplaySensitive(true).mpWireframeText("profile photo")
    /// ```
    public func mpWireframeText(_ text: String) -> some View {
        self.modifier(MPReplayModifier(sensitive: nil, wireframeText: text))
    }
}

private var mpWireframeTextKey: UInt8 = 0

extension UIView {
    /// Wireframe text declared for this view. The walker reads this to
    /// synthesize a wireframe element for content that otherwise cannot be
    /// extracted.
    ///
    /// This is the UIKit entry point, and the counterpart to SwiftUI's
    /// `.mpWireframeText(_:)`. Set it directly on any view:
    ///
    /// ```swift
    /// chartView.mpWireframeText = "monthly spend"
    /// ```
    ///
    /// Orthogonal to ``mpReplaySensitive`` — the declared text is sent even when
    /// the view is masked, because it is authored by you rather than scraped
    /// from the screen. Set it to `nil` to clear it.
    public var mpWireframeText: String? {
        get { objc_getAssociatedObject(self, &mpWireframeTextKey) as? String }
        set {
            objc_setAssociatedObject(
                self, &mpWireframeTextKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
