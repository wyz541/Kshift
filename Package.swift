// swift-tools-version: 6.1
import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .path

let package = Package(
  name: "Kshift",
  defaultLocalization: "zh-Hans",
  platforms: [
    .macOS("26.0"),
    .iOS("26.0"),
  ],
  products: [
    .library(name: "KshiftPresentation", targets: ["KshiftPresentation"]),
    .library(name: "KshiftFFI", targets: ["KshiftFFI"]),
    .library(name: "KshiftUI", targets: ["KshiftUI"]),
    .library(name: "KshiftAppKitAdapter", targets: ["KshiftAppKitAdapter"]),
    .library(name: "KshiftUIKitAdapter", targets: ["KshiftUIKitAdapter"]),
  ],
  targets: [
    .target(name: "KshiftPresentation"),
    .systemLibrary(name: "CKshiftFFI", path: "include"),
    .target(
      name: "KshiftFFI",
      dependencies: ["KshiftPresentation", "CKshiftFFI"],
      linkerSettings: [
        .unsafeFlags(["-L", "\(packageDirectory)/target/debug"]),
        .linkedLibrary("kshift_ffi"),
      ]
    ),
    .target(
      name: "KshiftUI",
      dependencies: ["KshiftPresentation", "KshiftFFI"]
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
      name: "KshiftPresentationTests",
      dependencies: ["KshiftPresentation"]
    ),
    .testTarget(
      name: "KshiftFFITests",
      dependencies: ["KshiftFFI"]
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
