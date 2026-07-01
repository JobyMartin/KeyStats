// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeyStats",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "KeyStats",
            path: "Sources/KeyStats",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
