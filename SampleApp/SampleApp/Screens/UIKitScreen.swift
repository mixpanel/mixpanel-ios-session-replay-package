//
//  UIKitScreen.swift
//  SampleApp
//
//  Pure UIKit screen wrapped for SwiftUI. Establishes the baseline: this is
//  what the wireframe extractor CAN see (UILabel/UIButton/UITextField are
//  first-class in the walker).
//

import SwiftUI
import UIKit

struct UIKitScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIKitVC { UIKitVC() }
    func updateUIViewController(_ vc: UIKitVC, context: Context) {}
}

final class UIKitVC: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "UIKit"

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])

        let label = UILabel()
        label.text = "Plain UILabel"
        stack.addArrangedSubview(label)

        let bigLabel = UILabel()
        bigLabel.text = "Large title"
        bigLabel.font = .preferredFont(forTextStyle: .largeTitle)
        stack.addArrangedSubview(bigLabel)

        let button = UIButton(type: .system)
        button.setTitle("Continue", for: .normal)
        stack.addArrangedSubview(button)

        let field = UITextField()
        field.placeholder = "Email"
        field.text = "user@example.com"
        field.borderStyle = .roundedRect
        stack.addArrangedSubview(field)

        let secure = UITextField()
        secure.placeholder = "Password"
        secure.text = "hunter2"
        secure.isSecureTextEntry = true
        secure.borderStyle = .roundedRect
        stack.addArrangedSubview(secure)

        let image = UIImageView(image: UIImage(systemName: "star.fill"))
        image.tintColor = .systemYellow
        image.contentMode = .scaleAspectFit
        image.accessibilityLabel = "star icon"
        image.heightAnchor.constraint(equalToConstant: 60).isActive = true
        stack.addArrangedSubview(image)
    }
}
