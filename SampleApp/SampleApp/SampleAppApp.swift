//
//  SampleAppApp.swift
//  SampleApp
//
//  Interactive test bed for MixpanelSessionReplay wireframes. Boots the SDK
//  with wireframes on + a debugEmitter that streams each frame's collected
//  elements to WireframeConsole for live inspection.
//

import MixpanelSessionReplay
import SwiftUI

@main
struct SampleAppApp: App {
  init() {
    let options = MPWireframesOptions(
      sensitiveRules: [],
      debugEmitter: { snapshot in
        WireframeConsole.shared.push(snapshot)
      }
    )

    let config = MPSessionReplayConfig(
      autoMaskedViews: [],
      enableLogging: true,
      enableSessionReplayOniOS26AndLater: true,
      wireframesOptions: options
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
