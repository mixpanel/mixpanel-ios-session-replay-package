//
//  ReplayIdentifiers.swift
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import Foundation
internal import MixpanelSwiftCommon

/// Who a replay is attributed to: either a distinct id passed directly, or an identity and the
/// distinct id derived from it. Kept as one value so a flush never pairs a distinct id with a
/// different identity. Empty identity values are treated as unset, so a replay never sends a key
/// that would resolve to a different user than the app's events.
struct ReplayIdentifiers: Equatable {
    let distinctId: String
    /// Nil for a distinct id passed directly.
    let identity: MixpanelIdentity?

    /// A distinct id passed directly. Requests carry it and no identity keys.
    init(distinctId: String) {
        self.distinctId = distinctId
        self.identity = nil
    }

    /// An identity and the distinct id analytics sends on events for it: the user once identified,
    /// otherwise `$device:` and the device id. Nil when the identity names neither a user nor a
    /// device.
    init?(identity: MixpanelIdentity) {
        if let userId = identity.userId.nonEmpty {
            self.distinctId = userId
        } else if let deviceId = identity.deviceId.nonEmpty {
            self.distinctId = "$device:\(deviceId)"
        } else {
            return nil
        }
        self.identity = identity
    }

    /// Whether a request names its user with `distinct_id`. Not when the identity has both a user
    /// and a company: Mixpanel builds the user from `$user_id` and `$company_id`, as it does for
    /// events, which carry no `distinct_id` either.
    var sendsDistinctId: Bool {
        identity?.userId.nonEmpty == nil || identity?.companyId.nonEmpty == nil
    }

    /// The identity keys Mixpanel resolves a replay's user from.
    var queryItems: [URLQueryItem] {
        guard let identity = identity else { return [] }
        return [
            identity.userId.nonEmpty.map { URLQueryItem(name: "$user_id", value: $0) },
            identity.companyId.nonEmpty.map { URLQueryItem(name: "$company_id", value: $0) },
            identity.deviceId.nonEmpty.map { URLQueryItem(name: "$device_id", value: $0) },
        ].compactMap { $0 }
    }
}

extension Optional where Wrapped == String {
    /// The string, or nil when it's nil or empty.
    var nonEmpty: String? {
        guard let value = self, !value.isEmpty else { return nil }
        return value
    }
}
