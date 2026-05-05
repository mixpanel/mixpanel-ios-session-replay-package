//
//  Swizzler.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation
import ObjectiveC.runtime
import UIKit

// MARK: - Dependency Protocols

protocol MPSessionReplaying {
    var isRecording: Bool { get set }
    func record(_ triggerTimestamp: Int64?)
    func markScreenDirty()
}

protocol TouchEventProcessing {
    func processTouchEvent(_ event: UIEvent)
}

// MARK: - Type Aliases

private typealias ViewControllerLifecycleIMP =
    @convention(c) (
        UIViewController, Selector, Bool
    ) ->
    Void
private typealias ViewControllerLifecycleBlock =
    @convention(block) (
        UIViewController, Bool
    ) -> Void

private typealias LayoutSubviewsIMP = @convention(c) (UIView, Selector) -> Void

private typealias LayoutSubviewsBlock = @convention(block) (UIView) -> Void

private typealias SendEventIMP =
    @convention(c) (
        UIApplication, Selector, UIEvent
    ) -> Void

private typealias SendEventBlock =
    @convention(block) (UIApplication, UIEvent)
    -> Void

private typealias PresentViewControllerIMP =
    @convention(c) (UIViewController, Selector, UIViewController, Bool, (() -> Void)?) -> Void
private typealias PresentViewControllerBlock =
    @convention(block) (UIViewController, UIViewController, Bool, (() -> Void)?) -> Void

/// A value type that uniquely identifies a swizzled Objective-C method
/// on a given class. Used as a key in the swizzled methods cache to
/// track and restore original method implementations during unswizzling.
///
/// Conforms to `Hashable` and `Equatable` by combining the method selector
/// and class name, ensuring uniqueness per class-method pair.
struct SwizzledMethod: Hashable {
    let method: Method
    private let className: AnyClass

    init(method: Method, className: AnyClass) {
        self.method = method
        self.className = className
    }

    static func == (lhs: SwizzledMethod, rhs: SwizzledMethod) -> Bool {
        let methodParity = (lhs.method == rhs.method)
        let classParity =
            (NSStringFromClass(lhs.className)
                == NSStringFromClass(rhs.className))
        return methodParity && classParity
    }

    func hash(into hasher: inout Hasher) {
        let methodName = NSStringFromSelector(method_getName(method))
        let className = NSStringFromClass(className)
        let identifier = "\(methodName)|||\(className)"
        hasher.combine(identifier)
    }
}

//MARK: - Swizzler

/// A utility class providing convenience methods to swizzle key methods
/// (viewDidAppear:, viewDidDisappear:, layoutSubviews, and sendEvent(_:))
/// via direct replacement swizzling.
final class Swizzler: TouchEventProcessing {
    static let shared = Swizzler()
    private var swizzledMethodsCache: [SwizzledMethod: IMP] = [:]

    /// Test hook to override the default `MPSessionReplay` instance with a mock or custom implementation.
    /// Used for unit testing to inject dependencies.
    var testOverride_sessionReplay: MPSessionReplaying?
    /// Test hook to override the default touch event processor with a mock or custom implementation.
    /// Useful for validating swizzled touch event handling.
    var testOverride_touchProcessor: TouchEventProcessing?

    /// Returns the overridden `MPSessionReplaying` instance if set, otherwise returns the shared `MPSessionReplay` instance.
    /// This allows test cases to inject a mock instance while production code uses the singleton.
    var sessionReplay: MPSessionReplaying? {
        testOverride_sessionReplay ?? MPSessionReplay.getInstance()
    }
    /// Returns the overridden `TouchEventProcessing` instance if set, otherwise returns the `Swizzler.shared` instance.
    /// Enables unit testing by substituting the event processor.
    var touchProcessor: TouchEventProcessing {
        testOverride_touchProcessor ?? Swizzler.shared
    }

    /// Delay used before performing operations that depend on view controller
    /// or window animations having fully completed (e.g. complex modal
    /// presentations or navigation transitions). Empirically, 0.4 seconds
    /// has been sufficient to cover standard UIKit animations, including
    /// those with additional spring or transition effects.
    let animationDelay: TimeInterval = 0.4

    // MARK: - Base Swizzling Method
    /// Replaces the given selector in `cls` with a new implementation, produced by `closure`.
    /// - Parameters:
    ///   - cls: The class on which to swizzle the method.
    ///   - selector: The method selector to replace (e.g. `#selector(UIViewController.viewDidAppear(_:))`).
    ///   - oldSig: The Swift type matching the C function signature of the original `IMP`.
    ///   - newSig: The Swift type for the new closure.
    ///   - closure: A closure that takes the old (typed) function pointer and returns your new closure.
    ///
    /// **Note**:
    /// - `oldSig` must use `@convention(c)` to match Objective-C calling conventions.
    /// - `newSig` can be a normal Swift closure or `@convention(block)`, as needed.
    /// - Be certain your parameter/return types exactly match the real Objective-C method.
    fileprivate static func swizzle<OldSig, NewSig>(
        in cls: AnyClass,
        selector: Selector,
        oldSig: OldSig.Type,
        newSig: NewSig.Type,
        closure: @escaping (OldSig) -> NewSig
    ) {
        // 1) Find the method. If it doesn't exist, no action needed.
        guard let method = class_getInstanceMethod(cls, selector) else {
            return
        }
        // 2) Get the existing implementation pointer.
        let oldIMP = method_getImplementation(method)

        let swizzledMethod = SwizzledMethod(method: method, className: cls)
        shared.sync {
            shared.swizzledMethodsCache[swizzledMethod] = oldIMP
        }

        // 3) Cast it to the provided `OldSig` function type (including @convention(c) if needed).
        let typedOldFunction = unsafeBitCast(oldIMP, to: oldSig)

        // 4) Build the new closure by calling user-provided `closure`.
        let newClosure = closure(typedOldFunction)

        // 5) Convert that Swift closure into an Objective-C function pointer.
        let newIMP = imp_implementationWithBlock(newClosure)

        // 6) Replace the method's implementation with our new IMP.
        method_setImplementation(method, newIMP)
    }

