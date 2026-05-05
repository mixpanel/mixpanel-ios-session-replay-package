//
//  RecordingEventTrigger.swift
//  MixpanelSessionReplay
//
//  Created by Mixpanel on 2026-03-03.
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import Foundation

/// Represents a single event trigger configuration from remote settings API.
///
/// Event triggers specify when to start session replay recording based on tracked events.
/// Each trigger contains a sampling percentage and optional property filters (JSONLogic expressions)
/// that are evaluated when matching events occur in the main Mixpanel SDK.
///
/// ## Structure
/// - `percentage`: Sampling rate (0-100) for how often recording should start when triggered
/// - `propertyFilters`: Optional JSONLogic expression to filter events by their properties
///
/// ## Example JSON
/// ```json
/// {
///   "percentage": 50,
///   "property_filters": {
///     "==": [{"var": "plan_type"}, "premium"]
///   }
/// }
/// ```
public struct RecordingEventTrigger: Codable {
    /// Sampling percentage (0-100). Required.
    public let percentage: Double

    /// Optional JSONLogic expression for property filtering
    public let propertyFilters: [String: Any]?

    enum CodingKeys: String, CodingKey {
        case percentage
        case propertyFilters = "property_filters"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        percentage = try container.decode(Double.self, forKey: .percentage)

        // Decode JSON object as [String: Any]
        if container.contains(.propertyFilters) {
            let nestedContainer = try container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .propertyFilters)
            propertyFilters = try nestedContainer.decode()
        } else {
            propertyFilters = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(percentage, forKey: .percentage)

        if let propertyFilters = propertyFilters {
            var nestedContainer = container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .propertyFilters)
            try nestedContainer.encode(propertyFilters)
        }
    }

    public init(percentage: Double, propertyFilters: [String: Any]? = nil) {
        self.percentage = percentage
        self.propertyFilters = propertyFilters
    }
}

// MARK: - Helper for dynamic coding keys

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

// MARK: - Nested container helpers

extension KeyedDecodingContainer where K == AnyCodingKey {
    func decode() throws -> [String: Any] {
        var dict = [String: Any]()

        for key in allKeys {
            if let value = try? decode(String.self, forKey: key) {
                dict[key.stringValue] = value
            } else if let value = try? decode(Int.self, forKey: key) {
                dict[key.stringValue] = value
            } else if let value = try? decode(Double.self, forKey: key) {
                dict[key.stringValue] = value
            } else if let value = try? decode(Bool.self, forKey: key) {
                dict[key.stringValue] = value
            } else if let nestedDict = try? nestedContainer(keyedBy: AnyCodingKey.self, forKey: key).decode() {
                dict[key.stringValue] = nestedDict
            } else if var nestedArray = try? nestedUnkeyedContainer(forKey: key) {
                dict[key.stringValue] = try nestedArray.decodeArray()
            }
        }

        return dict
    }
}

extension UnkeyedDecodingContainer {
    mutating func decodeArray() throws -> [Any] {
        var array = [Any]()

        while !isAtEnd {
            if let value = try? decode(String.self) {
                array.append(value)
            } else if let value = try? decode(Int.self) {
                array.append(value)
            } else if let value = try? decode(Double.self) {
                array.append(value)
            } else if let value = try? decode(Bool.self) {
                array.append(value)
            } else if let nestedDict = try? nestedContainer(keyedBy: AnyCodingKey.self).decode() {
                array.append(nestedDict)
            } else if var nestedArray = try? nestedUnkeyedContainer() {
                array.append(try nestedArray.decodeArray())
            }
        }

        return array
    }
}

extension KeyedEncodingContainer where K == AnyCodingKey {
    mutating func encode(_ dict: [String: Any]) throws {
        for (key, value) in dict {
            let codingKey = AnyCodingKey(stringValue: key)!

            switch value {
                case let v as String:
                    try encode(v, forKey: codingKey)
                case let v as Int:
                    try encode(v, forKey: codingKey)
                case let v as Double:
                    try encode(v, forKey: codingKey)
                case let v as Bool:
                    try encode(v, forKey: codingKey)
                case let v as [String: Any]:
                    var nestedContainer = nestedContainer(keyedBy: AnyCodingKey.self, forKey: codingKey)
                    try nestedContainer.encode(v)
                case let v as [Any]:
                    var nestedContainer = nestedUnkeyedContainer(forKey: codingKey)
                    try nestedContainer.encodeArray(v)
                default:
                    break
            }
        }
    }
}

extension UnkeyedEncodingContainer {
    mutating func encodeArray(_ array: [Any]) throws {
        for value in array {
            switch value {
                case let v as String:
                    try encode(v)
                case let v as Int:
                    try encode(v)
                case let v as Double:
                    try encode(v)
                case let v as Bool:
                    try encode(v)
                case let v as [String: Any]:
                    var nestedContainer = nestedContainer(keyedBy: AnyCodingKey.self)
                    try nestedContainer.encode(v)
                case let v as [Any]:
                    var nestedContainer = nestedUnkeyedContainer()
                    try nestedContainer.encodeArray(v)
                default:
                    break
            }
        }
    }
}
