// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macland",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "macland",
            path: "Sources/macland",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
