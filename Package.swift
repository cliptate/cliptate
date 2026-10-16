// swift-tools-version: 6.2
import PackageDescription

// SwiftPM uses swiftc to link executables. Its driver needs -O at link time
// as well as compile time to enable the release linker optimizations.
let releaseLinkerSettings: [LinkerSetting] = [
    .unsafeFlags(["-O"], .when(configuration: .release))
]

let package = Package(
    name: "Cliptate",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        // App and CLI filenames remain distinct on case-insensitive macOS volumes.
        .executable(
            name: "Cliptate",
            targets: ["Cliptate"]
        ),
        .executable(name: "CliptateCLI", targets: ["CliptateCLI"]),
        .library(name: "CliptateCore", targets: ["CliptateCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", exact: "13.0.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern.git", from: "1.1.0"),
        .package(url: "https://github.com/mihai8804858/swift-ass-renderer", from: "1.3.1"),
        // SwiftAssRenderer uses CombineSchedulers. Pin its IssueReporting graph
        // so Xcode 26 and Xcode 27 resolve the same package identities.
        .package(url: "https://github.com/pointfreeco/combine-schedulers", exact: "1.2.0"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", exact: "1.11.0"),
        .package(url: "https://github.com/AudioKit/AudioKit", from: "5.6.5"),
        // Keep the inference graph compatible with the pinned MLX Audio version.
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.32.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.32.3"),
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", exact: "0.1.5"),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "0.8.0"),
    ],
    targets: [
        .target(name: "CliptateCore"),
        .executableTarget(name: "CliptateCLI", dependencies: ["CliptateCore"],
                          linkerSettings: releaseLinkerSettings),
        .executableTarget(
            name: "Cliptate",
            dependencies: [
                "CliptateCore",
                .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAnalyticsCore", package: "firebase-ios-sdk"),
                "KeyboardShortcuts",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
                .product(name: "SwiftAssRenderer", package: "swift-ass-renderer"),
                .product(name: "AudioKit", package: "AudioKit"),
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
            ],
            resources: [
                .process("Assets.xcassets"),
                .process("Localizable.xcstrings")
            ],
            linkerSettings: releaseLinkerSettings + [.unsafeFlags(["-Xlinker", "-ObjC"])]
        ),
        .testTarget(name: "CliptateCoreTests", dependencies: ["CliptateCore"]),
        .testTarget(
            name: "CliptateTests",
            dependencies: ["Cliptate", "CliptateCore"],
            path: "Tests/CliptateTests",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
