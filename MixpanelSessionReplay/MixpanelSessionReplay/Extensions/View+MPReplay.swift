//
//  View+MPReplay.swift
//  MixpanelSessionReplay
//
//  The single SwiftUI entry point for Mixpanel session replay annotations.
//
//  `.mpReplay(sensitive:wireframeText:)` lets a developer, in one modifier, both
//  control masking and declare the wireframe text for a SwiftUI view. The two
//  concerns are orthogonal:
//
//    - `sensitive: true`  covers the view with an opaque rectangle in the
//                         recording (the pixels are not captured).
//    - `sensitive: false` opts the view out of automatic masking.
//    - `wireframeText:`   declares the text recorded for the view in the
//                         wireframe event. Apple does not expose a public API
//                         for reading rendered strings from SwiftUI's internal
//                         drawing views, so SwiftUI content otherwise ships with
//                         no text.
//
//  `wireframeText` is authored by the developer, not scraped from the screen, so
//  it is sent even when the view is `sensitive` — masking hides the pixels, the
//  declared text still describes the view for the AI summary. It is therefore
//  the developer's responsibility to ensure `wireframeText` is not itself
//  sensitive; if it could be, omit it.
//
//  Implementation: a single `MPReplayWrapper` UIView is planted as a
//  `.background` on the SwiftUI view (the same all-public pattern used by the
//  legacy `.mpReplaySensitive`), carrying both the sensitivity flag and the
//  declared text as associated objects. The wireframe walker reads them during
//  traversal. No private class references, no reflection into SwiftUI internals.
//

import ObjectiveC
import SwiftUI
import UIKit

/// Marker UIView planted behind SwiftUI content by `.mpReplay(...)`. Identified
/// by class so the walker can distinguish a Mixpanel annotation from an
/// ordinary background and read its declared text.
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
    /// Annotates a SwiftUI view for Mixpanel session replay.
    ///
    /// This is the single entry point for all Mixpanel SwiftUI replay work —
    /// prefer it over the legacy `.mpReplaySensitive(_:)`.
    ///
    /// - Parameters:
    ///   - sensitive: Pass `true` to mask the view (an opaque rectangle is drawn
    ///     over it in the recording and its pixels are not captured), or `false`
    ///     to explicitly opt out of automatic masking. Defaults to `nil` (no
    ///     masking override).
    ///   - wireframeText: The text recorded for this view in the wireframe.
    ///     SwiftUI does not expose its rendered strings, so declare them here.
    ///     The declared string does not have to match what SwiftUI renders — use
    ///     it for analytical labels (`"submit-cta"`) or to describe otherwise
    ///     opaque content. Defaults to `nil` (no declared text).
    ///
    ///     **This text is sent even when `sensitive` is `true`** — masking hides
    ///     the pixels, while the declared text still describes the view for the
    ///     AI summary. Because it is authored by you (not read from the screen),
    ///     it is your responsibility to ensure `wireframeText` is not itself
    ///     sensitive; if it could be, omit it.
    ///
    /// ```swift
    /// Text("Welcome").mpReplay(wireframeText: "Welcome")
    /// Image("avatar").mpReplay(sensitive: true, wireframeText: "profile photo")
    /// Button("Continue") { … }.mpReplay(wireframeText: "Continue")
    /// ```
    public func mpReplay(sensitive: Bool? = nil, wireframeText: String? = nil) -> some View {
        self.modifier(MPReplayModifier(sensitive: sensitive, wireframeText: wireframeText))
    }
}

private var mpWireframeTextKey: UInt8 = 0

extension UIView {
    /// Wireframe text declared by `.mpReplay(text:)`. The walker reads this to
    /// synthesize a wireframe element for SwiftUI content that otherwise cannot
    /// be extracted.
    public var mpWireframeText: String? {
        get { objc_getAssociatedObject(self, &mpWireframeTextKey) as? String }
        set {
            objc_setAssociatedObject(
                self, &mpWireframeTextKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
