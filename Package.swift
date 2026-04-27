// swift-tools-version:5.6
import PackageDescription

let package = Package(
    name: "MixpanelSessionReplay",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        // The library product points to the wrapper target, not the binary directly.
        // See MixpanelSessionReplayWrapper target below for why.
        .library(
            name: "MixpanelSessionReplay",
            targets: ["MixpanelSessionReplayWrapper"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/mixpanel/mixpanel-swift-common.git",
            from: "1.0.1"
        )
    ],
    targets: [
        // The xcframework distributed to consumers.
        .binaryTarget(
            name: "MixpanelSessionReplay",
            path: "MixpanelSessionReplay.xcframework"
        ),
        // Wrapper target: SPM .binaryTarget cannot declare dependencies on other
        // SPM packages, so we wrap the xcframework in a regular .target to pull in
        // MixpanelSwiftCommon as a transitive dependency. The wrapper's source file
        // (Sources/MixpanelSessionReplayWrapper/Exports.swift) re-exports the binary
        // module so consumers can keep using `import MixpanelSessionReplay`.
        .target(
            name: "MixpanelSessionReplayWrapper",
            dependencies: [
                "MixpanelSessionReplay",
                .product(name: "MixpanelSwiftCommon", package: "mixpanel-swift-common")
            ]
        )
    ]
)
