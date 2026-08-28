//
//  ExtractionLabScreen.swift
//  SampleApp
//
//  Empirical survey of text-extraction strategies against real SwiftUI
//  content. Renders a fixed sample SwiftUI subtree via UIHostingController,
//  then runs every candidate strategy over it and shows what each recovered.
//  Use the OS badge + strategy grid to see, per iOS release, which paths
//  actually reach the rendered text.
//

import ObjectiveC
import SwiftUI
import UIKit

struct ExtractionLabScreen: View {
    enum Target: String, CaseIterable, Identifiable {
        case synthetic
        case liveKeyWindow
        case liveKeyWindowAfterA11yPost
        var id: String { rawValue }
        var name: String {
            switch self {
                case .synthetic: return "Synthetic UIHostingController"
                case .liveKeyWindow: return "Live key window (visible app)"
                case .liveKeyWindowAfterA11yPost: return "Live key window + force a11y refresh"
            }
        }
    }

    @State private var findings: [Strategy: [Finding]] = [:]
    @State private var expected: [String] = []
    @State private var pass: Int = 0
    @State private var target: Target = .liveKeyWindow

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Target: \(target.name)").font(.footnote).foregroundColor(.secondary)
                    Text("Expected strings on screen:")
                        .font(.headline)
                    ForEach(expected, id: \.self) { s in
                        Text("• \(s)")
                            .font(.system(.footnote, design: .monospaced))
                    }
                    Divider()
                    ForEach(Strategy.allCases) { strat in
                        resultBlock(strat)
                    }
                }
                .padding()
            }
            Divider()
            ProbeSubject()
                .frame(height: 220)
                .background(Color(uiColor: .secondarySystemBackground))
        }
        .navigationTitle("Extraction Lab")
    }

    private var controls: some View {
        VStack(spacing: 6) {
            Picker("Target", selection: $target) {
                ForEach(Target.allCases) { t in
                    Text(t.name).tag(t)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                Button("Run all strategies") { run() }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Text("iOS \(UIDevice.current.systemVersion)")
                    .font(.caption).foregroundColor(.secondary)
                Text("pass #\(pass)")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(8)
    }

    private func resultBlock(_ strategy: Strategy) -> some View {
        let hits = findings[strategy] ?? []
        let expectedSet = Set(expected.map { $0.lowercased() })
        let matched = hits.filter { expectedSet.contains($0.text.lowercased()) }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(strategy.name).font(.headline)
                Spacer()
                Text("\(matched.count)/\(expected.count) expected · \(hits.count) total")
                    .font(.caption)
                    .foregroundColor(matched.count == expected.count ? .green : (matched.isEmpty ? .red : .orange))
            }
            Text(strategy.detail).font(.caption).foregroundColor(.secondary)
            if hits.isEmpty {
                Text("(no hits)").font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
            } else {
                ForEach(hits.prefix(20)) { f in
                    Text("\(f.source): \(f.text)")
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .foregroundColor(expectedSet.contains(f.text.lowercased()) ? .green : .primary)
                }
                if hits.count > 20 {
                    Text("… \(hits.count - 20) more").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(uiColor: .tertiarySystemBackground))
        .cornerRadius(6)
    }

    // MARK: - Run

    private func run() {
        // Different targets test different environmental assumptions:
        //  - synthetic: an ad-hoc UIHostingController in a bare UIWindow (no scene)
        //  - liveKeyWindow: the actual app's key window as iOS is compositing it
        //  - liveKeyWindowAfterA11yPost: same, but post .screenChanged first to
        //    see if iOS lazy-builds the a11y tree on notification
        let rootView: UIView?
        let host: UIViewController?

        switch target {
            case .synthetic:
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
                let h = UIHostingController(rootView: ProbeContent())
                window.rootViewController = h
                window.isHidden = false
                h.view.frame = window.bounds
                h.view.setNeedsLayout()
                h.view.layoutIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.15))
                rootView = h.view
                host = h
                self.expected = ["Welcome", "Continue", "Sign in", "star"]

            case .liveKeyWindow, .liveKeyWindowAfterA11yPost:
                let win = liveKeyWindow()
                rootView = win
                host = win?.rootViewController
                // What's on screen: the ProbeSubject at the bottom of THIS view plus
                // the tab bar and console overlay. Expected reflects the ProbeSubject.
                self.expected = ["Welcome", "Continue", "Sign in", "star"]
                if target == .liveKeyWindowAfterA11yPost, let win = win {
                    UIAccessibility.post(notification: .screenChanged, argument: win)
                    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
                }
        }

        guard let rootView = rootView, let host = host else {
            self.findings = [:]
            return
        }
        var out: [Strategy: [Finding]] = [:]
        for s in Strategy.allCases {
            out[s] = s.run(rootView: rootView, host: host)
        }
        self.findings = out
        self.pass += 1
    }
}

