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
        .package(url: "https://github.com/argmaxinc/WhisperKit", exact: "0.18.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "2.30.6"),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.1.9"),
    ],
    targets: [
        .target(name: "RefineCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(
            name: "Refine",
            dependencies: [
                "RefineCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Hub", package: "swift-transformers"),
            ]
        ),
        .testTarget(name: "RefineCoreTests", dependencies: ["RefineCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "RefineLocalInferenceTests", dependencies: ["Refine", "RefineCore"]),
    ]
)
