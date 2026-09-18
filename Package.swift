// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "blipsy",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "blipsy",
            path: "Sources/blipsy",
            swiftSettings: [
                // AppKit interop is cleaner under the Swift 5 language mode; the code
                // still uses actors / async-await, just without strict-6 enforcement.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
