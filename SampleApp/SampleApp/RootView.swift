//
//  RootView.swift
//  SampleApp
//

import SwiftUI

struct RootView: View {
    @State private var showConsole: Bool = true

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                NavigationView { SwiftUITextScreen() }
                    .tabItem { Label("SwiftUI Text", systemImage: "textformat") }

                NavigationView { SwiftUIInputsScreen() }
                    .tabItem { Label("SwiftUI Inputs", systemImage: "square.and.pencil") }

                NavigationView { UIKitScreen() }
                    .tabItem { Label("UIKit", systemImage: "square.stack.3d.up") }

                NavigationView { MixedScreen() }
                    .tabItem { Label("Mixed", systemImage: "rectangle.on.rectangle") }

                NavigationView { ExtractionLabScreen() }
                    .tabItem { Label("Lab", systemImage: "flask") }
            }

            if showConsole {
                WireframeConsoleView(onClose: { showConsole = false })
                    .frame(height: 260)
                    .transition(.move(edge: .bottom))
            } else {
                Button {
                    withAnimation { showConsole = true }
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .padding(10)
                        .background(.thinMaterial, in: Circle())
                }
                .padding(.trailing, 16)
                .padding(.bottom, 60)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

struct WireframeConsoleView: View {
    @ObservedObject var console = WireframeConsole.shared
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if console.rows.isEmpty {
                VStack(spacing: 4) {
                    if console.emitCount == 0 {
                        Text("Waiting for emits… tap or scroll on this screen.")
                    } else if console.textOnly && console.latestElementCount > 0 {
                        Text("No elements with text on this screen.")
                            .bold()
                        Text(
                            "\(console.latestElementCount) elements in latest frame — all have text=nil. Toggle the filter to see them."
                        )
                        .multilineTextAlignment(.center)
                    } else {
                        Text("No elements collected.")
                    }
                }
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // LazyVStack only builds rows as they scroll into view; stable Row.id
                // (role + bounds hash) lets SwiftUI diff instead of rebuilding.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                        ForEach(console.rows) { row in
                            RowView(row: row)
                        }
                        if console.latestElementCount > console.rows.count {
                            Text(
                                "… \(console.latestElementCount - console.rows.count) more (raise WireframeConsole.maxDisplayedRows to see)"
                            )
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(8)
                        }
                    }
                }
            }
        }
        .background(Color(uiColor: .systemGray6))
        .cornerRadius(12, corners: [.topLeft, .topRight])
        .shadow(radius: 4)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(headerText)
                .font(.system(.footnote, design: .monospaced))
                .bold()
            Spacer()
            Button {
                console.textOnly.toggle()
            } label: {
                Image(systemName: console.textOnly ? "text.badge.checkmark" : "text.badge.xmark")
                    .font(.title3)
                    .foregroundColor(console.textOnly ? .blue : .secondary)
            }
            .help(console.textOnly ? "Showing text-only" : "Showing all elements")
            Button {
                console.paused.toggle()
            } label: {
                Image(systemName: console.paused ? "play.circle.fill" : "pause.circle.fill")
                    .font(.title3)
                    .foregroundColor(console.paused ? .green : .primary)
            }
            Button(action: console.clear) {
                Image(systemName: "trash.circle.fill").font(.title3)
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").font(.title3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(uiColor: .systemGray6))
    }

    private var headerText: String {
        let shown = console.rows.count
        let total = console.latestElementCount
        // With filter on: shown reflects text-only count; total is per-frame all.
        // With filter off: shown/total both reflect full set, capped at 200.
        let mode = console.textOnly ? "text" : "all"
        let counts = "\(shown) shown · \(total) frame"
        let status = console.paused ? " ⏸" : ""
        return "Wireframe [\(mode)] · \(counts) · \(console.emitCount) emits\(status)"
    }
}

private struct RowView: View {
    let row: WireframeConsole.Row
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(row.role)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 44, alignment: .leading)
                .foregroundColor(colorFor(role: row.role))
            Text(row.text ?? "—")
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .foregroundColor(row.text == nil ? .secondary : .primary)
            Text(row.maskDecision)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.orange)
            Text("[\(row.bounds.map(String.init).joined(separator: ","))]")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(uiColor: .systemBackground))
    }

    private func colorFor(role: String) -> Color {
        switch role {
            case "text": return .blue
            case "button": return .green
            case "input": return .purple
            case "image": return .pink
            default: return .primary
        }
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

private struct RoundedCorner: Shape {
    var radius: CGFloat = 0
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        Path(
            UIBezierPath(
                roundedRect: rect,
                byRoundingCorners: corners,
                cornerRadii: CGSize(width: radius, height: radius)
            ).cgPath)
    }
}
