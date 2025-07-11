// swift-tools-version:5.6
import PackageDescription

let package = Package(
    name: "MixpanelSessionReplay",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "MixpanelSessionReplay", 
            targets: ["MixpanelSessionReplay"])
    ],
    targets: [
        .binaryTarget(
            name: "MixpanelSessionReplay", 
            path: "MixpanelSessionReplay.xcframework")
    ])

