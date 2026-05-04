//
//  MPSessionReplayEncoder.swift
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation

struct IdentityInfo {
    let distinctId: String
}

struct PayloadInfo {
    let sessionEvents: [SessionEvent]
    let batchStartTime: TimeInterval
    let seq: Int
    let replayId: String
    let replayLengthMs: Int64
    let replayStartTime: TimeInterval
}

struct MPSessionReplayEncoder {

    static func serialize(data: SessionTrackingData) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let jsonData = try encoder.encode(data)
            return String(data: jsonData, encoding: .utf8)
        } catch {
            Logger.error(message: "Error serializing JSON: \(error)")
            return nil
        }
    }

    static func jsonPayload(payloadInfo: PayloadInfo) -> String? {
        let metaEvent = SessionEvent.init(
            type: EventType.meta,
            data: .dimensionData(
                SessionDimensionData.init(width: DeviceInfo.screenWidth, height: DeviceInfo.screenHeight)),
            timestamp: TimestampUtils.timeIntervalToMs(payloadInfo.batchStartTime))
        var allEvents: [SessionEvent] = [metaEvent]
        allEvents.append(contentsOf: payloadInfo.sessionEvents)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        do {
            let jsonData = try encoder.encode(allEvents)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            Logger.error(message: "Failed to encode Payload JSON: \(error)")
        }
        return nil
    }

    static func deserialize(jsonString: String) -> SessionTrackingData? {
        let decoder = JSONDecoder()
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }
        do {
            let data = try decoder.decode(SessionTrackingData.self, from: jsonData)
            return data
        } catch {
            Logger.error(message: "Error deserializing JSON: \(error)")
            return nil
        }
    }

    static func jsonSessionData(eventData: SessionTrackingData) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(eventData)
            if let jsonString = String(data: data, encoding: .utf8) {
                Logger.info(message: "Serialized JSON string: \(jsonString)")
                return jsonString
            }
        } catch {
            Logger.error(message: "Error encoding Session JSON: \(error)")
        }
        return nil
    }

    static func incrementalSessionEvent(image: Data, timestamp: Int64) -> SessionEvent? {
        let attributesData = SessionAttributesData(
            source: IncrementalSource.mutation,
            texts: [],
            attributes: [
                SessionAttributesData.Attribute(
                    id: PayloadObjectID.mainSnapshot,
                    attributes: ["src": "data:image/jpeg;base64,\(image.base64EncodedString())"])
            ],
            removes: [],
            adds: []
        )

        return SessionEvent(
            type: EventType.incrementalSnapshot, data: .attributesData(attributesData),
            timestamp: timestamp)
    }

    static func mainSessionEvent(image: Data, timestamp: Int64) -> SessionEvent? {
        do {
            let replayJSON = ReplayJSONTemplate.mainEventJSON(
                imageBase64: image.base64EncodedString(), timestamp: timestamp)
            let decoder = JSONDecoder()
            if let replayJSONData = replayJSON.data(using: .utf8) {
                var nodeData = try decoder.decode(SessionEvent.self, from: replayJSONData)
                nodeData.timestamp = timestamp
                return nodeData
            } else {
                Logger.error(message: "Failed to convert string to Data")
            }
        } catch {
            Logger.error(
                message: "An error occurred while reading or decoding the main session event: \(error)")
        }

        return nil
    }
}
