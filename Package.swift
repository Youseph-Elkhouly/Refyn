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
    ],
    targets: [
        .target(name: "RefineCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(name: "Refine", dependencies: ["RefineCore"]),
        .testTarget(name: "RefineCoreTests", dependencies: ["RefineCore"]),
    ]
)
