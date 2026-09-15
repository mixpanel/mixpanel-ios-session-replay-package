//
//  SwiftUIInputsScreen.swift
//  SampleApp
//

import SwiftUI

struct SwiftUIInputsScreen: View {
    @State private var textField = "prefilled"
    @State private var secureField = "hunter2"
    @State private var toggle = true
    @State private var counter = 0

    var body: some View {
        Form {
            Section("Buttons") {
                Button("Regular button") { counter += 1 }
                Button {
                    counter += 1
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Icon + label button")
                    }
                }
                Button(role: .destructive) {
                } label: {
                    Text("Destructive")
                }
            }

            Section("Text fields") {
                TextField("Placeholder", text: $textField)
                SecureField("Secret", text: $secureField)
            }

            Section("Toggles / steppers") {
                Toggle("Enable notifications", isOn: $toggle)
                Stepper("Counter: \(counter)", value: $counter)
            }

            Section("Links / navigation") {
                NavigationLink("Push destination") {
                    Text("Destination")
                        .navigationTitle("Pushed")
                }
                Link("Open example.com", destination: URL(string: "https://example.com")!)
            }
        }
        .navigationTitle("SwiftUI Inputs")
    }
}
