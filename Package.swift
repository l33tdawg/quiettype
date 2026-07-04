// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "typeless-secure",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "LocalTypeCore", targets: ["LocalTypeCore"]),
        .executable(name: "localtype", targets: ["LocalTypeCLI"]),
        .executable(name: "localtype-session", targets: ["LocalTypeSessionCLI"]),
        .executable(name: "LocalTypeMac", targets: ["LocalTypeMac"])
    ],
    targets: [
        .target(name: "LocalTypeCore"),
        .executableTarget(
            name: "LocalTypeCLI",
            dependencies: ["LocalTypeCore"]
        ),
        .executableTarget(
            name: "LocalTypeSessionCLI",
            dependencies: ["LocalTypeCore"]
        ),
        .executableTarget(
            name: "LocalTypeMac",
            dependencies: ["LocalTypeCore"]
        ),
        .testTarget(
            name: "LocalTypeCoreTests",
            dependencies: ["LocalTypeCore"]
        )
    ]
)
