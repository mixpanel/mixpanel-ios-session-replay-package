//
//  ReadWriteLock.swift
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation

class ReadWriteLock {
    private let concurrentQueue: DispatchQueue

    init(label: String) {
        concurrentQueue = DispatchQueue(
            label: label, qos: .utility, attributes: .concurrent, autoreleaseFrequency: .workItem)
    }

    func read(closure: () -> Void) {
        concurrentQueue.sync {
            closure()
        }
    }
    func write(closure: () -> Void) {
        concurrentQueue.sync(
            flags: .barrier,
            execute: {
                closure()
            })
    }
}