    // MARK: - Dispatch Record
    fileprivate static func dispatchRecord() {
        guard Swizzler.shared.sessionReplay?.isRecording == true else { return }
        // Delay 0.4 seconds to safely finish all the ongoing transitions
        DispatchQueue.main.asyncAfter(deadline: .now() + Swizzler.shared.animationDelay) {
            Swizzler.shared.sessionReplay?.record(nil)  // Pass nil for the optional timestamp
        }
    }

    // MARK: - UIViewController Lifecycle

    /// Swizzles `viewDidAppear:`in `UIViewController`.
    static func swizzleViewControllerLifecycle() {
        // 1) viewDidAppear:
        Swizzler.swizzle(
            in: UIViewController.self,
            selector: #selector(UIViewController.viewDidAppear(_:)),
            oldSig: ViewControllerLifecycleIMP.self,
            newSig: ViewControllerLifecycleBlock.self
        ) { originalImp in
            return { (vc, animated) in
                // Call the original implementation
                originalImp(
                    vc, #selector(UIViewController.viewDidAppear(_:)), animated)
                // Call our logic
                dispatchRecord()
            }
        }
    }

    // MARK: - UIView layoutSubviews

    fileprivate static func markScreenDirtyAfterLayout() {
        guard Swizzler.shared.sessionReplay?.isRecording == true else { return }

        Swizzler.shared.sessionReplay?.markScreenDirty()
    }

    /// Swizzles `layoutSubviews` in `UIView`.
    static func swizzleLayoutSubviews() {
        Swizzler.swizzle(
            in: UIView.self,
            selector: #selector(UIView.layoutSubviews),
            oldSig: LayoutSubviewsIMP.self,
            newSig: LayoutSubviewsBlock.self
        ) { originalImp in
            return { (view) in
                // Call the original implementation
                originalImp(view, #selector(UIView.layoutSubviews))
                markScreenDirtyAfterLayout()
            }
        }
    }

    // MARK: - UIApplication sendEvent(_:)

    /// Swizzles `sendEvent(_:)` in `UIApplication`.
    static func swizzleSendEvent() {
        Swizzler.swizzle(
            in: UIApplication.self,
            selector: #selector(UIApplication.sendEvent(_:)),
            oldSig: SendEventIMP.self,
            newSig: SendEventBlock.self
        ) { originalImp in
            return { (app, event) in
                // Call our logic
                Swizzler.shared.touchProcessor.processTouchEvent(event)
                // Call the original implementation
                originalImp(app, #selector(UIApplication.sendEvent(_:)), event)
            }
        }
    }

    func processTouchEvent(_ event: UIEvent) {
        TouchEventTracker.processEvent(event)
    }

    @discardableResult
    private func sync<T>(block: () -> T) -> T {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        return block()
    }

    func originalImplementation(of cachedMethod: SwizzledMethod) -> IMP? {
        sync {
            if let originalImp = swizzledMethodsCache[cachedMethod] {
                return originalImp
            } else {
                return nil
            }
        }
    }

    static func swizzleViewWillDisappear() {
        Swizzler.swizzle(
            in: UIViewController.self,
            selector: #selector(UIViewController.viewWillDisappear(_:)),
            oldSig: ViewControllerLifecycleIMP.self,
            newSig: ViewControllerLifecycleBlock.self
        ) { originalImp in
            return { (vc, animated) in
                MPSessionReplay.getInstance()?.debugMaskOverlayManager?.enableTransitioningState()

                // Call the original implementation
                originalImp(
                    vc, #selector(UIViewController.viewWillDisappear(_:)), animated)
            }
        }
    }

    static func swizzlePresentViewController() {
        Swizzler.swizzle(
            in: UIViewController.self,
            selector: #selector(UIViewController.present(_:animated:completion:)),
            oldSig: PresentViewControllerIMP.self,
            newSig: PresentViewControllerBlock.self
        ) { originalImp in
            return { (presentingVC, presentedVC, animated, completion) in
                MPSessionReplay.getInstance()?.debugMaskOverlayManager?.enableTransitioningState()

                // Call the original implementation
                originalImp(
                    presentingVC,
                    #selector(UIViewController.present(_:animated:completion:)),
                    presentedVC,
                    animated,
                    completion
                )
            }
        }
    }

    /// Reverses swizzling and resets the method to its original implementation.
    /// Needs to be called on the main thread.
    func unswizzle() {
        ThreadUtils.runOnMainThread { [weak self] in
            guard let self else { return }
            for cachedMethod in self.swizzledMethodsCache.keys {
                if let originalIMP = self.originalImplementation(of: cachedMethod) {
                    method_setImplementation(cachedMethod.method, originalIMP)
                }
            }
            self.swizzledMethodsCache.removeAll()
            MPSessionReplayInstance.isSwizzled = false
            DebugMaskOverlayManager.isSwizzled = false
        }
    }
}
