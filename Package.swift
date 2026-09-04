// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DivergeSDK",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        // macOS supports core + tests/DocC without a simulator.
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "AIConversation",
            targets: ["AIConversation"]
        )
    ],
    targets: [
        .target(name: "AIConversationCore"),
        .target(
            name: "AIConversationEngine",
            dependencies: ["AIConversationCore"]
        ),
        .target(
            name: "AIConversation",
            dependencies: ["AIConversationEngine"],
            resources: [
                .process("Resources"),
                .copy("PrivacyInfo.xcprivacy")
            ]
        ),
        .executableTarget(
            name: "Harness",
            dependencies: ["AIConversation"],
            path: "Samples/macOS"
        ),
        .testTarget(
            name: "AIConversationTests",
            dependencies: [
                "AIConversation",
                "AIConversationCore",
                "AIConversationEngine"
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
