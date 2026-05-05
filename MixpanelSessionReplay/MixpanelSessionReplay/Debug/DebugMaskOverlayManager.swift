//
//  DebugMaskOverlayManager.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import UIKit

/// Manages the debug mask overlay that displays which views are being masked.
///
/// This manager attaches an overlay view to each root window and updates
/// the displayed mask regions when they change.
///
/// **Important**: This overlay only works in debug builds to prevent
/// accidental exposure in production. Use `create()` to obtain an instance.
class DebugMaskOverlayManager {

    /// Creates a DebugMaskOverlayManager if the app is debuggable.
    /// Returns nil for non-debuggable (release) builds to prevent accidental exposure.
    ///
    /// - Parameter colors: The overlay color configuration
    /// - Returns: DebugMaskOverlayManager instance if debuggable, nil otherwise
    static func create(colors: DebugOverlayColors) -> DebugMaskOverlayManager? {
        #if DEBUG
        return DebugMaskOverlayManager(colors: colors)
        #else
        Logger.warn(message: "Debug mask overlay is disabled in release builds")
        return nil
        #endif
    }

    private let colors: DebugOverlayColors

    private var isEnabled = false
    /// Uses weak keys to avoid retaining UIWindow instances, preventing memory leaks
    /// with multi-scene apps or transient windows (alerts, keyboards, etc.)
    private var overlayViews: NSMapTable<UIWindow, DebugMaskOverlayView>
    private var currentMaskDecisions: [HashableRect: MaskDecision] = [:]
    private var windowObserver: NSObjectProtocol?
    private var updateTimer: Timer?
    private let updateInterval: TimeInterval = 0.5  // Update every 500ms
    /// Flag to prevent concurrent updates from timer and listener paths
    private var isUpdating = false
    /// Flag that tells if screen is transitioning
    var isTransitioning = false {
        didSet {
            // If screen is transitioning then hide the overlay views
            if isTransitioning {
                hideAllOverlays()
            }
        }
    }
    static var isSwizzled = false

