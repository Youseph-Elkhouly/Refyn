// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Refine",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Refine", targets: ["Refine"]),
        .library(name: "RefineCore", targets: ["RefineCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.0.0"),
        .package(url: "https://github.com/argmaxinc/WhisperKit", exact: "0.14.1"),
    ],
    targets: [
        .target(name: "RefineCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(
            name: "Refine",
            dependencies: ["RefineCore", .product(name: "WhisperKit", package: "WhisperKit")]
        ),
        .testTarget(name: "RefineCoreTests", dependencies: ["RefineCore", .product(name: "GRDB", package: "GRDB.swift")]),
    ]
)
