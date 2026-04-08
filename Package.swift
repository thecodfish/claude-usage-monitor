// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "ClaudeUsageMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeUsageMonitor",
            path: "Sources/ClaudeUsageMonitor",
            exclude: ["Resources"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("SwiftUI"),
            ]
        )
    ]
)
