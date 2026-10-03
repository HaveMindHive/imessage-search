// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "iMessageSearch",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "MessagesCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "iMessageSearch",
            dependencies: ["MessagesCore"]
        ),
        .testTarget(
            name: "MessagesCoreTests",
            dependencies: ["MessagesCore"]
        ),
    ]
)
