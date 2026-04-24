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
    dependencies: [
        .package(
            name: "MixpanelSwiftCommon",
            url: "https://github.com/mixpanel/mixpanel-swift-common.git",
            from: "1.0.1"
        )
    ],
    targets: [
        .target(
            name: "MixpanelSessionReplay",
            dependencies: [
                "MixpanelSessionReplayBinary",
                .product(name: "MixpanelSwiftCommon", package: "MixpanelSwiftCommon")
            ]
        ),
        .binaryTarget(
            name: "MixpanelSessionReplay",
            path: "MixpanelSessionReplay.xcframework")
    ])

