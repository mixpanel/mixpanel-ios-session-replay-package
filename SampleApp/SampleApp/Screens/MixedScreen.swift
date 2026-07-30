//
//  MixedScreen.swift
//  SampleApp
//
//  Interleaves UIKit and SwiftUI both ways: a UIViewController that hosts a
//  SwiftUI subtree via UIHostingController, and a SwiftUI subtree that hosts
//  a UIKit label via UIViewRepresentable. Useful for confirming the walker
//  descends across the bridge in either direction.
//

import SwiftUI
import UIKit

struct MixedScreen: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {

        Text("SwiftUI wrapping UIKit").font(.headline)
        UIKitLabelWrapper(text: "This is a UILabel inside SwiftUI")
          .frame(height: 40)

        Divider()

        Text("UIKit wrapping SwiftUI").font(.headline)
        UIKitHostingSwiftUI(text: "SwiftUI Text inside a UIViewController")
          .frame(height: 80)

        Divider()

        Text("Double nested").font(.headline)
        UIKitHostingSwiftUI(text: "Level 1 SwiftUI")
          .frame(height: 60)

        Text("Notes:").font(.headline).padding(.top)
        Text("• 'Plain UILabel' in the wrapper below → UIKit path, should show text.")
        Text("• Anything from SwiftUI hosts → depends on extractor reach.")
      }
      .padding()
    }
    .navigationTitle("Mixed")
  }
}

private struct UIKitLabelWrapper: UIViewRepresentable {
  let text: String
  func makeUIView(context: Context) -> UILabel {
    let l = UILabel()
    l.text = text
    return l
  }
  func updateUIView(_ view: UILabel, context: Context) {
    view.text = text
  }
}

private struct UIKitHostingSwiftUI: UIViewControllerRepresentable {
  let text: String
  func makeUIViewController(context: Context) -> UIViewController {
    let vc = UIViewController()
    vc.view.backgroundColor = .secondarySystemBackground

    let child = UIHostingController(rootView: VStack(alignment: .leading, spacing: 4) {
      Text(text).bold()
      Text("nested body text")
        .font(.caption)
    })
    vc.addChild(child)
    child.view.translatesAutoresizingMaskIntoConstraints = false
    vc.view.addSubview(child.view)
    NSLayoutConstraint.activate([
      child.view.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 12),
      child.view.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -12),
      child.view.topAnchor.constraint(equalTo: vc.view.topAnchor, constant: 8),
      child.view.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor, constant: -8),
    ])
    child.didMove(toParent: vc)
    return vc
  }
  func updateUIViewController(_ vc: UIViewController, context: Context) {}
}
