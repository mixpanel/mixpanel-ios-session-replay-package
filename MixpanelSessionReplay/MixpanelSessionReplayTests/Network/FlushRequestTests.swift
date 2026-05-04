//
//  FlushRequestTests.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

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

    func testSendRequestNotAllowedDueToExponentialBackoff() {
        flushRequest.networkRequestsAllowedAfterTime = Date().timeIntervalSince1970 + 1000
        mockNetwork.sendRawRequestStub = { _ in
            return .success((self.responseData, self.httpresponse))
        }
        let payloadInfo = PayloadInfo(
            sessionEvents: [], batchStartTime: 1, seq: 1, replayId: "test", replayLengthMs: 1,
            replayStartTime: 1)
        let result = flushRequest.sendRequest(payloadInfo: payloadInfo)

        XCTAssertFalse(result)
        XCTAssertEqual(flushRequest.networkConsecutiveFailures, 0)
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
        var result = flushRequest.sendRequest(payloadInfo: payloadInfo)
        XCTAssertFalse(result)
        XCTAssertEqual(flushRequest.networkConsecutiveFailures, 4)

        // The requests are blocked for the given networkRequestsAllowedAfterTime time
        result = flushRequest.sendRequest(payloadInfo: payloadInfo)
        XCTAssertFalse(result)
        XCTAssertEqual(flushRequest.networkConsecutiveFailures, 4)
    }
}
