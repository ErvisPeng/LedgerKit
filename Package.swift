// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LedgerKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "LedgerKit",
            targets: ["LedgerKit"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LedgerKit",
            dependencies: [],
            path: "Sources/LedgerKit"
        ),
        .testTarget(
            name: "LedgerKitTests",
            dependencies: ["LedgerKit"],
            path: "Tests/LedgerKitTests"
        ),
    ]
)