    private init(colors: DebugOverlayColors) {
        self.colors = colors
        // Initialize map table with weak keys and strong values
        overlayViews = NSMapTable<UIWindow, DebugMaskOverlayView>(
            keyOptions: .weakMemory,
            valueOptions: .strongMemory
        )

        /// Observes `UIScene.didActivateNotification` to attach overlay views to windows
        /// belonging to newly activated scenes.
        ///
        /// This handles two cases that `UIWindow.didBecomeVisibleNotification` misses:
        /// - A new iPad window (scene) is opened by the user via multitasking
        /// - The app is brought back to the foreground from another app
        windowObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, self.isEnabled else { return }
            if let scene = notification.object as? UIWindowScene {
                for window in scene.windows where ViewUtils.isAppOwnedWindow(window) {
                    self.attachOverlayToWindow(window)
                }
            }
        }
    }

    deinit {
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        updateTimer?.invalidate()
    }

    /// Enables the debug mask overlay.
    /// Attaches overlay views to all existing windows and starts periodic updates.
    func enable() {
        guard !isEnabled else { return }
        isEnabled = true

        Logger.info(message: "Debug mask overlay enabled")

        // Attach overlay to all existing windows
        ThreadUtils.runOnMainThread { [weak self] in
            guard let self = self else { return }

            if !DebugMaskOverlayManager.isSwizzled {
                Swizzler.swizzleViewWillDisappear()
                Swizzler.swizzlePresentViewController()
                DebugMaskOverlayManager.isSwizzled = true
            }

            let windows = ViewUtils.getAllWindows()
            for window in windows {
                self.attachOverlayToWindow(window)
            }

            // Start periodic updates
            self.startPeriodicUpdates()
        }
    }

    /// Disables the debug mask overlay.
    /// Removes overlay views from all windows and stops periodic updates.
    func disable() {
        guard isEnabled else { return }

        ThreadUtils.runOnMainThread { [weak self] in
            guard let self = self else { return }
            self.isEnabled = false

            // Stop periodic updates
            // Timer must be invalidated on its creation thread
            self.updateTimer?.invalidate()
            self.updateTimer = nil

            // Remove overlays from all windows
            if let enumerator = self.overlayViews.objectEnumerator() {
                for case let overlayView as DebugMaskOverlayView in enumerator {
                    overlayView.removeFromSuperview()
                }
            }
            self.overlayViews.removeAllObjects()
            self.currentMaskDecisions = [:]

            Logger.info(message: "Debug mask overlay disabled")
        }
    }

    /// Temporarily enables transitioning state to hide overlay views during screen transitions.
    ///
    /// This method sets the `isTransitioning` flag to `true`, which triggers `hideAllOverlays()`
    /// to hide the overlay views during the transition animation. After a delay matching the
    /// standard UIKit animation duration, the flag is reset to `false`, allowing overlays
    /// to become visible again.
    func enableTransitioningState() {
        if isEnabled {
            isTransitioning = true
            DispatchQueue.main.asyncAfter(deadline: .now() + Swizzler.shared.animationDelay) { [weak self] in
                self?.isTransitioning = false
            }
        }
    }

    /// Hides all active overlay views by setting their `isHidden` property to true.
    ///
    /// This method clears the current mask regions cache and iterates through all
    /// overlay views in the map table, hiding each one without removing it from
    /// the view hierarchy. This is useful during screen transitions when the overlay
    /// should be temporarily hidden but will be shown again shortly.
    ///
    /// - Note: This method is called automatically when `isTransitioning` is set to `true`.
    /// - Important: The overlays remain in the view hierarchy and retain their position;
    private func hideAllOverlays() {
        ThreadUtils.runOnMainThread { [weak self] in
            self?.currentMaskDecisions = [:]
            if let enumerator = self?.overlayViews.objectEnumerator() {
                for case let overlayView as DebugMaskOverlayView in enumerator {
                    overlayView.isHidden = true
                }
            }
        }
    }

    /// Updates the displayed mask regions on all overlay views.
    /// - Parameter decisions: Dictionary mapping rectangles to their mask decisions
    /// - Parameter window: UIWindow object for the overlay to add
    func updateMaskRegions(_ decisions: [HashableRect: MaskDecision], for window: UIWindow) {
        performUpdate(with: decisions, for: window)
    }

    /// Shared method to perform mask region updates with race condition protection.
    /// Only one update can execute at a time; concurrent calls are discarded.
    private func performUpdate(with decisions: [HashableRect: MaskDecision], for window: UIWindow) {
        ThreadUtils.runOnMainThread { [weak self] in
            guard let self = self else { return }

            // Skip if another update is already in progress (discard this update)
            guard !self.isUpdating && !isTransitioning else {
                Logger.debug(
                    message:
                        "Skipping concurrent mask overlay update isUpdating = \(self.isUpdating) && isTransitioning = \(self.isTransitioning)"
                )
                return
            }

            // Set flag to prevent concurrent updates
            self.isUpdating = true

            // Ensure flag is reset even if an error occurs
            defer {
                self.isUpdating = false
            }

            // Skip if decisions haven't changed
            guard self.currentMaskDecisions != decisions else { return }
            self.currentMaskDecisions = decisions

            // Update all active overlay views
            if let overlayView = self.overlayViews.object(forKey: window) {
                overlayView.updateMaskDecisions(decisions)
                overlayView.isHidden = false
            }
        }
    }

    /// Attaches a debug overlay view to the specified window.
    /// Creates and configures a new overlay view, adds it to the window hierarchy,
    /// and tracks it in the overlay views map.
    /// - Parameter window: The window to attach the overlay to
    private func attachOverlayToWindow(_ window: UIWindow) {
        // Set isTransitioning to false and skip if already attached
        if overlayViews.object(forKey: window) != nil {
            isTransitioning = false
            return
        }

        let overlayView = DebugMaskOverlayView(frame: window.bounds, colors: colors)
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Add overlay as a subview to the window
        window.addSubview(overlayView)

        // Ensure overlay stays on top
        window.bringSubviewToFront(overlayView)

        // Update with current mask decisions
        overlayView.updateMaskDecisions(currentMaskDecisions)

        overlayViews.setObject(overlayView, forKey: window)
        Logger.info(message: "Debug overlay attached to window")
    }

    /// Starts a repeating timer that updates mask regions every 500ms.
    /// Fires immediately on start, then continues at the specified interval.
    private func startPeriodicUpdates() {
        // Invalidate existing timer if any
        updateTimer?.invalidate()

        // Create a new timer that fires every 500ms
        updateTimer = Timer.scheduledTimer(
            withTimeInterval: updateInterval,
            repeats: true
        ) { [weak self] _ in
            self?.computeAndUpdateMaskRegions()
        }

        // Fire immediately for the first update
        computeAndUpdateMaskRegions()
    }

    private func computeAndUpdateMaskRegions() {
        guard isEnabled else { return }

        // Get the current window
        guard let currentWindow = ViewUtils.getCurrentWindow() else { return }

        // Get the top view (similar to ScreenRecorder logic)
        let (view, _, _) = ScreenRecorder.shared.getTopViewFor(window: currentWindow)

        guard let view = view else { return }

        // Compute mask decisions — the maskRegionsListener callback will
        // deliver the results (including unmask entries) to updateMaskRegions
        _ = SensitiveViewManager.shared.getSensitiveFrames(in: view, window: currentWindow)
    }
}
