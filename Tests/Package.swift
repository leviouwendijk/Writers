// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WritersTests",
    platforms: [
        .macOS(.v13)
    ],
    products: [

        .executable(
            name: "t_writers",
            targets: ["WritersTests"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/leviouwendijk/Difference.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Position.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Readers.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Path.git", branch: "master"),

        .package(url: "https://github.com/leviouwendijk/Testing.git", branch: "master"),
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "WritersTests",
            dependencies: [
                .product(name: "Writers", package: "Writers"),
                .product(name: "Difference", package: "Difference"),
                .product(name: "Position", package: "Position"),
                .product(name: "Readers", package: "Readers"),
                .product(name: "Path", package: "Path"),
                .product(name: "Testing", package: "Testing"),
            ]
        ),
    ]
)
