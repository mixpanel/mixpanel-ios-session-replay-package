//
//  SwiftUIExtractionLabTests.swift
//  MixpanelSessionReplayTests
//
//  Runs candidate text-extraction strategies against a real
//  UIHostingController + SwiftUI subtree and dumps what each recovered.
//  Not a pass/fail test — always XCTFails so the dump surfaces in test
//  output. Delete once we've chosen a strategy.
//

import ObjectiveC
import SwiftUI
import UIKit
import XCTest

@testable import MixpanelSessionReplay

@available(iOS 14.0, *)
final class SwiftUIExtractionLabTests: XCTestCase {

  /// Strings that ProbeContent renders and that the SDK is *supposed* to
  /// wireframe. Excludes TextField text (inputs are always masked by design).
  static let expected = ["Welcome", "Continue", "Sign in", "star"]

  /// Diagnostic — always XCTFails to surface its dump. Skipped by default so
  /// CI stays green; run manually (comment out the skip) when investigating
  /// a new iOS version or evaluating a new extraction strategy.
  func test_runAllStrategies_dumpFindings() throws {
    try XCTSkipIf(true, "Diagnostic — un-skip to gather a fresh dump against real SwiftUI.")

    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    let host = UIHostingController(rootView: ProbeContent())
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.frame = window.bounds
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    // Give SwiftUI several run-loop ticks to complete the render pass. On a
    // fresh window created from XCTest, one tick isn't enough.
    for _ in 0..<10 {
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    host.view.layoutIfNeeded()

    var lines: [String] = []
    lines.append("iOS \(UIDevice.current.systemVersion)")
    lines.append("Expected: \(Self.expected)")
    lines.append("")

    // Topology dump so we can tell whether SwiftUI actually rendered.
    lines.append("--- view tree ---")
    dumpTopology(host.view, depth: 0, out: &lines)
    lines.append("")

    // Raw Mirror children of the hosting view (depth 2 only, no filter).
    // Tells us whether _rootView is reachable and what type it's exposed as.
    lines.append("--- Mirror(hostView).children ---")
    dumpMirrorChildren(host.view, path: "hostView", depth: 0, maxDepth: 3, out: &lines)
    lines.append("")

    // Also: dump host.view.accessibilityElements explicitly.
    lines.append("--- accessibility ---")
    lines.append("hostView.accessibilityElements = \(String(describing: host.view.accessibilityElements))")
    lines.append("hostView.isAccessibilityElement = \(host.view.isAccessibilityElement)")
    for (i, sub) in host.view.subviews.enumerated() {
      lines.append("subview[\(i)] \(type(of: sub)) a11yElements=\(String(describing: sub.accessibilityElements)) isA11yElement=\(sub.isAccessibilityElement) label=\(String(describing: sub.accessibilityLabel))")
    }
    lines.append("")

    let strategies: [(String, String, (UIView, UIViewController) -> [String])] = [
      ("A", "accessibility walk (public UIKit)", { root, _ in accessibilityWalk(root) }),
      ("B", "Mirror from hostView (_rootView)", { _, host in rootViewMirror(host) }),
      ("C", "Mirror on CGDrawingView/Layer only", { root, _ in leafIvarMirror(root) }),
      ("D", "Mirror every subview + sublayer", { root, _ in allSubtreeMirror(root) }),
    ]
    for (id, name, fn) in strategies {
      let found = fn(host.view, host).sorted().removingDuplicates()
      let hits = Set(found.map { $0.lowercased() })
      let expected = Set(Self.expected.map { $0.lowercased() })
      let matched = expected.intersection(hits).count
      lines.append("[\(id)] \(name)  matched=\(matched)/\(Self.expected.count) total=\(found.count)")
      for s in found.prefix(30) {
        let star = expected.contains(s.lowercased()) ? "★" : " "
        lines.append("    \(star) \(s)")
      }
      if found.count > 30 { lines.append("    … \(found.count - 30) more") }
      lines.append("")
    }

    XCTFail("Extraction lab dump — delete this test once a strategy is chosen:\n" + lines.joined(separator: "\n"))
  }
}

// MARK: - Probe subject

@available(iOS 14.0, *)
private struct ProbeContent: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Welcome").font(.title2).bold()
      Button("Continue") {}
      Button("Sign in") {}
      TextField("email", text: .constant("email@example.com"))
      Image(systemName: "star.fill").accessibilityLabel("star")
    }
  }
}

// MARK: - Strategies

private func accessibilityWalk(_ root: UIView) -> [String] {
  var out: [String] = []
  func visitView(_ v: UIView) {
    if let s = v.accessibilityLabel, !s.isEmpty { out.append(s) }
    if let s = v.accessibilityValue, !s.isEmpty { out.append(s) }
    if let elements = v.accessibilityElements as? [NSObject] {
      for e in elements {
        if let s = (e.value(forKey: "accessibilityLabel") as? String), !s.isEmpty { out.append(s) }
        if let s = (e.value(forKey: "accessibilityValue") as? String), !s.isEmpty { out.append(s) }
      }
    }
    visitLayer(v.layer)
    for sub in v.subviews { visitView(sub) }
  }
  func visitLayer(_ layer: CALayer) {
    if let d = layer.delegate as? NSObject, let s = d.accessibilityLabel, !s.isEmpty {
      out.append(s)
    }
    for sub in layer.sublayers ?? [] { visitLayer(sub) }
  }
  visitView(root)
  return out.filter(isPlausible)
}

