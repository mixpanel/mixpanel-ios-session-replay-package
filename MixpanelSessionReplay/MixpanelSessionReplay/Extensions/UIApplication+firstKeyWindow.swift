//
//  UIApplication+firstKeyWindow.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import UIKit

extension UIApplication {
    var firstKeyWindow: UIWindow? {
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        let activeScene =
            windowScenes
            .filter { $0.activationState == .foregroundActive }

        let firstActiveScene = activeScene.first
        let keyWindow = firstActiveScene?.windows.first(where: \.isKeyWindow)

        return keyWindow
    }
}
