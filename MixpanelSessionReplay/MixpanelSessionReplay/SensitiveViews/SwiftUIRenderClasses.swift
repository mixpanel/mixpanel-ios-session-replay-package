//
//  SwiftUIRenderClasses.swift
//  MixpanelSessionReplay
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import UIKit

/// The private UIKit and SwiftUI classes replay detection matches against.
///
/// SwiftUI draws its own text and images rather than composing UIKit views, so the
/// only handle on "this is a Text" or "this is an Image" is the concrete render
/// class — which is private, differs between iOS 18 and 26, and in two cases is not
/// resolvable by its readable name at all. Both masking (``SensitiveViewManager``)
/// and wireframe description (``WireframeClassifier``) need the same handles, so
/// they are resolved once here and shared.
///
/// Resolution happens at init: `NSClassFromString` returning `nil` is normal — the
/// class may not exist on this OS version — and every caller treats a `nil` handle
/// as "this detection does not apply."
struct SwiftUIRenderClasses {

    // MARK: - Byte-coded names

    /// Byte codes for SwiftUI's private mangled
    /// `_TtC7SwiftUIP33_863CCF9D49B535DAEB1C7D61BEE53B5914CGDrawingLayer` class name.
    /// Stored as individual `UInt8`s (not a contiguous string literal) so the symbol
    /// never appears as plain text in the binary's string table.
    static let drawingLayerCodes: [UInt8] = [
        95, 84, 116, 67, 55, 83, 119, 105, 102, 116, 85, 73, 80, 51, 51, 95,
        56, 54, 51, 67, 67, 70, 57, 68, 52, 57, 66, 53, 51, 53, 68, 65, 69,
        66, 49, 67, 55, 68, 54, 49, 66, 69, 69, 53, 51, 66, 53, 57, 49, 52,
        67, 71, 68, 114, 97, 119, 105, 110, 103, 76, 97, 121, 101, 114,
    ]

    /// Byte codes for SwiftUI's private mangled `ColorShapeLayer` class name, stored
    /// the same way as ``drawingLayerCodes``. `NSClassFromString("SwiftUI.ColorShapeLayer")`
    /// does not resolve it — unlike `SwiftUI.ImageLayer`, this one carries a private
    /// discriminator. The discriminator is stable: identical on iOS 18.0 and 26.2.
    static let colorShapeLayerCodes: [UInt8] = [
        95, 84, 116, 67, 55, 83, 119, 105, 102, 116, 85, 73, 80, 51, 51, 95,
        69, 49, 57, 70, 52, 57, 48, 68, 50, 53, 68, 53, 69, 48, 69, 67,
        56, 65, 50, 52, 57, 48, 51, 65, 70, 57, 53, 56, 69, 51, 52, 49,
        49, 53, 67, 111, 108, 111, 114, 83, 104, 97, 112, 101, 76, 97, 121, 101,
        114,
    ]

    // MARK: - Resolved handles

    /// `SwiftUI.TextEditorTextView` — the view a `TextEditor` renders into. Unaffected
    /// by the Liquid Glass UI change.
    let textEditorTextView: AnyClass? = NSClassFromString("SwiftUI.TextEditorTextView")

    /// `SwiftUI.ImageLayer` — the layer a bitmap `Image` renders into. Unaffected by
    /// the Liquid Glass UI change.
    let imageLayer: AnyClass? = NSClassFromString("SwiftUI.ImageLayer")

    /// `SwiftUI.CGDrawingView` — where SwiftUI `Text` lands on iOS 18 and earlier.
    let drawingView: AnyClass? = NSClassFromString("SwiftUI.CGDrawingView")

    /// `UIButtonLabel` — a `UIButton`'s title label. Reached as a layer *delegate*,
    /// which is how iOS 26 surfaces button text to the layer walk.
    let buttonLabel: AnyClass? = NSClassFromString("UIButtonLabel")

    /// iOS 26+: SwiftUI `Text` renders directly into this `CALayer` subclass rather
    /// than creating a `CGDrawingView`, so text detection forks on OS version.
    let drawingLayer: AnyClass?

    /// SwiftUI renders an SF Symbol into a `ColorShapeLayer` rather than an
    /// `ImageLayer`, so symbols were invisible to image detection: `maskAllImages` did
    /// not gray them and the wireframe did not describe them, while a bitmap
    /// `Image(uiImage:)` in the same position was handled correctly.
    ///
    /// Matching this class is narrow, not a catch-all for SwiftUI shapes. Measured on
    /// iOS 18.0 and 26.2: `Color`, `Rectangle().fill()`, `Circle().fill()`,
    /// `RoundedRectangle().fill()` and `Capsule().stroke()` all render into a plain
    /// `CALayer` (usually via `backgroundColor`), and a gradient into `GradientLayer`.
    /// `ColorShapeLayer` was produced only by the symbol — pinned by
    /// `test_swiftui_shapesAreNotMaskedAsImages`.
    let colorShapeLayer: AnyClass?

    init() {
        drawingLayer = ObfuscatedClassLookup.resolveClass(from: Self.drawingLayerCodes)
        colorShapeLayer = ObfuscatedClassLookup.resolveClass(from: Self.colorShapeLayerCodes)
    }
}

extension Array where Element == UInt8 {
    func decodedString() -> String? {
        String(bytes: self, encoding: .utf8)
    }
}

enum ObfuscatedClassLookup {
    static func resolveClass(from codes: [UInt8]) -> AnyClass? {
        guard let name = codes.decodedString() else { return nil }
        return NSClassFromString(name)
    }
}
