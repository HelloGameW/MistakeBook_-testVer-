// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MistakeKit",
    platforms: [.iOS("26.0"), .macOS(.v14)],
    products: [
        .library(name: "Contracts", targets: ["Contracts"]),
        .library(name: "Intelligence", targets: ["Intelligence"]),
        .library(name: "Storage", targets: ["Storage"]),
        .library(name: "Workflow", targets: ["Workflow"]),
        .library(name: "UI", targets: ["UI"]),
        .library(name: "Export", targets: ["Export"]),
        .library(name: "TestSupport", targets: ["TestSupport"]),
        .library(name: "PreviewSupport", targets: ["PreviewSupport"])
    ],
    dependencies: [],
    targets: [
        .target(name: "Contracts"),
        .target(name: "Intelligence", dependencies: ["Contracts"]),
        .target(name: "Storage", dependencies: ["Contracts"]),
        .target(name: "Workflow", dependencies: ["Contracts"]),
        .target(name: "UI", dependencies: ["Contracts"]),
        .target(name: "Export", dependencies: ["Contracts"]),
        .target(name: "TestSupport", dependencies: ["Contracts"]),
        .target(name: "PreviewSupport", dependencies: ["Contracts", "UI", "TestSupport"]),
        .testTarget(name: "ContractsTests", dependencies: ["Contracts", "TestSupport"], resources: [.copy("Fixtures")]),
        .testTarget(name: "IntelligenceTests", dependencies: ["Contracts", "Intelligence", "TestSupport"]),
        .testTarget(name: "StorageTests", dependencies: ["Contracts", "Storage", "TestSupport"]),
        .testTarget(name: "WorkflowTests", dependencies: ["Contracts", "Workflow", "Storage", "Intelligence", "Export", "TestSupport"]),
        .testTarget(name: "UITests", dependencies: ["Contracts", "UI", "TestSupport"]),
        .testTarget(name: "ExportTests", dependencies: ["Contracts", "Export", "TestSupport"])
    ],
    swiftLanguageModes: [.v6]
)
