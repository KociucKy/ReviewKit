// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ReviewKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "ReviewKit",
            targets: ["ReviewKit"]
        )
    ],
    targets: [
        .target(
            name: "ReviewKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "ReviewKitTests",
            dependencies: ["ReviewKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
