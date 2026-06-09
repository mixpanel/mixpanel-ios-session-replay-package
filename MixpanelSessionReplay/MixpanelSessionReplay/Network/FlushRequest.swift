//
//  FlushRequest.swift
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation

class FlushRequest {
    var networkRequestsAllowedAfterTime = 0.0
    var networkConsecutiveFailures = 0
    private let token: String
    let distinctId: String
    private var headers: [String: String] = [:]
    private let network: Network
    private let recordApiUrl: String

    init(
        token: String, distinctId: String, network: Network = Network(),
        serverURL: String = DataResidency.us
    ) {
        self.token = token
        self.distinctId = distinctId
        self.recordApiUrl = MPSessionReplayAPI.recordEndpoint(for: serverURL)

        if let data = "\(token):".data(using: .utf8) {
            headers["Authorization"] = "Basic \(data.base64EncodedString())"
            headers["Content-Type"] = "application/octet-stream"
        }
        self.network = network
    }

    func sendRequest(payloadInfo: PayloadInfo) -> Bool {
        if requestNotAllowed() {
            Logger.warn(message: "Request not allowed due to exponential backoff. Will retry later.")
            return false
        }

        guard let requestJSONString = MPSessionReplayEncoder.jsonPayload(payloadInfo: payloadInfo)
        else {
            return false
        }

        var requestResult = false
        if let requestDataRaw = requestJSONString.data(using: .utf8) {
            do {
                let requestDataZip = try requestDataRaw.gzipCompressed()
                let request = APIRequest(
                    endPoint: recordApiUrl, method: .post, requestBody: requestDataZip,
                    queryItems: buildQueryItems(payloadInfo: payloadInfo), headers: headers, timeoutInterval: nil)

                let semaphore = DispatchSemaphore(value: 0)
                network.sendRawRequest(request) { result in
                    defer { semaphore.signal() }

                    switch result {
                        case .success(_):
                            self.networkConsecutiveFailures = 0
                            self.updateRetryDelay()
                            requestResult = true
                            Logger.info(message: "Replay batch was ingested successfully")
                        case .failure(let error):
                            Logger.warn(message: "Server error: \(error.localizedDescription)")
                            self.networkConsecutiveFailures += 1
                            self.updateRetryDelay()
                    }
                }
                _ = semaphore.wait(timeout: .now() + 30.0)
            } catch {
                Logger.error(message: "Gzip compression failed with error: \(error)")
            }
        } else {
            Logger.warn(message: "UTF-8 data conversion failed")
        }
        return requestResult
    }

    private func buildQueryItems(payloadInfo: PayloadInfo) -> [URLQueryItem] {
        return [
            URLQueryItem(name: "format", value: "gzip"),
            URLQueryItem(name: "distinct_id", value: distinctId),
            URLQueryItem(name: "seq", value: String(payloadInfo.seq)),
            URLQueryItem(name: "batch_start_time", value: String(payloadInfo.batchStartTime)),
            URLQueryItem(name: "replay_id", value: payloadInfo.replayId),
            URLQueryItem(name: "replay_length_ms", value: String(payloadInfo.replayLengthMs)),
            URLQueryItem(name: "replay_start_time", value: String(payloadInfo.replayStartTime)),
            URLQueryItem(name: "$lib_version", value: APIConstants.currentLibVersion),
            URLQueryItem(name: "mp_lib", value: APIConstants.currentMpLib),
        ]
    }

    private func updateRetryDelay() {
        var retryTime = 0.0

        if networkConsecutiveFailures >= APIConstants.failuresTillBackoff {
            retryTime = max(
                retryTime,
                retryBackOffTimeWithConsecutiveFailures(networkConsecutiveFailures))
        }
        let retryDate = Date(timeIntervalSinceNow: retryTime)
        networkRequestsAllowedAfterTime = retryDate.timeIntervalSince1970
    }

    private func retryBackOffTimeWithConsecutiveFailures(_ failureCount: Int) -> TimeInterval {
        let time = pow(2.0, Double(failureCount) - 1) * 60 + Double(arc4random_uniform(30))
        return min(
            max(APIConstants.minRetryBackoff, time),
            APIConstants.maxRetryBackoff)
    }

    private func requestNotAllowed() -> Bool {
        let currentTime = Date().timeIntervalSince1970
        let timeRemaining = networkRequestsAllowedAfterTime - currentTime

        if timeRemaining > 0 {
            Logger.warn(
                message:
                    "Request not allowed. Time remaining until requests are allowed: \(timeRemaining) seconds."
            )
            return true
        }

        return false
    }

}
