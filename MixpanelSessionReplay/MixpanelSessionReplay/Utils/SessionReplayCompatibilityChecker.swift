//
//  SessionReplayCompatibilityChecker.swift
//  MixpanelSessionReplay
//
//  Created by Ketan on 19/12/25.
//  Copyright © 2025 Mixpanel. All rights reserved.
//

import Foundation

/// Represents the compatibility status for session replay functionality
enum SessionReplayCompatibilityStatus {
    case compatible
    case incompatible
    case unclear

    var description: String {
        switch self {
            case .compatible:
                return "Session replay is compatible and can be enabled"
            case .incompatible:
                return "Session replay is incompatible as app is built with Xcode 26+ and running iOS 26+ device"
            case .unclear:
                return "Unable to determine session replay compatibility"
        }
    }
}

struct SessionReplayCompatibilityChecker {

    // MARK: - Dependencies (Injectable for Testing)

    private let xcodeVersionProvider: () -> String?
    private let isiOS26OrLater: () -> Bool

    // MARK: - Shared Instance

    static let shared = SessionReplayCompatibilityChecker()

    // MARK: - Initialization

    init(
        xcodeVersionProvider: @escaping () -> String? = {
            Bundle.main.infoDictionary?["DTXcode"] as? String
        },
        isiOS26OrLater: @escaping () -> Bool = {
            if #available(iOS 26, *) { return true }
            return false
        }
    ) {
        self.xcodeVersionProvider = xcodeVersionProvider
        self.isiOS26OrLater = isiOS26OrLater
    }

    // MARK: - Compatibility Checks

    /// Compatibility based on the Xcode version used to build the app
    private func xcodeCompatibilityStatus() -> SessionReplayCompatibilityStatus {
        guard
            let xcodeVersionString = xcodeVersionProvider(),
            let xcodeVersion = Int(xcodeVersionString)
        else {
            return .unclear
        }

        // DTXcode format: Xcode 16.4 = "1640", Xcode 26.0 = "2600"
        return xcodeVersion >= 2600 ? .incompatible : .compatible
    }

    /// Compatibility based on the running iOS version
    private func iOSCompatibilityStatus() -> SessionReplayCompatibilityStatus {
        return isiOS26OrLater() ? .incompatible : .compatible
    }

    /// Final session replay compatibility considering both Xcode and iOS
    func isCompatible() -> SessionReplayCompatibilityStatus {
        let xcodeStatus = xcodeCompatibilityStatus()
        let iOSStatus = iOSCompatibilityStatus()

        if iOSStatus == .compatible || xcodeStatus == .compatible {
            return .compatible
        }

        // Liquid Glass applies only when both Xcode and iOS are 26+
        return .incompatible
    }

    /// Static convenience method using the shared instance
    static func isCompatible() -> SessionReplayCompatibilityStatus {
        return shared.isCompatible()
    }
}
