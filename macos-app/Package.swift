// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppStoreShots",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AppStoreShots",
            path: "Sources/AppStoreShots"
        )
    ]
)
