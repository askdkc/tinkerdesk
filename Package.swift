// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TinkerDesk",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TinkerCore", targets: ["TinkerCore"]),
        .executable(name: "TinkerDesk", targets: ["TinkerDesk"])
    ],
    targets: [
        .target(name: "TinkerCore"),
        .executableTarget(
            name: "TinkerDesk",
            dependencies: ["TinkerCore"]
        ),
        .testTarget(
            name: "TinkerCoreTests",
            dependencies: ["TinkerCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
