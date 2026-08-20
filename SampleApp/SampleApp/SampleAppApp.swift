//
//  SampleAppApp.swift
//  SampleApp
//
//  Interactive test bed for MixpanelSessionReplay wireframes. Boots the SDK
//  with wireframes on + `DebugOptions.wireframeEmitter`, which streams each
//  frame's collected elements to WireframeConsole for live inspection.
//
//  Note the split: `wireframesOptions` is what turns capture *on*, while
//  `debugOptions.wireframeEmitter` only *observes* it. Setting the emitter
//  without `wireframesOptions` is harmless but never calls back.
//

import MixpanelSessionReplay
import SwiftUI

@main
struct SampleAppApp: App {
  init() {
    let config = MPSessionReplayConfig(
      autoMaskedViews: [],
      enableLogging: true,
      enableSessionReplayOniOS26AndLater: true,
      // `overlayColors: nil` keeps the mask overlay off — this test bed reads
      // the wireframe payload in the console, not the grayed rectangles.
      debugOptions: DebugOptions(
        overlayColors: nil,
        wireframeEmitter: { snapshot in
          WireframeConsole.shared.push(snapshot)
        }
      ),
      wireframesOptions: MPWireframesOptions(sensitiveRules: [])
    )

    MPSessionReplay.initialize(
      token: "074759b3e946dbc6289ee8567cc557b3",
      distinctId: "ios_wireframe",
      config: config
    )
  }

  var body: some Scene {
    WindowGroup {
      RootView()
    }
  }
}
