// swift-tools-version: 6.2
import PackageDescription

// REQ: ADR-0002, ADR-0006 — the one deliberate SPM boundary; platform-neutral,
// no dependency on the Work Agent app or SwiftUI. `AgentKit` is a working
// name (docs/decisions/0006-native-swift-agent-loop.md); the public name is
// decided at the Publication horizon (docs/product/ROADMAP.md).
let package = Package(
    name: "AgentKit",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "ToolVocabulary", targets: ["ToolVocabulary"]),
        .library(name: "RuntimeCore", targets: ["RuntimeCore"]),
        .library(name: "Executors", targets: ["Executors"]),
        .library(name: "RuntimeTesting", targets: ["RuntimeTesting"]),
    ],
    targets: [
        .target(name: "ToolVocabulary"),
        .target(name: "RuntimeCore", dependencies: ["ToolVocabulary"]),
        .target(name: "Executors", dependencies: ["ToolVocabulary"]),
        .target(name: "RuntimeTesting"),
        .testTarget(
            name: "RuntimeCoreTests",
            dependencies: ["RuntimeCore", "RuntimeTesting", "ToolVocabulary"]
        ),
        .testTarget(
            name: "ExecutorsTests",
            dependencies: ["Executors"],
            resources: [.process("Fixtures")]
        ),
    ]
)