private func rootViewMirror(_ host: UIViewController) -> [String] {
  var out: [String] = []
  let hostView: UIView = host.view
  collectStrings(hostView, depth: 0, maxDepth: 12, out: &out)
  return out.filter(isPlausible)
}

private func leafIvarMirror(_ root: UIView) -> [String] {
  var out: [String] = []
  let drawViewCls: AnyClass? = NSClassFromString("SwiftUI.CGDrawingView")
  func visitView(_ v: UIView) {
    if let cls = drawViewCls, type(of: v) == cls {
      collectStrings(v, depth: 0, maxDepth: 8, out: &out)
      collectFromIvars(v, out: &out)
    }
    for sub in v.subviews { visitView(sub) }
    for layer in v.layer.sublayers ?? [] { visitLayer(layer) }
  }
  func visitLayer(_ layer: CALayer) {
    let cls = String(describing: type(of: layer))
    if cls.contains("CGDrawingLayer") {
      collectStrings(layer, depth: 0, maxDepth: 8, out: &out)
      collectFromIvars(layer, out: &out)
    }
    for sub in layer.sublayers ?? [] { visitLayer(sub) }
  }
  visitView(root)
  return out.filter(isPlausible)
}

private func allSubtreeMirror(_ root: UIView) -> [String] {
  var out: [String] = []
  func visitView(_ v: UIView) {
    collectStrings(v, depth: 0, maxDepth: 4, out: &out)
    for sub in v.subviews { visitView(sub) }
    for layer in v.layer.sublayers ?? [] { visitLayer(layer) }
  }
  func visitLayer(_ layer: CALayer) {
    collectStrings(layer, depth: 0, maxDepth: 4, out: &out)
    for sub in layer.sublayers ?? [] { visitLayer(sub) }
  }
  visitView(root)
  return out.filter(isPlausible)
}

// MARK: - Reflection helpers

private func collectStrings(_ value: Any, depth: Int, maxDepth: Int, out: inout [String]) {
  guard depth <= maxDepth else { return }
  if let s = value as? String, !s.isEmpty { out.append(s); return }
  if let a = value as? NSAttributedString, !a.string.isEmpty { out.append(a.string); return }
  for child in Mirror(reflecting: value).children {
    collectStrings(child.value, depth: depth + 1, maxDepth: maxDepth, out: &out)
  }
}

private func collectFromIvars(_ obj: AnyObject, out: inout [String]) {
  var cls: AnyClass? = type(of: obj)
  while let c = cls {
    var count: UInt32 = 0
    if let list = class_copyIvarList(c, &count) {
      defer { free(list) }
      for i in 0..<Int(count) {
        let ivar = list[i]
        guard let encPtr = ivar_getTypeEncoding(ivar) else { continue }
        let enc = String(cString: encPtr)
        guard enc.hasPrefix("@") else { continue }
        if let val = object_getIvar(obj, ivar) {
          collectStrings(val, depth: 0, maxDepth: 6, out: &out)
        }
      }
    }
    cls = class_getSuperclass(c)
  }
}

private func isPlausible(_ s: String) -> Bool {
  guard !s.isEmpty, s.count <= 400 else { return false }
  return true
}

private func dumpTopology(_ v: UIView, depth: Int, out: inout [String]) {
  let indent = String(repeating: "  ", count: depth)
  let cls = String(describing: type(of: v))
  out.append("\(indent)V \(cls) frame=\(v.frame) a11yLabel=\(v.accessibilityLabel ?? "-") a11yValue=\(v.accessibilityValue ?? "-")")
  for sub in v.subviews { dumpTopology(sub, depth: depth + 1, out: &out) }
  for l in v.layer.sublayers ?? [] { dumpLayerTopology(l, depth: depth + 1, out: &out) }
}

private func dumpLayerTopology(_ l: CALayer, depth: Int, out: inout [String]) {
  let indent = String(repeating: "  ", count: depth)
  let cls = String(describing: type(of: l))
  out.append("\(indent)L \(cls) frame=\(l.frame)")
  for sub in l.sublayers ?? [] { dumpLayerTopology(sub, depth: depth + 1, out: &out) }
}

private func dumpMirrorChildren(
  _ value: Any, path: String, depth: Int, maxDepth: Int, out: inout [String]
) {
  guard depth <= maxDepth else { return }
  let mirror = Mirror(reflecting: value)
  let ind = String(repeating: "  ", count: depth)
  for child in mirror.children {
    let label = child.label ?? "?"
    let desc = String(describing: child.value).prefix(120)
    out.append("\(ind)\(path).\(label): \(type(of: child.value)) = \(desc)")
    // Only recurse into things likely to hold text — heuristic.
    let typeName = String(describing: type(of: child.value))
    if typeName.contains("Text") || typeName.contains("String") || typeName.contains("Storage")
      || typeName.contains("Optional") || typeName.contains("_rootView") || label == "_rootView"
    {
      dumpMirrorChildren(child.value, path: "\(path).\(label)", depth: depth + 1, maxDepth: maxDepth, out: &out)
    }
  }
}

private extension Array where Element: Hashable {
  func removingDuplicates() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}
