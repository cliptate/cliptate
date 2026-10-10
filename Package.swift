// swift-tools-version: 6.2
import PackageDescription
import Foundation

// Keep the default App Store-safe; explicitly opt out for direct distribution.
let appStoreBuild = ProcessInfo.processInfo.environment["CLIPTATE_APP_STORE"] != "NO"

let package = Package(
    name: "Cliptate",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "Cliptate",
            targets: ["Cliptate"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern.git", from: "1.1.0"),
        .package(url: "https://github.com/mihai8804858/swift-ass-renderer", from: "1.3.1"),
        // Newer manifests change the IssueReporting package identity across Swift versions.
        // Use the same dependency graph with Xcode 26 and Xcode 27.
        .package(url: "https://github.com/pointfreeco/combine-schedulers", exact: "1.2.0"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", exact: "1.11.0"),
        .package(url: "https://github.com/AudioKit/AudioKit", from: "5.6.5"),
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm.git", from: "5.44.1"),
        // Keep the inference graph compatible with the pinned MLX Audio revision.
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.31.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.31.3"),
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", revision: "7734cd1fbbe86460083c1d24199737a24cadfcc8"),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "0.8.0"),
    ],
    targets: [
        .target(
            name: "Cliptate",
            dependencies: [
                "KeyboardShortcuts",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
                .product(name: "SwiftAssRenderer", package: "swift-ass-renderer"),
                .product(name: "AudioKit", package: "AudioKit"),
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "MLXAudioVAD", package: "mlx-audio-swift"),
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ],
            path: "Sources/Cliptate",
            exclude: [
                "Info.plist",
                "Cliptate.entitlements",
                "Cliptate.swift",
            ],
            resources: [
                .process("Assets.xcassets"),
                .process("Localizable.xcstrings")
            ],
            swiftSettings: appStoreBuild ? [.define("APP_STORE")] : []
        ),
        .testTarget(
            name: "CliptateTests",
            dependencies: ["Cliptate"],
            path: "Tests/CliptateTests",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
