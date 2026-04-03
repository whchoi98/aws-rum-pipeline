// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RumSDK",
    platforms: [.iOS(.v15)],
    products: [.library(name: "RumSDK", targets: ["RumSDK"])],
    targets: [
        .target(name: "RumSDK", path: "Sources/RumSDK"),
        .testTarget(name: "RumSDKTests", dependencies: ["RumSDK"], path: "Tests/RumSDKTests"),
    ]
)
