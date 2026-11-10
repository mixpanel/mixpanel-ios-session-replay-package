//
//  FlushRequest.swift
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation
internal import MixpanelSwiftCommon

/// How a `MixpanelIdentity` reaches the record endpoint. Empty values are treated as unset, so a
/// replay never sends a key that would resolve to a different user than the app's events.
enum ReplayIdentity {
    /// The distinct id analytics sends on events for this identity: the user once identified,
    /// otherwise `$device:` and the device id. Nil when the identity names neither.
    static func distinctId(_ identity: MixpanelIdentity) -> String? {
        if let userId = nonEmpty(identity.userId) {
            return userId
        }
        if let deviceId = nonEmpty(identity.deviceId) {
            return "$device:\(deviceId)"
        }
        return nil
    }

    /// Whether a request names its user with `distinct_id`. Not when the identity has both a user
    /// and a company: Mixpanel builds the user from `$user_id` and `$company_id`, as it does for
    /// events, which carry no `distinct_id` either.
    static func sendsDistinctId(_ identity: MixpanelIdentity?) -> Bool {
        nonEmpty(identity?.userId) == nil || nonEmpty(identity?.companyId) == nil
    }

    /// The identity keys Mixpanel resolves a replay's user from.
    static func queryItems(_ identity: MixpanelIdentity?) -> [URLQueryItem] {
        guard let identity = identity else { return [] }
        return [
            nonEmpty(identity.userId).map { URLQueryItem(name: "$user_id", value: $0) },
            nonEmpty(identity.companyId).map { URLQueryItem(name: "$company_id", value: $0) },
            nonEmpty(identity.deviceId).map { URLQueryItem(name: "$device_id", value: $0) },
        ].compactMap { $0 }
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let value = value, !value.isEmpty else { return nil }
        return value
    }
}

/// Who a replay is attributed to: either a distinct id passed directly, or an identity and the
/// distinct id derived from it. Kept as one value so a flush never pairs a distinct id with a
/// different identity.
struct ReplayIdentifiers: Equatable {
    let distinctId: String
    /// Nil for a distinct id passed directly.
    let identity: MixpanelIdentity?

    /// A distinct id passed directly. Requests carry it and no identity keys.
    init(distinctId: String) {
        self.distinctId = distinctId
        self.identity = nil
    }

    /// An identity and the distinct id analytics sends for it. Nil when the identity names neither
    /// a user nor a device.
    init?(identity: MixpanelIdentity) {
        guard let distinctId = ReplayIdentity.distinctId(identity) else { return nil }
        self.distinctId = distinctId
        self.identity = identity
    }
}

class FlushRequest {
    var networkRequestsAllowedAfterTime = 0.0
    var networkConsecutiveFailures = 0
    private let token: String
    let identifiers: ReplayIdentifiers
    var distinctId: String { identifiers.distinctId }
    private var headers: [String: String] = [:]
    private let network: Network
    private let recordApiUrl: String

    convenience init(
        token: String, distinctId: String, network: Network = Network(), serverURL: String = DataResidency.us
    ) {
        self.init(
            token: token, identifiers: ReplayIdentifiers(distinctId: distinctId), network: network,
            serverURL: serverURL)
    }

    init(
        token: String, identifiers: ReplayIdentifiers, network: Network = Network(),
        serverURL: String = DataResidency.us
    ) {
        self.token = token
        self.identifiers = identifiers
        self.recordApiUrl = MPSessionReplayAPI.recordEndpoint(for: serverURL)

        if let data = "\(token):".data(using: .utf8) {
            headers["Authorization"] = "Basic \(data.base64EncodedString())"
            headers["Content-Type"] = "application/octet-stream"
        }
        self.network = network
    }

    func sendRequest(payloadInfo: PayloadInfo) -> Bool {
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
        let current = payloadInfo.identifiers ?? identifiers
        return [
            URLQueryItem(name: "format", value: "gzip"),
            ReplayIdentity.sendsDistinctId(current.identity)
                ? URLQueryItem(name: "distinct_id", value: current.distinctId) : nil,
            URLQueryItem(name: "seq", value: String(payloadInfo.seq)),
            URLQueryItem(name: "batch_start_time", value: String(payloadInfo.batchStartTime)),
            URLQueryItem(name: "replay_id", value: payloadInfo.replayId),
            URLQueryItem(name: "replay_length_ms", value: String(payloadInfo.replayLengthMs)),
            URLQueryItem(name: "replay_start_time", value: String(payloadInfo.replayStartTime)),
            URLQueryItem(name: "$lib_version", value: APIConstants.currentLibVersion),
            URLQueryItem(name: "mp_lib", value: APIConstants.currentMpLib),
        ].compactMap { $0 } + ReplayIdentity.queryItems(current.identity)
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

    func requestNotAllowed() -> Bool {
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
