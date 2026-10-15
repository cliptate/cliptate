// swift-tools-version: 6.2
import PackageDescription
import Foundation

// Dev/Debug defaults to direct distribution, Release to App Store.
// An explicit override selects the same channel for either configuration.
let channelSwiftSettings: [SwiftSetting]
switch ProcessInfo.processInfo.environment["CLIPTATE_APP_STORE"] {
case "YES": channelSwiftSettings = [.define("APP_STORE")]
case "NO": channelSwiftSettings = []
default: channelSwiftSettings = [.define("APP_STORE", .when(configuration: .release))]
}

let package = Package(
    name: "Cliptate",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        // Keep app and CLI filenames distinct on case-insensitive macOS volumes.
        .executable(
            name: "CliptateApp",
            targets: ["Cliptate"]
        ),
        .executable(name: "cliptate", targets: ["CliptateCommand"])
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
        // Keep the inference graph compatible with the pinned MLX Audio version.
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.32.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.32.3"),
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", exact: "0.1.5"),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "0.8.0"),
    ],
    targets: [
        .target(name: "CliptateCLIKit", path: "Sources/Cliptate/CLIShared"),
        .executableTarget(name: "CliptateCommand", dependencies: ["CliptateCLIKit"]),
        .executableTarget(
            name: "Cliptate",
            dependencies: [
                "CliptateCLIKit",
                "KeyboardShortcuts",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
                .product(name: "SwiftAssRenderer", package: "swift-ass-renderer"),
                .product(name: "AudioKit", package: "AudioKit"),
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
                // Used transitively by RevenueCat's CombineSchedulers; keep the pinned identity explicit.
                .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
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
                "Cliptate-Direct.entitlements",
                "CLIShared",
            ],
            resources: [
                .process("Assets.xcassets"),
                .process("Localizable.xcstrings")
            ],
            swiftSettings: channelSwiftSettings
        ),
        .testTarget(
            name: "CliptateTests",
            dependencies: ["Cliptate", "CliptateCLIKit"],
            path: "Tests/CliptateTests",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
