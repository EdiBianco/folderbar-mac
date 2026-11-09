// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FolderBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FolderBar",
            path: "Sources/FolderBar"
        )
    ]
)
