// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "Kshift",
  defaultLocalization: "zh-Hans",
  platforms: [
    .macOS("26.0"),
    .iOS("26.0"),
  ],
  products: [
    .library(name: "KshiftCore", targets: ["KshiftCore"]),
    .library(name: "KshiftPresentation", targets: ["KshiftPresentation"]),
    .library(name: "KshiftFFI", targets: ["KshiftFFI"]),
    .library(name: "KshiftUI", targets: ["KshiftUI"]),
    .library(name: "KshiftAppKitAdapter", targets: ["KshiftAppKitAdapter"]),
    .library(name: "KshiftUIKitAdapter", targets: ["KshiftUIKitAdapter"]),
  ],
  targets: [
    .target(name: "KshiftCore"),
    .target(name: "KshiftPresentation"),
    .target(
      name: "KshiftFFI",
      dependencies: ["KshiftPresentation"]
    ),
    .target(
      name: "KshiftUI",
      dependencies: ["KshiftCore", "KshiftPresentation", "KshiftFFI"]
    ),
    .target(
      name: "KshiftAppKitAdapter",
      dependencies: ["KshiftPresentation"]
    ),
    .target(
      name: "KshiftUIKitAdapter",
      dependencies: ["KshiftPresentation"]
    ),
    .testTarget(
      name: "KshiftCoreTests",
      dependencies: ["KshiftCore", "KshiftUI"]
    ),
    .testTarget(
      name: "KshiftPresentationTests",
      dependencies: ["KshiftPresentation"]
    ),
    .testTarget(
      name: "KshiftFeatureTests",
      dependencies: ["KshiftPresentation", "KshiftFFI", "KshiftUI"]
    ),
    .testTarget(
      name: "KshiftAdapterBoundaryTests",
      dependencies: [
        "KshiftPresentation",
        "KshiftAppKitAdapter",
        "KshiftUIKitAdapter",
      ]
    ),
  ]
)
