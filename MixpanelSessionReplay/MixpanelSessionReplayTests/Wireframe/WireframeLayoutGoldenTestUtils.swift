//
//  WireframeLayoutGoldenTestUtils.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//
//  Device-keyed golden harness for wireframes laid out by *real* UIKit layout.
//
//  This is the counterpart to `WireframeGoldenTestUtils`, and the difference is
//  the whole point. Those goldens build their trees with hardcoded frames, which
//  makes them OS-independent but means coordinates are an *input* — nothing
//  verifies that a `UILabel` sized by its intrinsic content actually lands where
//  the wireframe claims. Here the frames come out of Auto Layout and real text
//  measurement, so coordinates are an *output* and the golden is a genuine
//  regression guard on capture fidelity. It is the same thing Android gained by
//  moving its goldens onto layoutlib (`:session-replay:wireframe-goldens`) and
//  Flutter has from pumping a real widget tree.
//
//  Because the numbers now depend on the rendering environment, goldens are
//  filed per simulator under `Golden/Layout/<device key>/`. The key is derived
//  from what actually determines the output — OS version, logical screen size
//  and scale — rather than the marketing name, so two simulators that agree on
//  those legitimately share a file and a new destination that differs shows up
//  as a new directory rather than a mystery diff.
//
//  Determinism notes:
//   - Views use explicit `UIFont.systemFont(ofSize:)`, never `preferredFont`, so
//     the goldens do not move with the Dynamic Type setting of whoever runs them.
//   - The window is sized from `UIScreen.main.bounds`, so the viewport recorded
//     in the golden is the simulator's own geometry.
//   - Layout is forced synchronously (`layoutIfNeeded`) before the walk; nothing
//     depends on a run-loop turn.
//

import CoreGraphics
import UIKit
import XCTest

@testable import MixpanelSessionReplay

/// Identifies the rendering environment a layout golden was recorded on, e.g.
/// `iOS26.2-402x874@3x`. Derived from the properties that actually change the
/// numbers rather than the device's marketing name.
func wireframeDeviceKey() -> String {
    let screen = UIScreen.main
    let size = screen.bounds.size
    let scale = screen.scale
    let version = UIDevice.current.systemVersion
    let scaleText = scale == scale.rounded() ? String(Int(scale)) : String(format: "%.1f", scale)
    return "iOS\(version)-\(Int(size.width))x\(Int(size.height))@\(scaleText)x"
}

/// Directory holding the checked-in layout goldens for the current device key.
private func wireframeLayoutGoldenDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Golden")
        .appendingPathComponent("Layout")
        .appendingPathComponent(wireframeDeviceKey())
}

/// A real `UIWindow` sized to the simulator's screen, with `root` installed and
/// laid out. Returns both so the caller can walk `root` against `window`.
///
/// The window is made key and visible because an off-window view hierarchy does
/// not get a real layout pass, which is exactly what these goldens are for.
func makeLayoutWindow(_ root: UIView) -> (window: UIWindow, root: UIView) {
    let window = UIWindow(frame: UIScreen.main.bounds)
    let controller = UIViewController()
    controller.view.backgroundColor = .white
    controller.view.addSubview(root)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    window.setNeedsLayout()
    window.layoutIfNeeded()
    root.setNeedsLayout()
    root.layoutIfNeeded()
    return (window, root)
}

/// Runs the production pipeline over a really-laid-out tree and asserts the
/// serialized result against the device-keyed golden, creating it on first run.
///
/// Mirrors `assertWireframeGolden(manager:root:window:...)` exactly, including
/// the JSON format, so a layout golden and a fixed-frame golden for the same
/// scenario are directly comparable.
func assertWireframeLayoutGolden(
    manager: SensitiveViewManager,
    root: UIView,
    window: UIView,
    rules: [MPSensitiveRule] = [],
    useAccessibilityLabelFallback: Bool = true,
    golden name: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    manager.useAccessibilityLabelFallback = useAccessibilityLabelFallback
    let (frames, elements) = manager.collectFramesAndWireframes(in: root, window: window)
    let emitter = WireframeEmitter(
        options: MPWireframesOptions(
            sensitiveRules: rules,
            useAccessibilityLabelFallback: useAccessibilityLabelFallback))
    let processed = emitter.processedElementsForTesting(
        elements: elements, maskBounds: Set(frames.keys))
    let viewport = [Int(window.bounds.width), Int(window.bounds.height)]
    assertWireframeLayoutGolden(
        processed, viewport: viewport, golden: name, file: file, line: line)
}

/// Asserts a pre-collected element list against the device-keyed layout golden.
func assertWireframeLayoutGolden(
    _ processed: [WireframeElement],
    viewport: [Int],
    golden name: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let actual = wireframeGoldenJSON(viewport: viewport, elements: processed)
    let directory = wireframeLayoutGoldenDirectory()
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: directory.path) {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let url = directory.appendingPathComponent(name)

    guard let expected = try? String(contentsOf: url, encoding: .utf8) else {
        do {
            try actual.write(to: url, atomically: true, encoding: .utf8)
            print("📸 Created wireframe layout golden: \(wireframeDeviceKey())/\(name)")
        } catch {
            XCTFail(
                "Failed to create wireframe layout golden \(name): \(error)", file: file, line: line)
        }
        return
    }

    XCTAssertEqual(
        actual,
        expected,
        """
        Wireframe layout golden mismatch for \(wireframeDeviceKey())/\(name).
        Delete MixpanelSessionReplayTests/Wireframe/Golden/Layout/\(wireframeDeviceKey())/\(name) \
        to regenerate. If this destination has no goldens yet, running the suite records them.
        """,
        file: file,
        line: line
    )
}
