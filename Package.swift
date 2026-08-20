// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Pullr",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Pullr", targets: ["Pullr"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4")
    ],
    targets: [
        .executableTarget(
            name: "Pullr",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Pullr",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
