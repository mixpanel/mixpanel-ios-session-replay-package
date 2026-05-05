//
//  NetworkTest.swift
//  MixpanelSessionReplayTests
//
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import XCTest

@testable import MixpanelSessionReplay

class NetworkTests: XCTestCase {
    var network: Network!
    var mockSession: URLSession!

    override func setUp() {
        super.setUp()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: configuration)

        network = Network(session: mockSession)
    }

    override func tearDown() {
        network = nil
        mockSession = nil
        super.tearDown()
    }

    func testPerformAPIRequestSuccess() {
        let url = URL(string: EndPoints.defaultRecord)!
        let responseData = "Success".data(using: .utf8)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.requestHandler = { request in
            return (response, responseData, nil)
        }

        let apiRequest = APIRequest(
            endPoint: EndPoints.defaultRecord,
            method: .get,
            requestBody: nil,
            queryItems: nil,
            headers: [:],
            timeoutInterval: nil
        )

        let expectation = self.expectation(description: "Completion handler invoked")

        network.sendRawRequest(apiRequest) { result in
            switch result {
                case .success(_): break
                case .failure(let error):
                    XCTFail("Expected success but got failure with error \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2, handler: nil)
    }

    func testPerformAPIRequestFailureWithError() {
        let error = NSError(
            domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])

        MockURLProtocol.requestHandler = { request in
            return (nil, nil, error)
        }

        let apiRequest = APIRequest(
            endPoint: EndPoints.defaultRecord,
            method: .get,
            requestBody: nil,
            queryItems: nil,
            headers: [:],
            timeoutInterval: nil
        )

        let expectation = self.expectation(description: "Completion handler invoked")

        network.sendRawRequest(apiRequest) { result in
            switch result {
                case .success(let message):
                    XCTFail("Expected failure but got success with message \(message)")
                case .failure(let receivedError):
                    XCTAssertEqual(receivedError.localizedDescription, error.localizedDescription)
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2, handler: nil)
    }

    func testPerformAPIRequestInvalidResponse() {
        let url = URL(string: EndPoints.defaultRecord)!
        let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.requestHandler = { request in
            return (response, nil, nil)
        }

        let apiRequest = APIRequest(
            endPoint: EndPoints.defaultRecord,
            method: .get,
            requestBody: nil,
            queryItems: nil,
            headers: [:],
            timeoutInterval: nil
        )

        let expectation = self.expectation(description: "Completion handler invoked")

        network.sendRawRequest(apiRequest) { result in
            switch result {
                case .success(let message):
                    XCTFail("Expected failure but got success with message \(message)")
                case .failure(let error):
                    XCTAssertEqual(error.localizedDescription, "Invalid status code: 500.")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2, handler: nil)
    }

    func testPerformAPIRequestInvalidURL() {
        network = Network(session: URLSession.shared)

        let apiRequest = APIRequest(
            endPoint: "invalid-url",
            method: .get,
            requestBody: nil,
            queryItems: nil,
            headers: [:],
            timeoutInterval: nil
        )

        let expectation = self.expectation(description: "Completion handler invoked")

        network.sendRawRequest(apiRequest) { result in
            switch result {
                case .success(let message):
                    XCTFail("Expected failure but got success with message \(message)")
                case .failure(let error):
                    XCTAssertEqual(error.localizedDescription, "unsupported URL")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 60, handler: nil)
    }
}
