//
//  SwiftUITextScreen.swift
//  SampleApp
//
//  Every SwiftUI Text variant we want to see the wireframe extractor
//  attempt. Nothing is masked — sensitiveRules is empty and autoMaskedViews
//  is [], so what appears in the console is exactly what the extractor
//  managed to pull.
//

import MixpanelSessionReplay
import SwiftUI

struct SwiftUITextScreen: View {
  @State private var counter = 0

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {

        section("Opt-in wireframe text (should appear in console)") {
          Text("Hello world")
            .mpWireframeText("Hello world")
          Text("Welcome")
            .mpWireframeText("Welcome")
          Button("Continue") {}
            .mpWireframeText("Continue")
        }

        section("Not opted in (should be text=nil in console)") {
          Text("Untagged text")
          Button("Untagged button") {}
        }

        section("Plain") {
          Text("Hello world")
          Text("Multi-line text\nsecond line\nthird line")
        }

        section("Formatted") {
          Text("Bold").bold()
          Text("Italic").italic()
          Text("Colored").foregroundColor(.red)
        }

        section("Localized / Interpolated") {
          Text("Count: \(counter)")
          Button("increment") { counter += 1 }
        }

        section("Labels & Concatenation") {
          Label("Star", systemImage: "star.fill")
          (Text("first ") + Text("second").bold() + Text(" third"))
        }

        section("With accessibility label") {
          Text("Displayed text")
            .accessibilityLabel("Accessible override")
        }

        section("Long / truncated") {
          Text(String(repeating: "word ", count: 30))
            .lineLimit(2)
        }
      }
      .padding()
    }
    .navigationTitle("SwiftUI Text")
  }

  @ViewBuilder
  private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.caption).foregroundColor(.secondary)
      content()
    }
    .padding(10)
    .background(Color(uiColor: .secondarySystemBackground))
    .cornerRadius(8)
  }
}
