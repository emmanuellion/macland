// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Island",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Island",
            path: "Sources/Island",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