private func liveKeyWindow() -> UIWindow? {
    for scene in UIApplication.shared.connectedScenes {
        guard let ws = scene as? UIWindowScene else { continue }
        if let key = ws.windows.first(where: { $0.isKeyWindow }) { return key }
        if let first = ws.windows.first { return first }
    }
    return nil
}

// MARK: - Probe subject shown on screen

private struct ProbeSubject: View {
    var body: some View {
        ProbeContent()
            .padding()
    }
}

private struct ProbeContent: View {
    @State private var email = "email@example.com"
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome").font(.title2).bold()
            Button("Continue") {}
            Button("Sign in") {}
            TextField("email", text: .constant(email))
            Image(systemName: "star.fill").accessibilityLabel("star")
        }
    }
}

// MARK: - Strategy plumbing

private struct Finding: Identifiable {
    let id = UUID()
    let text: String
    let source: String
}

private enum Strategy: String, CaseIterable, Identifiable {
    case accessibilityWalk
    case rootViewMirror
    case leafIvarMirror
    case allLayerMirror

    var id: String { rawValue }

    var name: String {
        switch self {
            case .accessibilityWalk: return "A. Accessibility walk"
            case .rootViewMirror: return "B. Mirror from _rootView"
            case .leafIvarMirror: return "C. Deep Mirror on leaf CGDrawingView/Layer"
            case .allLayerMirror: return "D. Mirror on every subview/sublayer"
        }
    }

    var detail: String {
        switch self {
            case .accessibilityWalk:
                return
                    "Walks accessibilityElements / accessibilityLabel / accessibilityValue on every subview and CALayer. Public UIKit."
            case .rootViewMirror:
                return
                    "Mirror-recurses into _UIHostingView.mirror(\"_rootView\") — where SwiftUI's value tree lives — collecting String / LocalizedStringKey / verbatim leaves."
            case .leafIvarMirror:
                return
                    "Deep Mirror + ObjC ivar walk on CGDrawingView (iOS ≤18) and CGDrawingLayer (iOS 26+) — the current SDK strategy, plus recursion into value-typed fields."
            case .allLayerMirror:
                return
                    "Mirror every UIView + every CALayer under the hosting view, up to depth 4, collecting String/AttributedString leaves."
        }
    }

    func run(rootView: UIView, host: UIViewController) -> [Finding] {
        switch self {
            case .accessibilityWalk: return runAccessibilityWalk(rootView)
            case .rootViewMirror: return runRootViewMirror(host)
            case .leafIvarMirror: return runLeafIvarMirror(rootView)
            case .allLayerMirror: return runAllLayerMirror(rootView)
        }
    }
}

// MARK: - A: Accessibility walk

private func runAccessibilityWalk(_ root: UIView) -> [Finding] {
    var out: [Finding] = []
    func visitView(_ v: UIView, path: String) {
        let cls = String(describing: type(of: v))
        if let s = v.accessibilityLabel, !s.isEmpty {
            out.append(.init(text: s, source: "\(path)/\(cls).a11yLabel"))
        }
        if let s = v.accessibilityValue, !s.isEmpty {
            out.append(.init(text: s, source: "\(path)/\(cls).a11yValue"))
        }
        if let elements = v.accessibilityElements as? [NSObject] {
            for (i, e) in elements.enumerated() {
                if let s = (e.value(forKey: "accessibilityLabel") as? String), !s.isEmpty {
                    out.append(.init(text: s, source: "\(path)/\(cls).accessibilityElements[\(i)].a11yLabel"))
                }
                if let s = (e.value(forKey: "accessibilityValue") as? String), !s.isEmpty {
                    out.append(.init(text: s, source: "\(path)/\(cls).accessibilityElements[\(i)].a11yValue"))
                }
            }
        }
        visitLayer(v.layer, path: "\(path)/\(cls)")
        for sub in v.subviews { visitView(sub, path: "\(path)/\(cls)") }
    }
    func visitLayer(_ layer: CALayer, path: String) {
        if let d = layer.delegate as? NSObject,
            let s = d.accessibilityLabel, !s.isEmpty
        {
            out.append(.init(text: s, source: "\(path)/layer.delegate.a11yLabel"))
        }
        for sub in layer.sublayers ?? [] {
            visitLayer(sub, path: "\(path)/sublayer")
        }
    }
    visitView(root, path: "")
    return dedupe(out)
}

// MARK: - B: Mirror from _rootView on the hosting view

private func runRootViewMirror(_ host: UIViewController) -> [Finding] {
    var out: [Finding] = []
    // The host is UIHostingController<ProbeContent>. Its view is _UIHostingView<ProbeContent>.
    // _rootView is a stored Swift property Mirror can see.
    mirrorFindStrings(host.view, path: "hostView", depth: 0, maxDepth: 8, out: &out)
    return dedupe(out)
}

