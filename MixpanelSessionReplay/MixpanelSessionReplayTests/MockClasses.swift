//
//  MockClasses.swift
//  MixpanelSessionReplay
//
//  Created by Ketan on 03/03/25.
//  Copyright © 2025 Mixpanel. All rights reserved.
//

import Foundation
import XCTest

@testable import MixpanelSessionReplay

class MockFlushRequest: FlushRequest {
    var sendRequestCalled = false
    var sendRequestSuccess = true

    override func sendRequest(payloadInfo: PayloadInfo) -> Bool {
        sendRequestCalled = true
        return sendRequestSuccess
    }
}

class MockNetworkMonitor: NetworkMonitoring {
    var isUsingWiFiOverride: Bool = true

    var isUsingWiFi: Bool {
        return isUsingWiFiOverride
    }
}

class MockFlushService: FlushService {
    var startCalled = false
    var stopCalled = false
    var flushEventsForAllCalled = false

    override func start() {
        startCalled = true
    }

    override func stop() {
        stopCalled = true
    }

    override func flushEvents(forAll: Bool = false, completionHandler: @escaping () -> Void = {}) {
        flushEventsForAllCalled = true
        completionHandler()
    }
}

class MockEventService: EventService {
    var clearEventsCalled = false
    var enqueueEventCalled = false

    // Optional expectation for async testing
    var enqueueEventExpectation: XCTestExpectation?

    override func clearEvents() {
        clearEventsCalled = true
    }

    override func enqueueEvent(_ event: SessionEvent) {
        enqueueEventCalled = true

        // Fulfill expectation if set (then clear to prevent multiple fulfillments)
        if let expectation = enqueueEventExpectation {
            expectation.fulfill()
            enqueueEventExpectation = nil
        }
    }
}

class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) -> (HTTPURLResponse?, Data?, Error?))?

    override class func canInit(with request: URLRequest) -> Bool { return true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { return request }

    override func startLoading() {
        guard MockURLProtocol.requestHandler != nil else {
            // If the test finished already, just tell the client we're done or failed
            self.client?.urlProtocol(
                self, didFailWithError: NSError(domain: "MockURLProtocol", code: -1, userInfo: nil))
            return
        }
        // 1. Move the handler check inside the block
        // 2. Use a high-priority background queue to avoid Main Thread contention
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self, let handler = MockURLProtocol.requestHandler else {
                return
            }

            let (response, data, error) = handler(self.request)

            if let error = error {
                self.client?.urlProtocol(self, didFailWithError: error)
            } else {
                if let response = response {
                    self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                }
                if let data = data {
                    self.client?.urlProtocol(self, didLoad: data)
                }
                self.client?.urlProtocolDidFinishLoading(self)
            }
        }
    }

    override func stopLoading() {}
}

// MARK: - MockNetwork

class MockNetwork: Network {
    // Stubs for each method - caller sets these before invoking
    var sendRawRequestStub: ((APIRequest) -> Result<(Data?, HTTPURLResponse), Error>)?

    var responseJson: String?
    override func sendRawRequest(
        _ apiRequest: APIRequest,
        completion: @escaping (Result<(Data?, HTTPURLResponse), Error>) -> Void
    ) {
        // Call stub synchronously
        if let stub = sendRawRequestStub {
            let result = stub(apiRequest)
            completion(result)
        } else if let json = responseJson {
            if let data = json.data(using: .utf8) {
                let response = HTTPURLResponse(
                    url: URL(string: "https://test.com")!,
                    statusCode: 200,
                    httpVersion: nil, headerFields: [:]
                )
                //return data from here so that the sendDecodableRequest can decode it without needing to set up a separate stub for sendDecodableRequest
                completion(.success((data, response!)))

            }
        } else {
            fatalError("MockNetwork: sendRawRequestStub not set")
        }

    }

    // Helper method to reset mock state between tests
    func reset() {
        sendRawRequestStub = nil
        responseJson = nil
    }
}
