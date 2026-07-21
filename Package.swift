// swift-tools-version: 6.2
import PackageDescription

// REQ: ADR-0002, ADR-0006 — the one deliberate SPM boundary; platform-neutral,
// no dependency on any host app or SwiftUI. This repo is SPM-root: WorkKit
// is the package, not an app carrying a package.
//
// ToolKit* products depend only on FoundationModels, platform frameworks, and
// ToolVocabulary — never on Recorder (see ENGINEERING.md "One package, many
// small products"): a developer can use
// ToolKitFiles with a vendor model package and no durable runs at all.
let package = Package(
    name: "WorkKit",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "ToolVocabulary", targets: ["ToolVocabulary"]),
        .library(name: "Recorder", targets: ["Recorder"]),
        .library(name: "Executors", targets: ["Executors"]),
        .library(name: "RuntimeTesting", targets: ["RuntimeTesting"]),
        .library(name: "ToolKitFiles", targets: ["ToolKitFiles"]),
        .library(name: "ToolKitWeb", targets: ["ToolKitWeb"]),
        .library(name: "ToolKitInteraction", targets: ["ToolKitInteraction"]),
        .library(name: "ToolKitForMac", targets: ["ToolKitForMac"]),
    ],
    dependencies: [
        // The only two external dependencies anywhere in the package (both pure
        // Swift, per Toni: "I generally prefer native Swift" — no bundled
        // binaries): docx is a zip container (ZIPFoundation), and fetch_url
        // renders HTML to Markdown by walking a real DOM (SwiftSoup) rather
        // than hand-rolled regex.
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.5"),
    ],
    targets: [
        .target(name: "ToolVocabulary"),
        .target(name: "Recorder", dependencies: ["ToolVocabulary"]),
        .target(name: "Executors", dependencies: ["ToolVocabulary"]),
        .target(name: "RuntimeTesting"),
        .target(
            name: "ToolKitFiles",
            dependencies: ["ToolVocabulary", .product(name: "ZIPFoundation", package: "ZIPFoundation")]
        ),
        .target(
            name: "ToolKitWeb",
            dependencies: ["ToolVocabulary", .product(name: "SwiftSoup", package: "SwiftSoup")]
        ),
        .target(name: "ToolKitInteraction", dependencies: ["ToolVocabulary"]),
        .target(
            name: "ToolKitForMac",
            dependencies: ["ToolKitFiles", "ToolKitWeb", "ToolKitInteraction"]
        ),
        .testTarget(
            name: "RecorderTests",
            dependencies: ["Recorder", "RuntimeTesting", "ToolVocabulary"]
        ),
        .testTarget(
            name: "ExecutorsTests",
            dependencies: ["Executors"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "ToolKitFilesTests",
            dependencies: ["ToolKitFiles"]
        ),
        .testTarget(
            name: "ToolKitWebTests",
            dependencies: ["ToolKitWeb"]
        ),
        .testTarget(
            name: "ToolKitInteractionTests",
            dependencies: ["ToolKitInteraction"]
        ),
        // Gated live-provider smoke tests hitting real endpoints — see
        // Tests/ExecutorsLiveTests/LiveTestSupport.swift for the run command and gating
        // pattern. `swift test` alone runs zero of these; they self-skip without keys.
        .testTarget(
            name: "ExecutorsLiveTests",
            dependencies: ["Executors", "ToolKitFiles", "Recorder"]
        ),
    ]
)