// MARK: - C: Deep Mirror on leaf CGDrawingView / CGDrawingLayer

private func runLeafIvarMirror(_ root: UIView) -> [Finding] {
    var out: [Finding] = []
    let drawViewName = "SwiftUI.CGDrawingView"
    let drawViewCls: AnyClass? = NSClassFromString(drawViewName)
    func visitView(_ v: UIView) {
        if let cls = drawViewCls, type(of: v) == cls {
            mirrorFindStrings(v, path: "CGDrawingView", depth: 0, maxDepth: 6, out: &out)
            dumpIvarObjects(v, path: "CGDrawingView.ivar", out: &out)
        }
        for sub in v.subviews { visitView(sub) }
        for layer in v.layer.sublayers ?? [] { visitLayer(layer) }
    }
    func visitLayer(_ layer: CALayer) {
        let cls = String(describing: type(of: layer))
        if cls.contains("CGDrawingLayer") {
            mirrorFindStrings(layer, path: "CGDrawingLayer", depth: 0, maxDepth: 6, out: &out)
            dumpIvarObjects(layer, path: "CGDrawingLayer.ivar", out: &out)
        }
        for sub in layer.sublayers ?? [] { visitLayer(sub) }
    }
    visitView(root)
    return dedupe(out)
}

// MARK: - D: Mirror every subview/sublayer

private func runAllLayerMirror(_ root: UIView) -> [Finding] {
    var out: [Finding] = []
    func visitView(_ v: UIView, depth: Int) {
        let cls = String(describing: type(of: v))
        mirrorFindStrings(v, path: "V:\(cls)", depth: 0, maxDepth: 4, out: &out)
        for sub in v.subviews { visitView(sub, depth: depth + 1) }
        for layer in v.layer.sublayers ?? [] { visitLayer(layer, depth: depth + 1) }
    }
    func visitLayer(_ layer: CALayer, depth: Int) {
        let cls = String(describing: type(of: layer))
        mirrorFindStrings(layer, path: "L:\(cls)", depth: 0, maxDepth: 4, out: &out)
        for sub in layer.sublayers ?? [] { visitLayer(sub, depth: depth + 1) }
    }
    visitView(root, depth: 0)
    return dedupe(out)
}

// MARK: - shared helpers

/// Recursively walks Mirror children up to maxDepth, collecting String and
/// NSAttributedString leaves. Also unwraps common containers (Optional,
/// arrays, tuples) so we don't miss nested payloads.
private func mirrorFindStrings(
    _ value: Any, path: String, depth: Int, maxDepth: Int, out: inout [Finding]
) {
    guard depth <= maxDepth else { return }
    if let s = value as? String, !s.isEmpty, isPlausibleText(s) {
        out.append(.init(text: s, source: path))
        return
    }
    if let a = value as? NSAttributedString, !a.string.isEmpty, isPlausibleText(a.string) {
        out.append(.init(text: a.string, source: "\(path)(NSAttributedString)"))
        return
    }
    let mirror = Mirror(reflecting: value)
    for child in mirror.children {
        let label = child.label ?? "?"
        mirrorFindStrings(
            child.value, path: "\(path).\(label)",
            depth: depth + 1, maxDepth: maxDepth, out: &out)
    }
}

/// For a given object, iterates its Objective-C ivars and for each one that
/// holds an object (`@` encoding), Mirror-descends into the value.
private func dumpIvarObjects(_ obj: AnyObject, path: String, out: inout [Finding]) {
    var cls: AnyClass? = type(of: obj)
    while let c = cls {
        var count: UInt32 = 0
        if let list = class_copyIvarList(c, &count) {
            defer { free(list) }
            for i in 0..<Int(count) {
                let ivar = list[i]
                guard let namePtr = ivar_getName(ivar) else { continue }
                let name = String(cString: namePtr)
                guard let encPtr = ivar_getTypeEncoding(ivar) else { continue }
                let enc = String(cString: encPtr)
                guard enc.hasPrefix("@") else { continue }
                if let val = object_getIvar(obj, ivar) {
                    mirrorFindStrings(val, path: "\(path).\(name)", depth: 0, maxDepth: 4, out: &out)
                }
            }
        }
        cls = class_getSuperclass(c)
    }
}

/// Filters out noisy Mirror hits that aren't user-visible text (SF Symbol
/// system names, hex color strings, huge blobs, etc.). Conservative.
private func isPlausibleText(_ s: String) -> Bool {
    if s.count > 400 { return false }
    if s.hasPrefix("#") { return false }
    if s.hasPrefix("<") { return false }
    if s.contains("0x") { return false }
    return true
}

private func dedupe(_ arr: [Finding]) -> [Finding] {
    var seen = Set<String>()
    return arr.filter { seen.insert("\($0.source)|\($0.text)").inserted }
}
