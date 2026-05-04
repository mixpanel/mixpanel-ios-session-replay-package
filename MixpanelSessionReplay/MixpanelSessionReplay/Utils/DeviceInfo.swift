//
//  DeviceInfo.swift
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation
import UIKit

struct DeviceInfo {
    static var screenWidth: Int {
        return Int(UIScreen.main.bounds.width)
    }

    static var screenHeight: Int {
        return Int(UIScreen.main.bounds.height)
    }

    static var deviceType: String {
        switch UIDevice.current.userInterfaceIdiom {
            case .pad:
                return "iPad"
            case .phone:
                return "iPhone"
            case .tv:
                return "tvOS"
            default:
                return "Unknown"
        }
    }

    static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let model = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return model
    }

    static var osVersion: String {
        return UIDevice.current.systemVersion
    }

    static var isiOSAppOnMac: Bool {
        if #available(iOS 14.0, macOS 11.0, *) {
            return ProcessInfo.processInfo.isiOSAppOnMac
        }
        return false
    }
}
