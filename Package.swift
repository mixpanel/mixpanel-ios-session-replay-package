// swift-tools-version:5.6

import PackageDescription

let package = Package(
    name: "MixpanelSessionReplay",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(name: "MixpanelSessionReplay", targets: ["MixpanelSessionReplay"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/mixpanel/mixpanel-swift-common.git",
            from: "1.0.1"
        )
    ],
    targets: [
        .target(
            name: "MixpanelSessionReplay",
            dependencies: [
                .product(name: "MixpanelSwiftCommon", package: "mixpanel-swift-common")
            ],
            path: "MixpanelSessionReplay",
            exclude: [
                "MixpanelSessionReplayTests",
                "MixpanelSessionReplayTests-Bridging-Header.h",
            ],
            resources: [.copy("MixpanelSessionReplay/Resources/PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "MixpanelSessionReplayTests",
            dependencies: ["MixpanelSessionReplay"],
            path: "MixpanelSessionReplay/MixpanelSessionReplayTests"
        ),
    ]
)
