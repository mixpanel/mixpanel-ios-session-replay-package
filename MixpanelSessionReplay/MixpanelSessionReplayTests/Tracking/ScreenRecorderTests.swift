//
//  ScreenRecorderTests.swift
//  MixpanelSessionReplay
//
//  Created by Ketan on 04/03/25.
//  Copyright © 2025 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

class ScreenRecorderTests: XCTestCase {
    var recorder: ScreenRecorder!
    var mockWindow: UIWindow!

    override func setUp() {
        super.setUp()
        recorder = ScreenRecorder.shared
        mockWindow = UIWindow(frame: UIScreen.main.bounds)
    }

    override func tearDown() {
        recorder.captureMethod = .viewHierarchy
        recorder = nil
        mockWindow = nil
        super.tearDown()
    }

    // MARK: - getRendererForSize

    func testGetScreenRendererForSize_CreatesNewRendererWhenSizeChanges() {
        let size1 = CGSize(width: 100, height: 100)
        let size2 = CGSize(width: 200, height: 200)

        let renderer1 = recorder.getRenderer(isPresented: false, size: size1)
        let renderer2 = recorder.getRenderer(isPresented: false, size: size1)

        XCTAssertTrue(renderer1 === renderer2, "Renderer should not be recreated if size is the same")

        let renderer3 = recorder.getRenderer(isPresented: false, size: size2)
        XCTAssertFalse(renderer1 === renderer3, "Renderer should be recreated if size changes")
    }

    func testGetModalRendererForSize_CreatesNewRendererWhenSizeChanges() {
        let size1 = CGSize(width: 100, height: 100)
        let size2 = CGSize(width: 200, height: 200)

        let renderer1 = recorder.getRenderer(isPresented: true, size: size1)
        let renderer2 = recorder.getRenderer(isPresented: true, size: size1)

        XCTAssertTrue(
            renderer1 === renderer2, "Modal renderer should not be recreated if size is the same")

        let renderer3 = recorder.getRenderer(isPresented: true, size: size2)
        XCTAssertFalse(
            renderer1 === renderer3, "Modal renderer should be recreated if size changes")
    }

    func testGetModalRendererForSize_ReturnsModalRenderer() {
        let size = CGSize(width: 100, height: 100)

        // Get the modal renderer
        let modalRenderer = recorder.getRenderer(isPresented: true, size: size)
        XCTAssertNotNil(modalRenderer, "Modal renderer should be created")
    }

    func testGetScreenRendererForSize_UsesOpaqueFormat() {
        let size = CGSize(width: 100, height: 100)

        // Get the screen renderer (should use opaque format)
        let screenRenderer = recorder.getRenderer(isPresented: false, size: size)
        XCTAssertNotNil(screenRenderer, "Screen renderer should be created")
    }

    // MARK: - getViewFromUIViewController

    func testGetViewFromUIViewController_ReturnsSuperviewIfAvailable() {
        let parentView = UIView()
        let childVC = UIViewController()
        let childView = UIView()

        parentView.addSubview(childView)
        childVC.view = childView

        XCTAssertEqual(
            recorder.getViewFromUIViewController(vc: childVC), childView.superview,
            "Should return superview if available")
    }

    func testGetViewFromUIViewController_ReturnsViewIfSuperviewIsNil() {
        let vc = UIViewController()
        let view = UIView()
        vc.view = view

        XCTAssertEqual(
            recorder.getViewFromUIViewController(vc: vc), view, "Should return view if superview is nil")
    }

    // MARK: - getTopViewFor

    func testGetTopViewFor_UsesTabBarControllerIfNotPresented() {
        let tabBarController = UITabBarController()
        let expectedView = UIView()
        tabBarController.view = expectedView

        let result = recorder.getTopViewFor(
            viewController: tabBarController, isPresented: false, window: mockWindow)
        XCTAssertEqual(result, expectedView, "Should return tab bar controller's view")
    }

    func testGetTopViewFor_UsesNavigationControllerIfNotPresented() {
        let navController = UINavigationController()
        let expectedView = UIView()
        navController.view = expectedView

        let result = recorder.getTopViewFor(
            viewController: navController, isPresented: false, window: mockWindow)
        XCTAssertEqual(result, expectedView, "Should return navigation controller's view")
    }

