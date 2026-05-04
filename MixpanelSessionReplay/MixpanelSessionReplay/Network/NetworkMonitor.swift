//
//  NetworkMonitor.swift
//  MixpanelSessionReplay
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Network

protocol NetworkMonitoring {
    var isUsingWiFi: Bool { get }
}

class NetworkMonitor: NetworkMonitoring {
    static let shared = NetworkMonitor()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue.global(qos: .background)
    var isConnected: Bool = false
    var isUsingWiFi: Bool = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
            self?.isUsingWiFi = path.usesInterfaceType(.wifi)

            if let isConnected = self?.isConnected, let isUsingWiFi = self?.isUsingWiFi {
                Logger.debug(message: "Internet Connected: \(isConnected), Using WiFi: \(isUsingWiFi)")
            }
        }
        monitor.start(queue: queue)
    }
}
