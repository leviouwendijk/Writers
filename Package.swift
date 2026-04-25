// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Writers",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Writers",
            targets: ["Writers"]
        ),

        .executable(
            name: "wtest",
            targets: ["WritersTestFlows"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/leviouwendijk/Difference.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Position.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Readers.git", branch: "master"),

        .package(url: "https://github.com/leviouwendijk/TestFlows.git", branch: "master"),
    ],
    targets: [
        .target(
            name: "Writers",
            dependencies: [
                .product(name: "Difference", package: "Difference"),
                .product(name: "Position", package: "Position"),
                .product(name: "Readers", package: "Readers"),
            ],
        ),

        .executableTarget(
            name: "WritersTestFlows",
            dependencies: [
                "Writers",
                .product(name: "Difference", package: "Difference"),
                .product(name: "Position", package: "Position"),
                .product(name: "Readers", package: "Readers"),
                .product(name: "TestFlows", package: "TestFlows"),
            ],
            // sources: ["WritersTestFlows"]
        ),
    ]
)
