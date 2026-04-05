// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SomaFM",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SomaFM", targets: ["SomaFM"])
    ],
    dependencies: [
        // Add dependencies here if needed
    ],
    targets: [
        .executableTarget(
            name: "SomaFM",
            dependencies: []
        ),
        .testTarget(
            name: "SomaFMTests",
            dependencies: ["SomaFM"]
        )
    ]
)