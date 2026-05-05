//
//  TouchEventTracker.swift
//  MixpanelSessionReplay
//
//  Created by Jared McFarland on 10/24/24.
//  Copyright © 2024 Mixpanel. All rights reserved.
//

#if os(iOS)
import Foundation
import UIKit

struct TouchEventData {
    var phase: UITouch.Phase
    var location: CGPoint
    var hash: Int
}

struct TouchEventTracker {
    static var initialTouchPoints: [Int: CGPoint] = [:]

    static func detectSwipeDirection(from start: CGPoint, to end: CGPoint)
        -> String
    {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y

        if abs(deltaX) > abs(deltaY) {
            if deltaX > 0 {
                return "right"
            } else {
                return "left"
            }
        } else if abs(deltaY) > abs(deltaX) {
            if deltaY > 0 {
                return "down"
            } else {
                return "up"
            }
        }

        return "right"
    }

    static func processEvent(_ event: UIEvent) {
        let timestamp = TimestampUtils.timestamp()
        guard MPSessionReplay.getInstance()?.isRecording == true else {
            return
        }
        guard event.type == .touches else {
            return
        }
        guard let window = ViewUtils.getCurrentWindow() else {
            return
        }

        // Get the touch events only for the current window
        guard let touches = event.touches(for: window) else { return }

        // As UITouch can be accessed on the main thread, grab the required values from the touch
        // and do the rest processing with that data on the background thread
        let touchEventsData: [TouchEventData] = touches.map { touch in
            return TouchEventData(
                phase: touch.phase,
                location: touch.location(in: window),
                hash: ObjectIdentifier(touch).hashValue)
        }

        DispatchQueue.main.async {
            for touch in touchEventsData {
                switch touch.phase {
                    case .began:
                        MPSessionReplay.getInstance()?.debugMaskOverlayManager?.enableTransitioningState()

                        MPSessionReplay.getInstance()?.record(
                            timestamp)
                        TouchEventTracker.initialTouchPoints[touch.hash] =
                            touch.location
                    case .ended, .cancelled:
                        MPSessionReplay.getInstance()?.record(
                            timestamp)

                        let touchStartPoint =
                            TouchEventTracker.initialTouchPoints.removeValue(
                                forKey: touch.hash) ?? CGPoint.zero
                        let isSwipe =
                            touchStartPoint.distance(to: touch.location)
                            > TouchInteraction.swipeDistanceThreshold
                        let direction =
                            isSwipe
                            ? TouchEventTracker.detectSwipeDirection(
                                from: touchStartPoint, to: touch.location)
                            : nil
                        let rawEvent = RawTouchEvent(
                            start: touchStartPoint, end: touch.location,
                            isSwipe: isSwipe, direction: direction,
                            timestamp: timestamp)
                        EventPublisher.shared.publishTouchEvent(rawEvent)
                    default:
                        break
                }
            }
        }
    }
}
#endif

extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        return hypot(point.x - x, point.y - y)
    }
}
