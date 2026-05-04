//
//  Event.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation

struct RawTouchEvent {
    var start: CGPoint
    var end: CGPoint
    var isSwipe: Bool
    var direction: String?
    var timestamp: Int64
}

struct RawScreenshotEvent {
    var data: Data
    var isInitial: Bool  // is initial screenshot
    var timestamp: Int64
}
