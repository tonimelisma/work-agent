// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FoundationModelsPOC",
    platforms: [.macOS("27.0")],
    products: [.library(name: "FoundationModelsPOC", targets: ["FoundationModelsPOC"]),
               .executable(name: "foundation-models-probe", targets: ["FoundationModelsProbe"]),
               .executable(name: "foundation-models-session-probe", targets: ["FoundationModelsSessionProbe"])],
    targets: [
        .target(name: "FoundationModelsPOC"),
        .executableTarget(name: "FoundationModelsProbe", dependencies: ["FoundationModelsPOC"]),
        .executableTarget(name: "FoundationModelsSessionProbe", dependencies: ["FoundationModelsPOC"]),
        .testTarget(
            name: "FoundationModelsPOCTests",
            dependencies: ["FoundationModelsPOC"],
            resources: [.process("Fixtures")]
        ),
    ]
)
