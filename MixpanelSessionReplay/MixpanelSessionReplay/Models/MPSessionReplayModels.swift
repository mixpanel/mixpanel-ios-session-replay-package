//
//  MPSessionReplayModels.swift
//  Copyright © 2024 Mixpanel. All rights reserved.
//

import Foundation

struct SessionTrackingData: Codable {
    let distinctId: String
    let deviceId: String
    let seq: Int
    let events: [SessionEvent]
    let batchStartTime: Double
    let replayId: String
    let replayLengthMs: Int
    let replayStartTime: Double

    enum CodingKeys: String, CodingKey {
        case distinctId = "distinct_id"
        case events, seq
        case batchStartTime = "batch_start_time"
        case replayId = "replay_id"
        case replayLengthMs = "replay_length_ms"
        case replayStartTime = "replay_start_time"
        case deviceId = "$device_id"
    }
}

struct SessionEvent: Codable {
    let type: Int
    let data: SessionEventData?
    var timestamp: Int64
}

protocol SessionEventDataProtocol: Codable {}

enum SessionEventData: Codable {
    case dimensionData(SessionDimensionData)
    case nodeData(SessionNodeData)
    case positionData(SessionPositionData)
    case detailedData(EventDataDetail)
    case attributesData(SessionAttributesData)

    enum CodingKeys: String, CodingKey {
        case width, height, node, source, positions, type, id, x, y, textContent, childNodes, tagName,
            attributes, isStyle, name, publicId, systemId, texts, removes, adds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let width = try container.decodeIfPresent(Int.self, forKey: .width),
            let height = try container.decodeIfPresent(Int.self, forKey: .height)
        {
            let dimensionData = SessionDimensionData(width: width, height: height)
            self = .dimensionData(dimensionData)
            return
        }

        if let node = try container.decodeIfPresent(SessionNode.self, forKey: .node) {
            let nodeData = SessionNodeData(node: node)
            self = .nodeData(nodeData)
            return
        }

        if let source = try container.decodeIfPresent(Int.self, forKey: .source),
            let positions = try container.decodeIfPresent([SessionPosition].self, forKey: .positions)
        {
            let positionData = SessionPositionData(source: source, positions: positions)
            self = .positionData(positionData)
            return
        }

        if let type = try container.decodeIfPresent(Int.self, forKey: .type),
            let id = try container.decodeIfPresent(Int.self, forKey: .id),
            let x = try container.decodeIfPresent(Int.self, forKey: .x),
            let y = try container.decodeIfPresent(Int.self, forKey: .y),
            let source = try container.decodeIfPresent(Int.self, forKey: .source)
        {
            let detailData = EventDataDetail(source: source, type: type, id: id, x: x, y: y)
            self = .detailedData(detailData)
            return
        }

        throw DecodingError.dataCorruptedError(
            forKey: .width, in: container, debugDescription: "Data does not match any known event type")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .dimensionData(let data):
                try container.encode(data.width, forKey: .width)
                try container.encode(data.height, forKey: .height)
            case .nodeData(let data):
                try container.encode(data.node, forKey: .node)
            case .positionData(let data):
                try container.encode(data.source, forKey: .source)
                try container.encode(data.positions, forKey: .positions)
            case .detailedData(let data):
                try container.encode(data.source, forKey: .source)
                try container.encode(data.type, forKey: .type)
                try container.encode(data.id, forKey: .id)
                try container.encode(data.x, forKey: .x)
                try container.encode(data.y, forKey: .y)
            case .attributesData(let data):
                try container.encode(data.source, forKey: .source)
                try container.encode(data.texts, forKey: .texts)
                try container.encode(data.attributes, forKey: .attributes)
                try container.encode(data.removes, forKey: .removes)
                try container.encode(data.adds, forKey: .adds)
        }
    }
}

struct SessionDimensionData: SessionEventDataProtocol {
    let width: Int
    let height: Int
}

struct SessionNodeData: SessionEventDataProtocol {
    let node: SessionNode
}

struct SessionPositionData: SessionEventDataProtocol {
    let source: Int
    let positions: [SessionPosition]
}

struct EventDataDetail: Codable {
    var source: Int
    var type: Int
    var id: Int
    var x: Int
    var y: Int
}

struct SessionAttributesData: Codable {
    let source: Int
    let texts: [String]
    let attributes: [Attribute]
    let removes: [String]
    let adds: [String]

    public struct Attribute: Codable {
        let id: Int
        let attributes: [String: String]
    }
}

struct SessionNode: Codable {
    let type: Int
    let name: String?
    let publicId: String?
    let systemId: String?
    let tagName: String?
    let attributes: [String: String]?
    let textContent: String?
    let isStyle: Bool?
    let childNodes: [SessionNode]?
    let id: Int
}

struct SessionPosition: Codable {
    let x: Double
    let y: Double
    let id: Int
    let timeOffset: Int
}

struct SessionChildNode: Codable {
    let type: Int
    let tagName: String?
    let attributes: [String: String]?
    let childNodes: [SessionChildNode]?
    let id: Int
    let textContent: String?
    let isStyle: Bool?
}
