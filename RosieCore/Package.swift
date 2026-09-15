// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RosieCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "RosieCore", targets: ["RosieCore"])],
    targets: [
        .target(name: "RosieCore"),
        .testTarget(name: "RosieCoreTests", dependencies: ["RosieCore"])
    ]
)