    func testGetTopViewFor_UsesViewControllerIfPresented() {
        let viewController = UIViewController()
        let expectedView = UIView()
        viewController.view = expectedView

        let result = recorder.getTopViewFor(
            viewController: viewController, isPresented: true, window: mockWindow)
        XCTAssertEqual(result, expectedView, "Should return presented view controller's view")
    }

    func testGetTopViewFor_UsesWindowAsFallback() {
        let result = recorder.getTopViewFor(viewController: nil, isPresented: false, window: mockWindow)
        XCTAssertEqual(result, mockWindow, "Should return window as fallback if viewController is nil")
    }

    // MARK: - renderViewHierarchyAsImage

    func testRenderViewHierarchyAsImage_ReturnsNilForInvisibleView() {
        let window = UIWindow()
        let view = UIView()
        view.isHidden = true
        window.addSubview(view)

        let image = recorder.renderViewHierarchyAsImage(window: window)
        XCTAssertNil(image, "Should return nil if view is not visible")
    }

    func testRenderViewHierarchyAsImage_ReturnsImageIfViewIsVisible() {
        let window = UIWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.addSubview(view)
        window.isHidden = false
        let image = recorder.renderViewHierarchyAsImage(window: window)
        XCTAssertNotNil(image, "Should return an image if view is visible")
    }

    /// The layer-tree method draws the app's own content into the frame — a solid red
    /// root view here, sampled at the frame's center. (`drawHierarchy` needs the window
    /// to have been composited on screen, which a test window never is, so the view-
    /// hierarchy method is only checked for producing an image, above.)
    func testRenderViewHierarchyAsImage_LayerTreeRendersTheWindowContent() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
        let rootVC = UIViewController()
        rootVC.view.backgroundColor = .red
        window.rootViewController = rootVC
        window.isHidden = false
        window.layoutIfNeeded()
        recorder.captureMethod = .layerTree

        let frame = try XCTUnwrap(recorder.renderViewHierarchyAsImage(window: window))
        let center = CGPoint(x: frame.image.size.width / 2, y: frame.image.size.height / 2)
        let color = try XCTUnwrap(pixel(of: frame.image, at: center))

