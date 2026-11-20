// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WritersBenchmarks",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "b_writers", targets: ["WritersBenchmark"]),
    ],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "WritersBenchmark",
            dependencies: [
                .product(name: "Writers", package: "Writers"),
            ]
        ),
    ]
)
