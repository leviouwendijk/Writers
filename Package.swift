// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Writers",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Writers",
            targets: ["Writers"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/leviouwendijk/Difference.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Position.git", branch: "master"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Writers",
            dependencies: [
                .product(name: "Difference", package: "Difference"),
                .product(name: "Position", package: "Position"),
            ],
        ),
        .testTarget(
            name: "WritersTests",
            dependencies: ["Writers"]
        ),
    ]
)
