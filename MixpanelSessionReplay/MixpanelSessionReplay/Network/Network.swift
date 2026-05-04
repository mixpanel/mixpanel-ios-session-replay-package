//
//  Network.swift
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation

enum RequestMethod: String {
    case get
    case post
}

struct APIRequest {
    let endPoint: String
    let method: RequestMethod
    let requestBody: Data?
    let queryItems: [URLQueryItem]?
    let headers: [String: String]
    let timeoutInterval: TimeInterval?
}

class Network {
    private var session: URLSession

    init(session: URLSession = URLSession.shared) {
        self.session = session
    }

    /// Sends a network request and decodes the response into the specified `Decodable` type.
    ///
    /// This method performs an HTTP request using the provided `APIRequest` and attempts to decode
    /// the JSON response into the specified model type `T`. The result is returned via the completion handler.
    ///
    /// - Parameters:
    ///   - apiRequest: The API request configuration containing endpoint, method, headers, etc.
    ///   - responseType: The type to decode the JSON response into. Must conform to `Decodable`.
    ///   - completion: A closure called upon completion with either the decoded response object or an error.
    ///
    /// - Returns: Nothing directly. Use the `completion` handler to retrieve the result.
    ///
    /// - Note: Use this method when the API response conforms to a known Codable model.
    func sendDecodableRequest<T: Decodable>(
        _ apiRequest: APIRequest, responseType: T.Type, completion: @escaping (Result<T, Error>) -> Void
    ) {
        // Debug logging for 400 error
        Logger.debug(message: "[Network] performAPIRequest called for \(apiRequest.endPoint)")
        Logger.debug(message: "[Network] Method: \(apiRequest.method.rawValue)")
        if let queryItems = apiRequest.queryItems {
            Logger.debug(
                message:
                    "[Network] Query Parameters: \(queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&"))"
            )
        }
        if !apiRequest.headers.isEmpty {
            Logger.debug(message: "[Network] Headers: \(apiRequest.headers)")
        }

        sendRawRequest(apiRequest) { result in
            switch result {
                case .success((let data, _)):
                    guard let data = data else {
                        let error = NSError(
                            domain: NetworkError.domain, code: NetworkError.invalidResponseCode,
                            userInfo: [NSLocalizedDescriptionKey: "No data received."])
                        completion(.failure(error))
                        return
                    }

                    do {
                        let decodedResponse = try JSONDecoder().decode(T.self, from: data)
                        completion(.success(decodedResponse))
                    } catch {
                        Logger.error(message: "[Network] Failed to decode response: \(error)")
                        if let responseString = String(data: data, encoding: .utf8) {
                            Logger.debug(message: "[Network] Response body: \(responseString)")
                        }
                        completion(.failure(error))
                    }
                case .failure(let error):
                    completion(.failure(error))
            }
        }
    }

    /// Sends a network request and returns the raw response data and HTTP response.
    ///
    /// This method performs an HTTP request using the provided `APIRequest` configuration and
    /// returns the optional raw `Data` and associated `HTTPURLResponse` through a completion handler.
    ///
    /// - Parameters:
    ///   - apiRequest: The API request configuration containing endpoint, method, headers, etc.
    ///   - completion: A closure called upon completion with either the raw response data and
    ///                 HTTPURLResponse or an error.
    ///
    /// - Note: Use this method when you want to handle the raw response manually, without decoding.
    func sendRawRequest(
        _ apiRequest: APIRequest, completion: @escaping (Result<(Data?, HTTPURLResponse), Error>) -> Void
    ) {
        guard let request = buildURLRequest(apiRequest) else {
            let error = NSError(
                domain: NetworkError.domain, code: NetworkError.invalidRequestCode,
                userInfo: [NSLocalizedDescriptionKey: "Invalid request."])
            completion(.failure(error))
            return
        }

        // Log the final URL being requested (for debugging)
        if let url = request.url {
            Logger.debug(message: "[Network] Final URL: \(url.absoluteString)")
        }

        var hasCompleted = false
        let completionQueue = DispatchQueue(label: "com.mixpanel.network.completion")

        let safeCompletion: (Result<(Data?, HTTPURLResponse), Error>) -> Void = { result in
            completionQueue.sync {
                guard !hasCompleted else { return }
                hasCompleted = true
                completion(result)
            }
        }

        let task = session.dataTask(with: request) { (data, response, error) in
            if let error = error {
                safeCompletion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = NSError(
                    domain: NetworkError.domain, code: NetworkError.invalidResponseCode,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response."])
                safeCompletion(.failure(error))
                return
            }

            guard httpResponse.statusCode == 200 else {
                // Log response details for debugging
                Logger.error(message: "[Network] HTTP Error: Status code \(httpResponse.statusCode)")
                if let data = data, let responseBody = String(data: data, encoding: .utf8) {
                    Logger.debug(message: "[Network] Response body: \(responseBody)")
                }
                let error = NSError(
                    domain: NetworkError.domain, code: NetworkError.invalidResponseCode,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid status code: \(httpResponse.statusCode)."])
                safeCompletion(.failure(error))
                return
            }

            safeCompletion(.success((data, httpResponse)))
        }

        // Add timeout handler if specified
        if let timeout = apiRequest.timeoutInterval {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak task] in
                guard let task = task, task.state == .running else { return }
                task.cancel()
                let timeoutError = NSError(
                    domain: NetworkError.domain,
                    code: NetworkError.timeoutErrorCode,
                    userInfo: [NSLocalizedDescriptionKey: "Request timed out after \(timeout) seconds."])
                safeCompletion(.failure(timeoutError))
            }
        }

        task.resume()
    }

    private func buildURLRequest(_ apiRequest: APIRequest) -> URLRequest? {
        guard let url = buildURL(apiRequest) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = apiRequest.method.rawValue
        request.httpBody = apiRequest.requestBody
        if let timeout = apiRequest.timeoutInterval {
            request.timeoutInterval = timeout
        }

        for (k, v) in apiRequest.headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        return request as URLRequest
    }

    private func buildURL(_ apiRequest: APIRequest) -> URL? {
        guard var components = URLComponents(string: apiRequest.endPoint) else {
            return nil
        }
        components.queryItems = apiRequest.queryItems
        // adding workaround to replace + for %2B as it's not done by default within URLComponents
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(
            of: "+", with: "%2B")
        return components.url
    }
}
