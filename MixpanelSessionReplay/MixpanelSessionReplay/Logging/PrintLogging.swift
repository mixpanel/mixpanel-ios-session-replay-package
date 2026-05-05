//
//  PrintLogging.swift
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation

/// Simply formats and prints the object by calling `print`
class PrintLogging: Logging {
    static let shared = PrintLogging()
    private init() {}

    func addMessage(message: LogMessage) {
        print(
            "[Mixpanel Session Replay - \(message.file) - func \(message.function)] (\(message.level.rawValue)) - \(message.text)"
        )
    }

    /// Helper method for simplified logging
    func log(_ level: LogLevel, _ message: String, file: String = #file, function: String = #function) {
        let logMessage = LogMessage(path: file, function: function, text: message, level: level)
        addMessage(message: logMessage)
    }
}

/// Simply formats and prints the object by calling `debugPrint`, this makes things a bit easier if you
/// need to print data that may be quoted for instance.
class PrintDebugLogging: Logging {
    static let shared = PrintDebugLogging()
    private init() {}

    func addMessage(message: LogMessage) {
        debugPrint(
            "[Mixpanel Session Replay - \(message.file) - func \(message.function)] (\(message.level.rawValue)) - \(message.text)"
        )
    }

    /// Helper method for simplified logging
    func log(_ level: LogLevel, _ message: String, file: String = #file, function: String = #function) {
        let logMessage = LogMessage(path: file, function: function, text: message, level: level)
        addMessage(message: logMessage)
    }
}
