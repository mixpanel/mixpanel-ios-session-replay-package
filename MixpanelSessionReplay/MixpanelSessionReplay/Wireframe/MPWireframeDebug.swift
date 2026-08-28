//
//  MPWireframeDebug.swift
//  MixpanelSessionReplay
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import Foundation

/// Why a wireframe element's text was preserved, rewritten, or dropped.
///
/// Reported through ``MPWireframeDebugSnapshot`` for local inspection only.
///
/// Raw values are the `SCREAMING_SNAKE_CASE` names Android and Flutter report
/// in their debug snapshots, so the same decision reads identically on every
/// platform.
///
/// ⚠️ Not a stable contract — case names and semantics may change.
public enum MPMaskDecision: String, Codable {
    /// Text emitted as-is.
    case none = "NONE"
    /// Developer-supplied `.mpWireframeText(_:)`. Emitted verbatim, even on
    /// a masked or editable view, because the text is authored rather than
    /// scraped from the screen. Exempt from the Layer 2 geometric strip; Layer 3
    /// sensitive rules still run over it, so an element that started as
    /// ``declared`` can still end up ``ruleStrip`` or ``ruleRedact``.
    case declared = "DECLARED"
    /// Explicitly marked sensitive by the app
    /// (`addSensitiveClass`, `mpReplaySensitive = true`, or the
    /// `.mpReplaySensitive(true)` SwiftUI modifier).
    case explicit = "EXPLICIT"
    /// Automatically masked because it matched an `MPAutoMaskedViews` category
    /// (text, image, web, map).
    case auto = "AUTO"
    /// Text-entry field — always masked, cannot be overridden.
    case textEntry = "TEXT_ENTRY"
    /// Bounds intersected a mask rect the screenshot painted over.
    /// Prevents leaks when a sensitive parent covers a non-sensitive child on
    /// the screenshot but the child's text would otherwise pass through.
    case geometric = "GEOMETRIC"
    /// Matched a `.strip` / `.stripRegex` rule; text was dropped.
    case ruleStrip = "RULE_STRIP"
    /// Matched a `.redact` / `.redactRegex` rule; text was rewritten.
    case ruleRedact = "RULE_REDACT"
}

/// A per-frame snapshot of the wireframe pass, delivered to
/// ``DebugOptions/wireframeEmitter`` for local inspection.
///
/// ⚠️ Not a stable contract — the JSON shape and field names may change.
/// Never sent to Mixpanel.
public struct MPWireframeDebugSnapshot {
    public let timestamp: Int64
    public let viewport: [Int]
    public let elements: [DebugElement]

    public struct DebugElement {
        public let role: String
        public let text: String?
        public let bounds: [Int]
        public let maskDecision: MPMaskDecision

        public init(role: String, text: String?, bounds: [Int], maskDecision: MPMaskDecision) {
            self.role = role
            self.text = text
            self.bounds = bounds
            self.maskDecision = maskDecision
        }
    }

    public init(
        timestamp: Int64,
        viewport: [Int],
        elements: [DebugElement]
    ) {
        self.timestamp = timestamp
        self.viewport = viewport
        self.elements = elements
    }

    /// Debug JSON — NOT a stable contract.
    public func toJson() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let dto = DebugSnapshotJSON(
            timestamp: timestamp,
            viewport: viewport,
            elements: elements.map { e in
                DebugSnapshotJSON.Element(
                    role: e.role,
                    text: e.text,
                    bounds: e.bounds,
                    maskDecision: e.maskDecision.rawValue
                )
            }
        )
        guard let data = try? encoder.encode(dto),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
    }
}

private struct DebugSnapshotJSON: Encodable {
    let timestamp: Int64
    let viewport: [Int]
    let elements: [Element]

    struct Element: Encodable {
        let role: String
        let text: String?
        let bounds: [Int]
        let maskDecision: String

        private enum CodingKeys: String, CodingKey {
            case role, text, bounds, maskDecision
        }

        /// Written out so a textless element emits `"text": null` rather than dropping the
        /// key. The synthesized conformance uses `encodeIfPresent` for optionals, which made
        /// this JSON disagree with Android's (`encodeDefaults = true` writes the null) and
        /// with the golden format, which specifies a `text: null` literal. Comparing two
        /// platforms' debug output by eye is the point of the sample apps, and a missing key
        /// reads as `undefined` rather than "no text" to anything consuming it — which is
        /// exactly how the React Native bridge first surfaced this.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(role, forKey: .role)
            try container.encode(text, forKey: .text)
            try container.encode(bounds, forKey: .bounds)
            try container.encode(maskDecision, forKey: .maskDecision)
        }
    }
}
