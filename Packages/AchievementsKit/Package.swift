// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AchievementsKit",
    platforms: [.iOS("26.0"), .macOS(.v14)],
    products: [
        .library(name: "AchievementsKit", targets: ["AchievementsKit"]),
        .executable(name: "AchievementsKitValidation", targets: ["AchievementsKitValidation"])
    ],
    targets: [
        .target(name: "AchievementsKit"),
        .executableTarget(name: "AchievementsKitValidation", dependencies: ["AchievementsKit"]),
        .testTarget(name: "AchievementsKitTests", dependencies: ["AchievementsKit"])
    ],
    swiftLanguageModes: [.v6]
)
