//
//  ReactNativeWireframeSupport.swift
//  MixpanelSessionReplay
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import UIKit

/// Wireframe classification and text extraction for React Native's text and image views.
///
/// React Native draws its own text: neither architecture backs a `<Text>` with a
/// `UILabel`, so ``SensitiveViewManager/classifyForWireframe(view:)`` mapped every RN
/// paragraph to `nil` and an RN screen produced a wireframe with no text elements in it at
/// all — not even textless shells. The masking side was never affected (the React Native
/// bridge registers these classes through the public `addSensitiveClass`, so the pixels
/// were always grayed); only the description was missing.
///
/// The two architectures land on different tiers of the text precedence chain, because
/// only one of them exposes the drawn string exactly:
///
/// | | class | text source | tier |
/// |---|---|---|---|
/// | Fabric | `RCTParagraphComponentView` | `attributedText` | 2 — rendered text, always read |
/// | Paper | `RCTTextView` | `accessibilityLabel` | 3 — needs `useAccessibilityLabelFallback` |
///
/// Both are classified either way, so a Paper `<Text>` still ships its `role + bounds`
/// shell with the fallback off; only its text waits on the customer's setting. See
/// ``renderedText(for:)``.
///
/// This is deliberately a per-class table inside the SDK rather than a new public
/// extension point, for the same reason the SwiftUI private classes are: the walk is where
/// classification happens, and the alternative — a public "register a text provider" API —
/// would exist on iOS only, since Android's `ReactTextView` is a `TextView` subclass and
/// needs nothing. Keeping the knowledge here keeps the *public* surface identical across
/// platforms.
///
/// ## Masking still decides
///
/// Nothing here reads text that masking has hidden. The bridge registers RN's text classes
/// as sensitive whenever the customer leaves `.text` in `autoMaskedViews` (the default), so
/// those views take the masked path and ship as textless shells. When the view emitting the
/// element is an *ancestor* of the masked one — Fabric's `RCTParagraphComponentView` holds
/// the masked `RCTParagraphTextView` that does the drawing — the emitter's geometric layer
/// strips the text, because the ancestor's bounds necessarily intersect its own child's
/// mask rect. Both routes are pinned by `ReactNativeWireframeTests`.
enum ReactNativeWireframeSupport {

  /// Fabric (New Architecture, the default since RN 0.76). The component view for
  /// `<Text>`; its `attributedText` is declared in `RCTParagraphComponentView.h` as
  /// "to be only used by external introspection and debug tools", which is exactly this.
  private static let paragraphComponentViewClass: AnyClass? =
    NSClassFromString("RCTParagraphComponentView")

  /// Paper (legacy architecture). Classified so the element still ships, but its text is
  /// left to the accessibility-label tier: `RCTTextView` keeps its `NSTextStorage` private
  /// and publishes the string only through its `accessibilityLabel` override. See
  /// ``renderedText(for:)``.
  private static let legacyTextViewClass: AnyClass? = NSClassFromString("RCTTextView")

  /// Paper's `<Image>` is an `RCTView` that draws into its own layer, so it is invisible
  /// to the `UIImageView` check. Fabric's is backed by `RCTUIImageViewAnimated`, a real
  /// `UIImageView` subclass, and is already classified without help.
  private static let legacyImageViewClass: AnyClass? = NSClassFromString("RCTImageView")

  /// Selector for Fabric's introspection property, resolved once.
  private static let attributedTextSelector = NSSelectorFromString("attributedText")

  /// True when this app links React Native at all. Lets the walk skip the class checks
  /// entirely for native-only apps.
  static let isReactNativeApp: Bool =
    paragraphComponentViewClass != nil || legacyTextViewClass != nil
    || legacyImageViewClass != nil

  /// The wireframe role for a React Native view, or `nil` if this is not one of the RN
  /// views the UIKit checks miss.
  static func role(for view: UIView) -> WireframeRole? {
    guard isReactNativeApp else { return nil }
    if let paragraphComponentViewClass, view.isKind(of: paragraphComponentViewClass) {
      return .text
    }
    if let legacyTextViewClass, view.isKind(of: legacyTextViewClass) { return .text }
    if let legacyImageViewClass, view.isKind(of: legacyImageViewClass) { return .image }
    return nil
  }

  /// The rendered text of a React Native paragraph, or `nil` when there is no exact
  /// source for it.
  ///
  /// Tier 2 of the text precedence chain — the element's own rendered text — so it is
  /// *not* gated by ``MPWireframesOptions/useAccessibilityLabelFallback``. Only Fabric
  /// reaches it: `attributedText` is rebuilt from the same `AttributedString` the view
  /// draws, so it is exactly what is on screen.
  ///
  /// **Paper deliberately returns `nil` here.** `RCTTextView` keeps its `NSTextStorage`
  /// private and publishes the string only by overriding `accessibilityLabel`, and that
  /// override prefers an explicitly-set label over the rendered text — so what comes back
  /// may be a label describing the view rather than the text drawn in it, and which of the
  /// two it is cannot be told from outside RN. That is precisely the uncertainty
  /// `useAccessibilityLabelFallback` exists to govern, so Paper text is left to fall
  /// through to the label tier in `extractWireframeText`, where the customer's setting
  /// decides. With the fallback off, a legacy-architecture `<Text>` ships as a
  /// `role + bounds` shell and `.mpWireframeText(_:)` is the way to describe it.
  ///
  /// (Reading the private `_textStorage` ivar by KVC would resolve the ambiguity exactly,
  /// and is rejected for the same reason the SwiftUI reflection extractor was: the SDK
  /// does not reach into another framework's internals.)
  static func renderedText(for view: UIView) -> String? {
    guard isReactNativeApp else { return nil }

    guard let paragraphComponentViewClass, view.isKind(of: paragraphComponentViewClass),
      view.responds(to: attributedTextSelector),
      let attributed = view.value(forKey: "attributedText") as? NSAttributedString
    else {
      return nil
    }
    return attributed.string.isEmpty ? nil : attributed.string
  }
}
