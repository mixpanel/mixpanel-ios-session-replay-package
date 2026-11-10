// swift-tools-version:5.6

import PackageDescription

let package = Package(
    name: "MixpanelSessionReplay",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "MixpanelSessionReplay", targets: ["MixpanelSessionReplay"])
    ],
    dependencies: [
        // TEMPORARY (hierarchical-groups): MixpanelIdentity is on mixpanel-swift-common's
        // hierarchical-groups branch. Restore the released dependency once it ships:
        // .package(url: "https://github.com/mixpanel/mixpanel-swift-common.git", from: "2.1.0")
        .package(path: "../mixpanel-swift-common")
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
