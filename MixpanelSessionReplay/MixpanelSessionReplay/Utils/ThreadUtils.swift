//
//  ThreadUtils.swift
//  MixpanelSessionReplay
//
//  Created by Ketan on 22/05/25.
//
import Foundation

struct ThreadUtils {
    /// Executes a given closure on the main thread.
    ///
    /// - Parameters:
    ///   - async: Default is `true`. If `true`, the closure is dispatched asynchronously when not on the main thread.
    ///            If `false`, it is dispatched synchronously.
    ///   - block: The closure to execute on the main thread.
    ///
    /// If already on the main thread, the closure is executed immediately regardless of the `async` value.
    ///
    /// ### Usage:
    /// ```swift
    /// ThreadUtils.runOnMainThread() {
    ///     // Code that must run on the main thread
    /// }
    /// ```
    static func runOnMainThread(async: Bool = true, _ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            if async {
                DispatchQueue.main.async {
                    block()
                }
            } else {
                DispatchQueue.main.sync {
                    block()
                }
            }
        }
    }
}
