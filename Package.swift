// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Kshift",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "KshiftCore", targets: ["KshiftCore"]),
        .library(name: "KshiftUI", targets: ["KshiftUI"]),
        .library(name: "KshiftPlatform", targets: ["KshiftPlatform"]),
    ],
    targets: [
        .target(
            name: "KshiftCore",
            path: "Sources/KshiftCore"
        ),
        .target(
            name: "KshiftUI",
            dependencies: ["KshiftCore"],
            path: "Sources/KshiftUI"
        ),
        .target(
            name: "KshiftPlatform",
            dependencies: ["KshiftUI"],
            path: "Sources/KshiftPlatform"
        ),
        .testTarget(
            name: "KshiftCoreTests",
            dependencies: ["KshiftCore", "KshiftUI"],
            path: "Tests/KshiftCoreTests"
        ),
    ]
)
