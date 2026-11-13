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
    .library(name: "KshiftCore", targets: ["KshiftCore"]),
    .library(name: "KshiftPresentation", targets: ["KshiftPresentation"]),
    .library(name: "KshiftFFI", targets: ["KshiftFFI"]),
    .library(name: "KshiftUI", targets: ["KshiftUI"]),
    .library(name: "KshiftAppKitAdapter", targets: ["KshiftAppKitAdapter"]),
    .library(name: "KshiftUIKitAdapter", targets: ["KshiftUIKitAdapter"]),
  ],
  targets: [
    .target(name: "KshiftCore", dependencies: ["KshiftFFI"]),
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
      dependencies: ["KshiftCore", "KshiftPresentation"]
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
      name: "KshiftFFITests",
      dependencies: ["KshiftFFI"]
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