        XCTAssertEqual(color.red, 255, accuracy: 2, "should render the red root view")
        XCTAssertEqual(color.green, 0, accuracy: 2, "should render the red root view")
        XCTAssertEqual(color.blue, 0, accuracy: 2, "should render the red root view")
    }

    /// The layer-tree method must place the view where it sits in the window, not at the
    /// context's origin: a view drawn at a non-zero `viewBounds.origin` lands inside that
    /// rect, and the spot it would have covered without the translation stays untouched.
    func testDraw_LayerTreePlacesTheViewAtItsWindowPosition() throws {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        view.backgroundColor = .red
        view.layoutIfNeeded()
        let viewBounds = CGRect(x: 40, y: 60, width: 50, height: 50)
        recorder.captureMethod = .layerTree

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: 200, height: 300)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            recorder.draw(view, at: viewBounds, in: context.cgContext)
        }

        let inside = try XCTUnwrap(pixel(of: image, at: CGPoint(x: 65, y: 85)))
        XCTAssertEqual(inside.red, 255, accuracy: 2, "the view should be drawn inside viewBounds")
        XCTAssertEqual(inside.green, 0, accuracy: 2)
        XCTAssertEqual(inside.blue, 0, accuracy: 2)

        let untranslated = try XCTUnwrap(pixel(of: image, at: CGPoint(x: 25, y: 25)))
        XCTAssertEqual(untranslated.green, 255, accuracy: 2, "where the view would land without the translation")
        XCTAssertEqual(untranslated.blue, 255, accuracy: 2, "where the view would land without the translation")

        let outside = try XCTUnwrap(pixel(of: image, at: CGPoint(x: 150, y: 250)))
        XCTAssertEqual(outside.green, 255, accuracy: 2, "the rest of the frame stays untouched")
        XCTAssertEqual(outside.blue, 255, accuracy: 2, "the rest of the frame stays untouched")
    }

    /// A masked view caught in the middle of a Core Animation animation must be covered by
    /// its mask wherever the layer-tree render draws it: the mask and the pixels have to
    /// come from the same moment of the animation.
    func testRenderViewHierarchyAsImage_LayerTreeMasksAViewMidAnimation() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let rootVC = UIViewController()
        rootVC.view.backgroundColor = .white
        window.rootViewController = rootVC
        window.isHidden = false
        let secret = UIView(frame: CGRect(x: 0, y: 100, width: 60, height: 60))
        secret.backgroundColor = .red
        secret.mpReplaySensitive = true
        rootVC.view.addSubview(secret)
        window.layoutIfNeeded()
        recorder.captureMethod = .layerTree

        UIView.animate(withDuration: 20, delay: 0, options: [.curveLinear]) {
            secret.frame.origin.x = 240
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let presentationX = try XCTUnwrap(secret.layer.presentation()).frame.minX
        XCTAssertLessThan(presentationX, 60, "the animation should still be in flight")

        let frame = try XCTUnwrap(recorder.renderViewHierarchyAsImage(window: window))
        XCTAssertEqual(
            countPixels(of: frame.image) { $0.red > 200 && $0.green < 60 && $0.blue < 60 }, 0,
            "no part of the masked view may show outside its mask")
        // The frame shows the view where the screen does — mid-flight — not where the
        // animation will leave it.
        let onScreen = try XCTUnwrap(pixel(of: frame.image, at: CGPoint(x: presentationX + 30, y: 130)))
        XCTAssertEqual(onScreen.red, onScreen.blue, accuracy: 2, "the mask covers the view mid-flight")
        XCTAssertLessThan(onScreen.red, 240, "the mask covers the view mid-flight")
        let destination = try XCTUnwrap(pixel(of: frame.image, at: CGPoint(x: 270, y: 130)))
        XCTAssertEqual(destination.red, 255, accuracy: 2, "nothing is drawn where the view has not reached yet")
        XCTAssertEqual(destination.green, 255, accuracy: 2, "nothing is drawn where the view has not reached yet")
    }

    /// A picker is left out of the layer-tree render — `render(in:)` flattens its wheel —
    /// and drawn by snapshot instead: here, where the test window is never composited and
    /// the snapshot draws nothing, the page behind it shows. The live picker is untouched.
    func testRenderViewHierarchyAsImage_LayerTreeLeavesPickersToTheSnapshot() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        let rootVC = UIViewController()
        rootVC.view.backgroundColor = .white
        window.rootViewController = rootVC
        window.isHidden = false
        let picker = UIPickerView(frame: CGRect(x: 0, y: 100, width: 300, height: 216))
        picker.backgroundColor = .red
        rootVC.view.addSubview(picker)
        window.layoutIfNeeded()
        CATransaction.flush()
        recorder.captureMethod = .layerTree

        XCTAssertEqual(recorder.snapshottedViews(in: rootVC.view), [picker])
        let frame = try XCTUnwrap(recorder.renderViewHierarchyAsImage(window: window))
        let center = try XCTUnwrap(pixel(of: frame.image, at: CGPoint(x: 150, y: 208)))
        XCTAssertEqual(center.red, 255, accuracy: 2, "the page shows where the picker was left out")
        XCTAssertEqual(center.green, 255, accuracy: 2, "the page shows where the picker was left out")
        XCTAssertFalse(picker.layer.isHidden, "the live picker is never hidden")
        XCTAssertEqual(picker.layer.presentation()?.isHidden, false, "the presentation copy is restored")
    }

    /// Shadows are left out of the layer-tree render — `render(in:)` blurs them on the CPU —
    /// and the live layer keeps its shadow.
    func testRenderViewHierarchyAsImage_LayerTreeLeavesShadowsOut() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        let rootVC = UIViewController()
        rootVC.view.backgroundColor = .white
        window.rootViewController = rootVC
        window.isHidden = false
        let card = UIView(frame: CGRect(x: 50, y: 100, width: 200, height: 100))
        card.backgroundColor = .blue
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 1
        card.layer.shadowRadius = 4
        card.layer.shadowOffset = CGSize(width: 0, height: 30)
        rootVC.view.addSubview(card)
        window.layoutIfNeeded()
        CATransaction.flush()
        recorder.captureMethod = .layerTree

        let frame = try XCTUnwrap(recorder.renderViewHierarchyAsImage(window: window))
        let underCard = try XCTUnwrap(pixel(of: frame.image, at: CGPoint(x: 150, y: 215)))
        XCTAssertEqual(underCard.red, 255, accuracy: 2, "no shadow is drawn below the card")
        XCTAssertEqual(underCard.green, 255, accuracy: 2, "no shadow is drawn below the card")
        let onCard = try XCTUnwrap(pixel(of: frame.image, at: CGPoint(x: 150, y: 150)))
        XCTAssertEqual(onCard.blue, 255, accuracy: 2, "the card itself is drawn")
        XCTAssertEqual(card.layer.shadowOpacity, 1, "the live layer keeps its shadow")
        XCTAssertEqual(card.layer.presentation()?.shadowOpacity, 1, "the presentation copy is restored")
    }

    /// A picker caught mid-animation is snapshotted where the screen shows it — the
    /// presentation position, where its mask is measured — not where it will land.
    func testPickerSnapshots_PlaceAPickerWhereItIsMidAnimation() throws {
        let (window, root, picker) = makePickerWindow()
        UIView.animate(withDuration: 20, delay: 0, options: [.curveLinear]) {
            picker.frame.origin.x = 200
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let presentationX = try XCTUnwrap(picker.layer.presentation()).frame.minX
        XCTAssertLessThan(presentationX, 40, "the animation should still be in flight")

        let tree = try XCTUnwrap(root.layer.presentation())
        let snapshots = recorder.pickerSnapshots(in: root, tree: tree, at: window.bounds)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(try XCTUnwrap(snapshots.first).rect.minX, presentationX, accuracy: 1)
    }

    /// A picker that something drawn after it paints over is left to the layer-tree
    /// render: a snapshot drawn over the whole frame would cover that view.
    func testPickerSnapshots_LeaveCoveredPickersToTheRender() throws {
        let (window, root, picker) = makePickerWindow()
        let cover = UIView(frame: CGRect(x: 40, y: 150, width: 200, height: 80))
        cover.backgroundColor = .blue
        root.addSubview(cover)
        root.layoutIfNeeded()
        CATransaction.flush()
        let tree = try XCTUnwrap(root.layer.presentation())

        XCTAssertTrue(recorder.pickerSnapshots(in: root, tree: tree, at: window.bounds).isEmpty)

        cover.frame.origin.y = 330
        CATransaction.flush()
        let movedTree = try XCTUnwrap(root.layer.presentation())
        XCTAssertEqual(
            recorder.pickerSnapshots(in: root, tree: movedTree, at: window.bounds).map(\.view), [picker],
            "a view beside the picker does not cover it")
    }

    /// A transparent container laid over the picker — a SwiftUI host spanning the screen —
    /// draws nothing, so the picker is still snapshotted.
    func testPickerSnapshots_IgnoreTransparentContainersOverThePicker() throws {
        let (window, root, picker) = makePickerWindow()
        let container = UIView(frame: root.bounds)
        container.backgroundColor = .clear
        container.addSubview(UIView(frame: CGRect(x: 0, y: 360, width: 300, height: 40)))
        root.addSubview(container)
        root.layoutIfNeeded()
        CATransaction.flush()
        let tree = try XCTUnwrap(root.layer.presentation())

        XCTAssertEqual(recorder.pickerSnapshots(in: root, tree: tree, at: window.bounds).map(\.view), [picker])
    }

    private func makePickerWindow() -> (UIWindow, UIView, UIPickerView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        let rootVC = UIViewController()
        rootVC.view.backgroundColor = .white
        window.rootViewController = rootVC
        window.isHidden = false
        let picker = UIPickerView(frame: CGRect(x: 0, y: 100, width: 300, height: 216))
        rootVC.view.addSubview(picker)
        window.layoutIfNeeded()
        CATransaction.flush()
        recorder.captureMethod = .layerTree
        return (window, rootVC.view, picker)
    }

    func testSnapshottedViews_SkipsHiddenPickers() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        let picker = UIPickerView(frame: CGRect(x: 0, y: 0, width: 300, height: 216))
        picker.isHidden = true
        root.addSubview(picker)

        XCTAssertTrue(recorder.snapshottedViews(in: root).isEmpty)
    }

    private func countPixels(of image: UIImage, where matches: ((red: Int, green: Int, blue: Int)) -> Bool) -> Int {
        guard let cgImage = image.cgImage else { return -1 }
        let width = cgImage.width
        let height = cgImage.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard
            let context = CGContext(
                data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return -1 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for index in stride(from: 0, to: rgba.count, by: 4)
        where matches((Int(rgba[index]), Int(rgba[index + 1]), Int(rgba[index + 2]))) {
            count += 1
        }
        return count
    }

    private func pixel(of image: UIImage, at point: CGPoint) -> (red: Double, green: Double, blue: Double)? {
        guard let cgImage = image.cgImage else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        guard
            let context = CGContext(
                data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // `point` is in top-left image coordinates; the bitmap context's origin is
        // bottom-left, so the image is placed so that row `point.y` from the top lands
        // on the context's one pixel.
        let height = CGFloat(cgImage.height)
        context.draw(
            cgImage,
            in: CGRect(
                x: -point.x * image.scale, y: -(height - point.y * image.scale),
                width: CGFloat(cgImage.width), height: height))
        return (Double(rgba[0]), Double(rgba[1]), Double(rgba[2]))
    }

    // MARK: - getTopViewFor (with isPresented flag)

    func testGetTopViewFor_ReturnsIsPresentedFalseForRegularView() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        let rootVC = UIViewController()
        let view = UIView(frame: window.bounds)
        rootVC.view = view
        window.rootViewController = rootVC
        window.makeKeyAndVisible()

        let result = recorder.getTopViewFor(window: window)

        XCTAssertNotNil(result.view, "View should be returned")
        XCTAssertNotNil(result.viewBounds, "View bounds should be returned")
        XCTAssertFalse(result.isPresented, "isPresented should be false for regular view")
    }

    func testGetTopViewFor_ReturnsNilForOutOfBoundsView() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        let rootVC = UIViewController()
        // Create view that's way outside window bounds
        let view = UIView(frame: CGRect(x: 10000, y: 10000, width: 100, height: 100))
        rootVC.view = view
        window.rootViewController = rootVC

        let result = recorder.getTopViewFor(window: window)

        XCTAssertNil(result.view, "View should be nil for out of bounds view")
        XCTAssertNil(result.viewBounds, "View bounds should be nil for out of bounds view")
    }

    // MARK: - Background Fill Color

    func testBackgroundFillColor_IsCorrectGray() {
        // Verify the background fill color is correct (203/255 for each RGB component)
        let expectedColor = UIColor(red: 203 / 255.0, green: 203 / 255.0, blue: 203 / 255.0, alpha: 1.0)

        XCTAssertEqual(
            recorder.backgroundFillColor, expectedColor,
            "Background fill color should be light gray (203/255)")
    }

    // MARK: - captureScreenshot
    func testCaptureScreenshot_ReturnsNilIfWindowIsNil() {
        let result = recorder.captureScreenshot()
        XCTAssertNil(result, "Should return nil if no window is available")
    }

    // MARK: - Wireframe / screenshot timestamp agreement

    /// The render path must hand the wireframe emitter the same capture instant it reports
    /// to its caller, so the `mp_wireframe` event and the screenshot event describing one
    /// frame agree. Two regressions live here: the emitter used to read the clock itself
    /// after rendering finished (drifting from the screenshot by the render duration), and
    /// the instant used to come *in* from `record()` as the trigger time — on a
    /// touch-triggered capture, the touch's own timestamp, which tied the frame to the
    /// touch that produced it. Android reads it right after `createBitmapFromView` and
    /// Flutter reads `captureTimestamp` at the render for the same reason.
    func testRenderViewHierarchyAsImage_stampsWireframeWithTheCaptureInstant() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 20))
        label.text = "Welcome"
        window.addSubview(label)
        window.isHidden = false

        EventPublisher.shared.resetSubscribers()
        // The publisher calls back on the emitter's queue, so this array is mutated off the
        // test thread and read on it. Guarded, and awaited through an expectation rather
        // than a polled deadline: the 2s of RunLoop pumping it replaces was a bet on how
        // soon the machine got round to the emit, and it lost intermittently on CI.
        let publishedLock = NSLock()
        var published: [SessionEvent] = []
        let receivedWireframe = expectation(description: "mp_wireframe published")
        receivedWireframe.assertForOverFulfill = false
        let subscriber = CapturingCustomEventSubscriber {
            publishedLock.lock()
            published.append($0)
            publishedLock.unlock()
            receivedWireframe.fulfill()
        }
        EventPublisher.shared.subscribe(subscriber)

        SensitiveViewManager.reset()
        SensitiveViewManager.shared.wireframeCollectionEnabled = true
        recorder.wireframeEmitter = WireframeEmitter(options: MPWireframesOptions())
        defer {
            recorder.wireframeEmitter = nil
            SensitiveViewManager.reset()
            EventPublisher.shared.resetSubscribers()
        }

        let before = TimestampUtils.timestamp()
        let frame = try XCTUnwrap(recorder.renderViewHierarchyAsImage(window: window))
        let after = TimestampUtils.timestamp()

        wait(for: [receivedWireframe], timeout: 10.0)

        publishedLock.lock()
        let firstPublished = published.first
        publishedLock.unlock()

        let event = try XCTUnwrap(firstPublished, "expected an mp_wireframe event")
        XCTAssertEqual(
            event.timestamp, frame.capturedAtMs,
            "wireframe must carry the same capture instant the frame reports")
        // Read at the render, so it falls inside the window this call occupied — it is
        // neither a trigger time from before the call nor a clock read after publishing.
        XCTAssertGreaterThanOrEqual(frame.capturedAtMs, before)
        XCTAssertLessThanOrEqual(frame.capturedAtMs, after)
    }

    // MARK: - Empty wireframes

    /// A frame that yields no elements still ships an `mp_wireframe` event with an empty
    /// `elements` array. "Described, nothing readable" is a different fact from "never
    /// described" — suppressing the event would leave the summarizer unable to tell a
    /// blank screen from a frame we failed to walk. Android emits it too; iOS used to
    /// gate the emit on `!wireframes.isEmpty`.
    func testRenderViewHierarchyAsImage_emitsWireframeForAFrameWithNoElements() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        // No labels, no controls — nothing the walker can turn into an element.
        window.addSubview(UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200)))
        window.isHidden = false

        EventPublisher.shared.resetSubscribers()
        // The publisher calls back on the emitter's queue, so this array is mutated off the
        // test thread and read on it. Guarded, and awaited through an expectation rather
        // than a polled deadline: the 2s of RunLoop pumping it replaces was a bet on how
        // soon the machine got round to the emit, and it lost intermittently on CI.
        let publishedLock = NSLock()
        var published: [SessionEvent] = []
        let receivedWireframe = expectation(description: "mp_wireframe published")
        receivedWireframe.assertForOverFulfill = false
        let subscriber = CapturingCustomEventSubscriber {
            publishedLock.lock()
            published.append($0)
            publishedLock.unlock()
            receivedWireframe.fulfill()
        }
        EventPublisher.shared.subscribe(subscriber)

        SensitiveViewManager.reset()
        SensitiveViewManager.shared.wireframeCollectionEnabled = true
        recorder.wireframeEmitter = WireframeEmitter(options: MPWireframesOptions())
        defer {
            recorder.wireframeEmitter = nil
            SensitiveViewManager.reset()
            EventPublisher.shared.resetSubscribers()
        }

        XCTAssertNotNil(recorder.renderViewHierarchyAsImage(window: window))

        wait(for: [receivedWireframe], timeout: 10.0)

        publishedLock.lock()
        let firstPublished = published.first
        publishedLock.unlock()

        let event = try XCTUnwrap(firstPublished, "an empty frame must still emit mp_wireframe")
        guard case .customData(let custom) = event.data else {
            return XCTFail("expected customData")
        }
        XCTAssertEqual(custom.tag, WireframeEmitter.tag)
        XCTAssertTrue(custom.payload.elements.isEmpty, "expected a zero-element payload")
        XCTAssertEqual(custom.payload.viewport, [200, 200], "viewport still describes the frame")
    }
}

private final class CapturingCustomEventSubscriber: EventListener {
    let onCustom: (SessionEvent) -> Void
    init(onCustom: @escaping (SessionEvent) -> Void) { self.onCustom = onCustom }
    func receivedTouchEvent(_ rawEvent: RawTouchEvent) {}
    func receivedScreenshotEvent(_ rawEvent: RawScreenshotEvent) {}
    func receivedCustomEvent(_ event: SessionEvent) { onCustom(event) }
}
