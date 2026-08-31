//
//  MixpanelSessionReplayInstance.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation
import UIKit

open class MPSessionReplayInstance: MPSessionReplaying {
    static var recordWorkItem: DispatchWorkItem?
    static var lastRecordTimestamp: Int64 = 0
    static var isSwizzled: Bool = false

    private var _screenIsDirty: Bool = true

    var flushService: FlushService
    var eventService: EventService

    var config: MPSessionReplayConfig
    var token: String

    var shouldRecordSession: Bool = false
    ///Tells you if the current session should be recorded based on the given sampling rate
    public internal(set) var isRecording: Bool = false
    ///Tells you if the recording is in-progress

    var debugMaskOverlayManager: DebugMaskOverlayManager?
    /// Controls whether event triggers are evaluated (default: true)
    public internal(set) var isEventTriggersEnabled: Bool = true

    #if !os(OSX) && !os(watchOS)
    var taskId = UIBackgroundTaskIdentifier.invalid
    #endif

    init(token: String, distinctId: String, config: MPSessionReplayConfig) {
        self.config = config
        self.token = token
        self.wifiOnly = config.wifiOnly
        self.loggingEnabled = config.enableLogging

        eventService = EventService()
        flushService = FlushService(
            token: token, distinctId: distinctId, eventService: eventService, wifiOnly: config.wifiOnly,
            flushInterval: config.flushInterval, serverURL: config.serverURL)

        // Initialize debug mask overlay if enabled (DEBUG builds only)
        if let overlayColors = config.debugOptions?.overlayColors,
            let manager = DebugMaskOverlayManager.create(colors: overlayColors)
        {
            debugMaskOverlayManager = manager

            // Set up mask regions listener
            SensitiveViewManager.shared.maskRegionsListener = { [weak self] (decisions, window) -> Void in
                if let window = window {
                    self?.debugMaskOverlayManager?.updateMaskRegions(decisions, for: window)
                }
            }
        }

        // Wire up wireframes if opted in. `wireframesOptions` is the single
        // switch that turns capture on; `debugOptions.wireframeEmitter` only
        // observes it, so passing it without wireframes options is a no-op.
        if let wireframesOptions = config.wireframesOptions {
            ScreenRecorder.shared.wireframeEmitter = WireframeEmitter(
                options: wireframesOptions,
                debugEmitter: config.debugOptions?.wireframeEmitter)
            SensitiveViewManager.shared.wireframeClassifier.useAccessibilityLabelFallback =
                wireframesOptions.useAccessibilityLabelFallback
            SensitiveViewManager.shared.wireframeCollectionEnabled = true
        }

        // This will not trigger the didSet of autoMaskedViews, so we need to call the update method here to make sure the masking is updated according to the config during initialization.
        self.autoMaskedViews = config.autoMaskedViews
        updateSensitiveViewMasking(config.autoMaskedViews)
        updateWifiOnly(config.wifiOnly)

        configureBackgroundObserver()
        configureAutoStartRecording()

        Logger.debug(
            message:
                "Initialised the SDK with config: \(config)."
        )
    }

    //MARK: Initialization helper methods
    open var wifiOnly: Bool = true {
        didSet {
            updateWifiOnly(wifiOnly)
        }
    }

    private func updateWifiOnly(_ wifiOnly: Bool) {
        flushService.wifiOnly = wifiOnly
    }

    open var autoMaskedViews: Set<MPAutoMaskedViews> = [] {
        didSet {
            guard oldValue != autoMaskedViews else { return }
            config.autoMaskedViews = autoMaskedViews
            updateSensitiveViewMasking(autoMaskedViews)
        }
    }

    open var loggingEnabled: Bool = false {
        didSet {
            MPSessionReplayManager.sharedInstance.updateLoggingEnabled(loggingEnabled)
        }
    }

    private func updateSensitiveViewMasking(_ autoMaskedViews: Set<MPAutoMaskedViews>) {
        ThreadUtils.runOnMainThread {
            SensitiveViewManager.shared.maskAllText = autoMaskedViews.contains(.text)
            SensitiveViewManager.shared.maskAllImages = autoMaskedViews.contains(.image)
            SensitiveViewManager.shared.maskAllWebViews = autoMaskedViews.contains(.web)
            SensitiveViewManager.shared.maskAllMapViews = autoMaskedViews.contains(.map)
            SensitiveViewManager.shared.clearCache()
        }
    }

