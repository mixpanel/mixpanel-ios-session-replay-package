//
//  WireframePayload.swift
//  MixpanelSessionReplay
//
//  Copyright © 2026 Mixpanel. All rights reserved.
//

import Foundation

/// Wire DTO for the `mp_wireframe` custom event payload.
///
/// `Hashable` because the emitter dedups on this type: the hash of a finished
/// payload is the dedup key, so two consecutive frames that would serialize to
/// the same bytes collapse to one event. See `WireframeEmitter.lastPayloadHash`.
struct WireframePayload: Codable, Equatable, Hashable {
    let viewport: [Int]?
    let elements: [WireframeElementJson]
}

struct WireframeElementJson: Codable, Equatable, Hashable {
    /// "text" | "button" | "input" | "image"
    let role: String
    /// Capped at 50 characters *including* a trailing "…" at emit time; `nil`
    /// for masked or empty.
    let text: String?
    /// `[x, y, w, h]` in window-relative pixels.
    let bounds: [Int]
}
