//
//  TimestampUtils.swift
//  MixpanelSessionReplay
//
//  Created by Jared McFarland on 10/25/24.
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation

struct TimestampUtils {
    static func timestamp() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }

    static func timeIntervalToMs(_ timeInterval: TimeInterval) -> Int64 {
        return Int64(timeInterval * 1000)
    }

    static func convertTouchTimestamp(_ touchTimestamp: TimeInterval) -> Int64 {
        // UITouch.timestamp is the time since system boot time
        let bootTime = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        return timeIntervalToMs(bootTime + touchTimestamp)
    }

}
