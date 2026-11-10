//
//  FlushRequestTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import MixpanelSwiftCommon
import XCTest

@testable import MixpanelSessionReplay

final class FlushRequestTests: XCTestCase {
    var flushRequest: FlushRequest!
    var mockNetwork: MockNetwork!
    var responseData: Data!
    var httpresponse: HTTPURLResponse!

    override func setUp() {
        super.setUp()
        mockNetwork = MockNetwork()
        flushRequest = FlushRequest(
            token: "testToken", distinctId: "testDistinctId", network: mockNetwork)
        responseData = Data()
        httpresponse = HTTPURLResponse(
            url: URL(string: "https://test.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    override func tearDown() {
        flushRequest = nil
        mockNetwork = nil
        super.tearDown()
    }

    func testSendRequestSuccess() {
        mockNetwork.sendRawRequestStub = { _ in
            return .success((self.responseData, self.httpresponse))
        }
        let payloadInfo = PayloadInfo(
            sessionEvents: [], batchStartTime: 1, seq: 1, replayId: "test", replayLengthMs: 1,
            replayStartTime: 1)

        let result = flushRequest.sendRequest(payloadInfo: payloadInfo)
        XCTAssertTrue(result)
        XCTAssertEqual(flushRequest.networkConsecutiveFailures, 0)
    }

    func testSendRequestFailure() {
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        mockNetwork.sendRawRequestStub = { _ in
            return .failure(error)
        }
        let payloadInfo = PayloadInfo(
            sessionEvents: [], batchStartTime: 1, seq: 1, replayId: "test", replayLengthMs: 1,
            replayStartTime: 1)

        let result = flushRequest.sendRequest(payloadInfo: payloadInfo)
        XCTAssertFalse(result)
        XCTAssertEqual(flushRequest.networkConsecutiveFailures, 1)
    }

    func testSendRequestConsecutiveFailures() {
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        mockNetwork.sendRawRequestStub = { _ in
            return .failure(error)
        }
        let payloadInfo = PayloadInfo(
            sessionEvents: [], batchStartTime: 1, seq: 1, replayId: "test", replayLengthMs: 1,
            replayStartTime: 1)
        flushRequest.networkConsecutiveFailures = 3
        let result = flushRequest.sendRequest(payloadInfo: payloadInfo)
        XCTAssertFalse(result)
        XCTAssertEqual(flushRequest.networkConsecutiveFailures, 4)
    }

    // MARK: - Identity query items

    /// Sends one batch through `request` and returns the query items it was sent with.
    private func sentQueryItems(_ request: FlushRequest) -> [URLQueryItem] {
        var sent: [URLQueryItem] = []
        mockNetwork.sendRawRequestStub = { apiRequest in
            sent = apiRequest.queryItems ?? []
            return .success((self.responseData, self.httpresponse))
        }
        let payloadInfo = PayloadInfo(
            sessionEvents: [], batchStartTime: 1, seq: 2, replayId: "replay", replayLengthMs: 3,
            replayStartTime: 4)
        XCTAssertTrue(request.sendRequest(payloadInfo: payloadInfo))
        return sent
    }

    private func expectedBaseQueryItems(distinctId: String?) -> [URLQueryItem] {
        return [
            URLQueryItem(name: "format", value: "gzip"),
            distinctId.map { URLQueryItem(name: "distinct_id", value: $0) },
            URLQueryItem(name: "seq", value: "2"),
            URLQueryItem(name: "batch_start_time", value: "1.0"),
            URLQueryItem(name: "replay_id", value: "replay"),
            URLQueryItem(name: "replay_length_ms", value: "3"),
            URLQueryItem(name: "replay_start_time", value: "4.0"),
            URLQueryItem(name: "$lib_version", value: APIConstants.currentLibVersion),
            URLQueryItem(name: "mp_lib", value: APIConstants.currentMpLib),
        ].compactMap { $0 }
    }

    func testQueryItems_DistinctIdOnly_Unchanged() {
        XCTAssertEqual(sentQueryItems(flushRequest), expectedBaseQueryItems(distinctId: "testDistinctId"))
        XCTAssertNil(flushRequest.identifiers.identity)
    }

    func testQueryItems_HierarchicalGroupsIdentitySendsNoDistinctId() {
        let identity = MixpanelIdentity(userId: "user_123", companyId: "acme", deviceId: "device-1")
        let request = FlushRequest(
            token: "testToken", distinctId: "user_123", identity: identity, network: mockNetwork)

        XCTAssertEqual(
            sentQueryItems(request),
            expectedBaseQueryItems(distinctId: nil) + [
                URLQueryItem(name: "$user_id", value: "user_123"),
                URLQueryItem(name: "$company_id", value: "acme"),
                URLQueryItem(name: "$device_id", value: "device-1"),
            ])
    }

    func testQueryItems_UserOnlyIdentity() {
        let identity = MixpanelIdentity(userId: "user_123", companyId: "", deviceId: nil)
        let request = FlushRequest(
            token: "testToken", distinctId: "user_123", identity: identity, network: mockNetwork)

        XCTAssertEqual(
            sentQueryItems(request),
            expectedBaseQueryItems(distinctId: "user_123") + [URLQueryItem(name: "$user_id", value: "user_123")])
    }

    func testQueryItems_CompanyWithoutUserSendsDistinctId() {
        let identity = MixpanelIdentity(userId: nil, companyId: "acme", deviceId: "device-1")
        let request = FlushRequest(
            token: "testToken", distinctId: "$device:device-1", identity: identity, network: mockNetwork)

        XCTAssertEqual(
            sentQueryItems(request),
            expectedBaseQueryItems(distinctId: "$device:device-1") + [
                URLQueryItem(name: "$company_id", value: "acme"),
                URLQueryItem(name: "$device_id", value: "device-1"),
            ])
    }

    func testQueryItems_DeviceOnlyIdentity() {
        let identity = MixpanelIdentity(userId: nil, companyId: nil, deviceId: "device-1")
        let request = FlushRequest(
            token: "testToken", distinctId: "$device:device-1", identity: identity, network: mockNetwork)

        XCTAssertEqual(
            sentQueryItems(request),
            expectedBaseQueryItems(distinctId: "$device:device-1") + [
                URLQueryItem(name: "$device_id", value: "device-1")
            ])
    }

    func testReplayIdentityDistinctId() {
        XCTAssertEqual(ReplayIdentity.distinctId(MixpanelIdentity(userId: "u", companyId: nil, deviceId: "d")), "u")
        XCTAssertEqual(ReplayIdentity.distinctId(MixpanelIdentity(userId: "", companyId: nil, deviceId: "d")), "$device:d")
        XCTAssertEqual(ReplayIdentity.distinctId(MixpanelIdentity(userId: nil, companyId: nil, deviceId: "d")), "$device:d")
        XCTAssertNil(ReplayIdentity.distinctId(MixpanelIdentity(userId: nil, companyId: "acme")))
        XCTAssertNil(ReplayIdentity.distinctId(MixpanelIdentity(userId: "", companyId: "acme", deviceId: "")))
    }
}
