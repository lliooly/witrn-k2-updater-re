// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "K2Updater",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "K2Updater", targets: ["K2Updater"])],
    targets: [
        .target(name: "K2Core"),
        .executableTarget(name: "K2Updater", dependencies: ["K2Core"]),
        .testTarget(name: "K2CoreTests", dependencies: ["K2Core"])
    ]
)
