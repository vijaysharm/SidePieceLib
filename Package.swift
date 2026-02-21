// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SidePieceLib",
    platforms: [.macOS(.v15)],
    products: [
        .library(
            name: "SidePieceLib",
            targets: ["SidePieceLib"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.23.2"),
        .package(url: "https://github.com/vijaysharm/textual", branch: "main"),
    ],
    targets: [
        .target(
            name: "SidePieceLib",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Textual", package: "textual"),
            ]
        ),
    ]
)
