//
//  SwiftUITextExtractor.swift
//  MixpanelSessionReplay
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//
//  Best-effort text extraction for SwiftUI internals. SwiftUI does not expose
//  a public accessor for Text content: text is rendered via Core Graphics on
//  `SwiftUI.CGDrawingView` (iOS <=25) or `SwiftUI.CGDrawingLayer` (iOS 26+).
//  This extractor tries a chain of strategies and returns `nil` on failure,
//  never throws.
//
//  Extraction is skipped when the element is already masked — extractor is
//  only called for elements whose decision remains `.none`.
//

import Foundation
import ObjectiveC
import UIKit

final class SwiftUITextExtractor {
  static let shared = SwiftUITextExtractor()

  /// Ivar names that on some iOS versions carry SwiftUI Text content.
  /// Ordered by likelihood; first hit wins.
  private static let textIvarAllowlist = [
    "_text", "text",
    "_string", "string",
    "_attributedString", "attributedString",
    "_content", "content",
    "_textContent", "textContent",
  ]

  private init() {}

  /// Extract text from a `SwiftUI.CGDrawingView` (UIView).
  /// Returns `nil` if no strategy succeeded or the extracted text is empty.
  ///
  /// Not cached: SwiftUI can reuse a `CGDrawingView` instance across text
  /// updates, and stale text would defeat the point of the wireframe.
  func extractText(from view: UIView) -> String? {
    if let label = accessibilityText(from: view) { return label }
    if let ivarText = ivarText(from: view) { return ivarText }
    if let mirrorText = mirrorText(from: view) { return mirrorText }
    return nil
  }

  /// Extract text from a SwiftUI text-rendering `CALayer` (iOS 26+
  /// `CGDrawingLayer`). Uses the same strategy chain minus the SwiftUI View
  /// accessibility fallback.
  func extractText(from layer: CALayer) -> String? {
    if let ivarText = ivarText(from: layer) { return ivarText }
    if let mirrorText = mirrorText(from: layer) { return mirrorText }
    if let delegate = layer.delegate as? NSObject,
      let label = delegate.accessibilityLabel, !label.isEmpty
    {
      return label
    }
    return nil
  }

  // MARK: - Strategies

  private func accessibilityText(from view: UIView) -> String? {
    if let label = view.accessibilityLabel, !label.isEmpty { return label }
    if let value = view.accessibilityValue, !value.isEmpty { return value }
    return nil
  }

  private func ivarText(from object: AnyObject) -> String? {
    var cls: AnyClass? = type(of: object)
    while let current = cls {
      var count: UInt32 = 0
      guard let ivarList = class_copyIvarList(current, &count) else {
        cls = class_getSuperclass(current)
        continue
      }
      defer { free(ivarList) }

      for i in 0..<Int(count) {
        let ivar = ivarList[i]
        guard let cNamePtr = ivar_getName(ivar) else { continue }
        let name = String(cString: cNamePtr)
        guard SwiftUITextExtractor.textIvarAllowlist.contains(name) else { continue }
        if let text = readStringIvar(from: object, ivar: ivar) {
          return text
        }
      }
      cls = class_getSuperclass(current)
    }
    return nil
  }

  private func readStringIvar(from object: AnyObject, ivar: Ivar) -> String? {
    let raw = object_getIvar(object, ivar)
    if let string = raw as? String, !string.isEmpty { return string }
    if let attributed = raw as? NSAttributedString {
      let string = attributed.string
      if !string.isEmpty { return string }
    }
    return nil
  }

  private func mirrorText(from object: AnyObject) -> String? {
    for child in Mirror(reflecting: object).children {
      guard let label = child.label,
        SwiftUITextExtractor.textIvarAllowlist.contains(label)
          || SwiftUITextExtractor.textIvarAllowlist.contains("_" + label)
      else { continue }
      if let string = child.value as? String, !string.isEmpty { return string }
      if let attributed = child.value as? NSAttributedString {
        let string = attributed.string
        if !string.isEmpty { return string }
      }
    }
    return nil
  }
}
