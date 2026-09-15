//
//  WireframeConsole.swift
//  SampleApp
//
//  Shared observable model that receives every wireframe frame from the SDK's
//  debugEmitter and republishes the latest snapshot to SwiftUI. Coalesces
//  emits to keep the UI responsive on Form-heavy screens where a single pass
//  can produce hundreds of elements.
//

import Combine
import Foundation
import MixpanelSessionReplay

final class WireframeConsole: ObservableObject {
    static let shared = WireframeConsole()

    /// Displayed row. `id` is derived from role+bounds so the same element
    /// keeps its identity across emits — SwiftUI can diff instead of tearing
    /// down and rebuilding the whole list every frame.
    struct Row: Identifiable, Equatable {
        let id: Int
        let role: String
        let text: String?
        let bounds: [Int]
        let maskDecision: String
    }

    /// Cap on how many rows the UI holds. Beyond this we drop the tail and
    /// note the total in `latestElementCount`. Prevents Form screens with
    /// 500+ internal views from freezing scrolling.
    static let maxDisplayedRows = 200

    /// Minimum interval between UI publishes. The SDK may emit far faster on
    /// active screens; UI diffing on hundreds of rows at 10Hz is unusably slow.
    static let publishInterval: TimeInterval = 0.4

    @Published private(set) var latestTimestamp: Int64 = 0
    @Published private(set) var latestViewport: [Int] = []
    @Published private(set) var latestElementCount: Int = 0
    @Published private(set) var rows: [Row] = []
    @Published private(set) var emitCount: Int = 0
    @Published var paused: Bool = false
    /// When true, `rows` only contains elements with non-nil text — the ones
    /// worth reading. Defaults on because unfiltered Form/List screens produce
    /// hundreds of text=nil rows and drown out anything useful.
    @Published var textOnly: Bool = true

    private let queue = DispatchQueue(label: "wireframe-console")
    private var lastPublishAt: TimeInterval = 0

    private init() {}

    /// Called from the SDK's screenshot/wireframe pass. May fire off the main
    /// thread; hop to main before mutating @Published state.
    func push(_ snapshot: MPWireframeDebugSnapshot) {
        // Snapshot the filter flag on the caller's thread. Reading a Bool is
        // atomic enough for a debug UI toggle; worst case a filter change takes
        // one extra emit to take effect.
        let textOnly = self.textOnly
        queue.async { [weak self] in
            guard let self = self else { return }
            let now = Date().timeIntervalSince1970
            guard now - self.lastPublishAt > Self.publishInterval else { return }
            self.lastPublishAt = now

            let total = snapshot.elements.count
            let filtered =
                textOnly
                ? snapshot.elements.filter { $0.text?.isEmpty == false }
                : Array(snapshot.elements)
            let capped = filtered.prefix(Self.maxDisplayedRows)
            let rows = capped.map { e -> Row in
                // Stable identity across emits: role + rounded bounds. Same element
                // keeps its Row.id, so SwiftUI diffs cheaply.
                var hasher = Hasher()
                hasher.combine(e.role)
                e.bounds.forEach { hasher.combine($0) }
                return Row(
                    id: hasher.finalize(),
                    role: e.role,
                    text: e.text,
                    bounds: e.bounds,
                    maskDecision: e.maskDecision.rawValue
                )
            }

            DispatchQueue.main.async {
                guard !self.paused else { return }
                self.latestTimestamp = snapshot.timestamp
                self.latestViewport = snapshot.viewport
                self.latestElementCount = total
                self.rows = rows
                self.emitCount += 1
            }
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.rows = []
            self.emitCount = 0
            self.latestElementCount = 0
        }
    }
}
