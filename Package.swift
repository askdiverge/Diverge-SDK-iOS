// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DivergeSDK",
    platforms: [
        .iOS(.v15),
        // macOS supports core + tests/DocC without a simulator.
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "DivergeSDK",
            targets: ["DivergeSDK"]
        ),
        .library(
            name: "DivergeSDKUI",
            targets: ["DivergeSDKUI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "DivergeSDK",
            path: "Sources/DivergeSDK",
            resources: [
                .copy("PrivacyInfo.xcprivacy")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "DivergeSDKUI",
            dependencies: ["DivergeSDK"],
            path: "Sources/DivergeSDKUI",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "DivergeSDKTests",
            dependencies: [
                "DivergeSDK",
                "DivergeSDKUI"
            ],
            path: "Tests/DivergeSDKTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