    private func configureBackgroundObserver() {
        /// stop recording when app goes to background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    private func configureForegroundObserver() {
        /// restart recording when app enters foreground
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(autoStartRecording),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc func markScreenDirty() {
        // Use main queue for immediate, lightweight flag setting
        // markScreenDirty() is just a boolean setter - no performance impact
        ThreadUtils.runOnMainThread { [weak self] in
            self?._screenIsDirty = true
        }
    }

    func isScreenDirty() -> Bool {
        return _screenIsDirty
    }
    func removeObservers() {
        //Remove all observers set
        NotificationCenter.default.removeObserver(self)

        // Clean up mask regions listener (safe to set to nil even if not set)
        SensitiveViewManager.shared.maskRegionsListener = nil

        // Tear down wireframe capture (safe to run when never enabled). Only the emitter
        // needs clearing by hand: `ScreenRecorder` is a separate singleton that survives
        // this teardown, while every `SensitiveViewManager` flag — `wireframeCollectionEnabled`
        // included — goes with `SensitiveViewManager.reset()` a few lines later in
        // `deinitializeInstance`, the sole caller of this method.
        ScreenRecorder.shared.wireframeEmitter = nil
    }

    @objc func appDidEnterBackground() {
        stopRecordingOnAppDidEnterBackground()
    }

    #if !os(OSX) && !os(watchOS)
    private func sharedUIApplication() -> UIApplication? {
        guard
            let sharedApplication =
                UIApplication.perform(NSSelectorFromString("sharedApplication"))?.takeUnretainedValue()
                as? UIApplication
        else {
            return nil
        }
        return sharedApplication
    }
    #endif  // !os(OSX)

    private func performSwizzling() {
        // Swizzle check to avoid re-swizzling the methods
        guard !MPSessionReplayInstance.isSwizzled else {
            return
        }
        Swizzler.swizzleViewControllerLifecycle()
        Swizzler.swizzleLayoutSubviews()
        Swizzler.swizzleSendEvent()

        MPSessionReplayInstance.isSwizzled = true
    }

    private func configureAutoStartRecording() {
        // If the autoStartRecording is enabled, then start recording
        if isAutoStartRecordingEnabled() {
            autoStartRecording()
            configureForegroundObserver()
        }
    }

    private func isAutoStartRecordingEnabled() -> Bool {
        if config.autoStartRecording && config.recordingSessionsPercent > 0 && config.recordingSessionsPercent <= 100.0
        {
            return true
        }
        return false
    }

    @objc func autoStartRecording() {
        Logger.info(message: "Starting automatic recording")
        startRecording(sessionsPercent: config.recordingSessionsPercent)
    }

    //MARK: Record functionality

    /// Manually starts session replay recording.
    ///
    /// - Parameter sessionsPercent: A value from 0 to 100 representing the likelihood that the current session will be recorded.
    ///   This controls sampling of sessions. Defaults to 100 (record all sessions) if not specified.
    ///   The `recordingSessionsPercent` value from the config is ignored when calling this method.
    ///
    /// If recording is already active, calling this method has no effect.
    public func startRecording(sessionsPercent: Double = 100.0) {
        /// Use main thread for all recording start setup to ensure thread safety with consistent state updates and avoid potential race conditions
        ThreadUtils.runOnMainThread { [weak self] in
            guard let self = self else { return }
            if isRecording {
                Logger.warn(message: "Recording is already in progress, startRecording call ignored.")
                return
            }

            shouldRecordSession = shouldRecordSessionFor(percent: sessionsPercent)
            if shouldRecordSession {
                SessionManager.shared.generateNewSession()
                // generate a new session will make old session events obsolete, so clean it up.
                eventService.clearEvents()
                // Wireframe dedup is per *session*, not per SDK lifetime. The emitter
                // outlives a stop/start cycle, so without this the new replay's first
                // frame is compared against the previous replay's last one — and a
                // background/foreground onto an unchanged screen dedups it away,
                // shipping an opening screenshot with no `mp_wireframe` to describe it.
                // This is the one session boundary: `generateNewSession()` has no other
                // caller. Android and Flutter reset at the same point.
                ScreenRecorder.shared.wireframeEmitter?.resetDedup()
                performSwizzling()
                record()
                isRecording = true

                // Enable debug mask overlay if configured
                debugMaskOverlayManager?.enable()

                flushService.start()
                MPSessionReplaySender.shared.register(data: ["$mp_replay_id": SessionManager.shared.replayId])
                Logger.debug(message: "Started recording, replay id - \(SessionManager.shared.replayId)")
            }
        }
    }

    /// Manually capture the screenshot If you have disabled the auto capture.
    /// Make sure you have started the recording by calling `startRecording` method.
    public func captureScreenshot() {
        guard isRecording else {
            Logger.warn(
                message:
                    "Cannot capture screenshot, recording is not started yet. Please call `startRecording` first."
            )
            return
        }
        markScreenDirty()
        record()
    }

    /// Manually capture the screenshot with touch event If you have disabled the auto capture.
    /// Make sure you have started the recording by calling `startRecording` method.
    public func captureScreenshot(withTouchEvent event: UIEvent) {
        guard isRecording else {
            Logger.warn(
                message:
                    "Cannot capture screenshot, recording is not started yet. Please call `startRecording` first."
            )
            return
        }
        markScreenDirty()
        TouchEventTracker.processEvent(event)
    }

    /// Sets the distinct ID to session replays. You can use this method to update the distinctId post the Session Replay SDK initialisation.
    /// It is recommended to call Identify from Mixpanel main SDK first and then calling identify from the Session Replay SDK.
    /// This makes sure to properly merge the users.
    /// - Parameter distinctId: distinctId of the user.
    /// - Parameter completion: completion handler to be called after updating the distinct id.
    public func identify(distinctId: String, completion: @escaping () -> Void = {}) {
        guard distinctId != flushService.getDistinctId() && distinctId != "" else {
            completion()
            return
        }
        self.flushService.flushEvents(
            forAll: true,
            completionHandler: { [weak self] in
                self?.flushService.updateDistinctId(distinctId)
                // Ensure the completion handler is executed on the main queue.
                DispatchQueue.main.async {
                    completion()
                }
            })
    }

    /// Returns the URL to view the current session replay in the Mixpanel dashboard.
    ///
    /// - Returns: The session replay URL if recording is active, or `nil` if not recording.
    public func getSessionReplayURL() -> String? {
        guard isRecording else { return nil }
        var components = URLComponents(string: MPSessionReplayAPI.sessionReplayRedirect)
        components?.queryItems = [
            URLQueryItem(name: "replay_id", value: SessionManager.shared.replayId),
            URLQueryItem(name: "distinct_id", value: flushService.getDistinctId()),
            URLQueryItem(name: "token", value: token),
        ]
        if let encodedQuery = components?.percentEncodedQuery {
            components?.percentEncodedQuery = encodedQuery.replacingOccurrences(of: "+", with: "%2B")
        }
        return components?.url?.absoluteString
    }

    /// - Parameter triggerTimestamp: When the thing that asked for this capture happened —
    ///   a touch's own `UITouch.timestamp`, or `nil` for "now". Used **only** to rate-limit
    ///   against `ReplaySettings.recordInterval`; it is deliberately not what the resulting
    ///   events are stamped with. The frame carries the instant its pixels came off the
    ///   renderer (`RenderedFrame.capturedAtMs`), which is strictly later than the trigger
    ///   by the render duration. Those are two different quantities: the gate asks "has
    ///   enough time passed since we last captured", the event asserts "this is what the
    ///   screen looked like at T". Conflating them back-dated every touch-triggered frame
    ///   to its touch, tying the two events and leaving the service's touch-gated sampler
    ///   to break the tie by sort stability. Android and Flutter stamp at the pixels too.
    func record(_ triggerTimestamp: Int64? = nil) {
        if shouldRecordSession && isScreenDirty() {
            let triggeredAtMs = triggerTimestamp ?? TimestampUtils.timestamp()
            let elapsedTime = triggeredAtMs - MPSessionReplayInstance.lastRecordTimestamp

            if elapsedTime < ReplaySettings.recordInterval {
                return
            }
            MPSessionReplayInstance.lastRecordTimestamp = triggeredAtMs

            MPSessionReplayInstance.recordWorkItem?.cancel()
            MPSessionReplayInstance.recordWorkItem = DispatchWorkItem { [weak self] in
                let startTime = TimestampUtils.timestamp()
                // The screenshot and its `mp_wireframe` are stamped from one instant read at
                // the render, so the pair describes one moment and both report when that
                // moment was on screen.
                if let screenshot = ScreenRecorder.shared.captureScreenshot() {
                    let endTime = TimestampUtils.timestamp()
                    Logger.debug(message: "Time taken to take screenshot - \(endTime - startTime)")
                    // Additional recording check to skip processing screenshot that accidentally got captured due to async processing
                    if self?.isRecording == true {
                        self?.processScreenshot(
                            screenshot.data, timestamp: screenshot.capturedAtMs)
                    }
                }
            }

            if Thread.isMainThread {
                MPSessionReplayInstance.recordWorkItem?.perform()
            } else {
                if let workItem = MPSessionReplayInstance.recordWorkItem {
                    DispatchQueue.main.async(execute: workItem)
                }
            }
        }
    }

    /// - Parameter timestamp: The frame's `RenderedFrame.capturedAtMs`, not the time this
    ///   runs. Publishing hops to a background queue and the encoder sits behind the event
    ///   serial queue, so a publish-time stamp would date the screen to whenever the
    ///   pipeline drained — while touches are accurate at the source. Same reasoning as
    ///   Android's `RawScreenshotEvent.timestamp`.
    func processScreenshot(_ screenshot: Data, timestamp: Int64) {
        _screenIsDirty = false
        // Move event publishing to a background thread
        DispatchQueue.global(qos: .utility).async {
            EventPublisher.shared.publishSessionEvent(
                // TODO: Refactor or cleanup incremental snapshot support, only send full snapshots for now (isInitial: true)
                RawScreenshotEvent(data: screenshot, isInitial: true, timestamp: timestamp)
            )
            Logger.debug(message: "Screenshot published")
        }
    }

    /// Stops the session recording and performs cleanup tasks.
    ///
    /// This method stops recording, clears relevant session state, and uploads pending events.
    public func stopRecording() {
        processStopRecording()
        flushService.flushEvents(forAll: true)
    }

    /// Stop recording and perform the background upload of the pending screenshot events.
    private func stopRecordingOnAppDidEnterBackground() {
        processStopRecording()
        performBackgroundUpload()
    }

    private func processStopRecording() {
        if isRecording == false {
            return
        }
        shouldRecordSession = false
        isRecording = false

        // Disable debug mask overlay
        debugMaskOverlayManager?.disable()

        flushService.stop()
        MPSessionReplaySender.shared.unregister("$mp_replay_id")
        SensitiveViewManager.shared.clearCache()
        Logger.debug(message: "Stopped recording")
    }

    func shouldRecordSessionFor(percent: Double) -> Bool {
        guard percent > 0 && percent <= 100 else {
            return false
        }
        if Double.random(in: 0...100) <= percent {
            return true
        }
        Logger.debug(message: "Session not selected for recording based on sampling rate of \(percent)%")
        return false
    }

    private func performBackgroundUpload() {
        guard let sharedApplication = sharedUIApplication() else {
            return
        }

        let completionHandler: () -> Void = { [weak self] in
            guard let self = self else { return }

            if self.taskId != UIBackgroundTaskIdentifier.invalid {
                sharedApplication.endBackgroundTask(self.taskId)
                self.taskId = UIBackgroundTaskIdentifier.invalid
            }
        }

        taskId = sharedApplication.beginBackgroundTask(expirationHandler: completionHandler)
        flushService.flushEvents(
            forAll: true,
            completionHandler: {
                DispatchQueue.main.async {
                    completionHandler()
                }
            })
    }

    /// Manually flushes all queued session replay events to the server.
    ///
    /// - Parameter completionHandler: A closure that will be called after the flush operation completes.
    ///
    /// Use this method when you want to ensure that all collected events are immediately uploaded,
    /// such as before logging out or SDK re-initialisation
    public func flush(completionHandler: @escaping () -> Void = {}) {
        flushService.flushEvents(forAll: true, completionHandler: completionHandler)
    }

    /// Masks every view that is an instance of `aClass`.
    ///
    /// **Registrations do not survive re-initialization.** `MPSessionReplay.initialize`
    /// deinitializes any previous instance first, and `deinitializeInstance` replaces
    /// `SensitiveViewManager` outright — so registered classes are gone and the incoming config
    /// decides what is masked. Register again after re-initializing.
    ///
    /// This has always been the behaviour here; it was undocumented, and Android used to differ
    /// by keeping registrations. Android now matches (2026-08-26) — a new initialization is a new
    /// initialization on both.
    public func addSensitiveClass(_ aClass: AnyClass) {
        SensitiveViewManager.shared.addSensitiveClass(aClass)
    }

    public func removeSensitiveClass(_ aClass: AnyClass) {
        SensitiveViewManager.shared.removeSensitiveClass(aClass)
    }

    // MARK: - Event Trigger Control

    /// Disables event-triggered recording.
    ///
    /// When disabled, the SDK will ignore events from the Mixpanel SDK that would normally
    /// trigger recording based on configured event triggers. This does not affect
    /// auto start recording and Manual recording using `startRecording()`method.
    ///
    /// - Note: This is a global setting that affects all event triggers of sesion replay.
    /// This setting will be reset to `enabled` on SDK re-initialization.
    public func disableEventTriggers() {
        isEventTriggersEnabled = false
        Logger.info(message: "Event triggers disabled")
    }

    /// Enables event-triggered recording.
    ///
    /// Enables processing of events from the Mixpanel SDK for triggering recording.
    /// Event triggers will evaluate normally after calling this method.
    ///
    /// - Note: Event triggers are enabled by default on SDK initialization.
    public func enableEventTriggers() {
        isEventTriggersEnabled = true
        Logger.info(message: "Event triggers enabled")
    }
}
