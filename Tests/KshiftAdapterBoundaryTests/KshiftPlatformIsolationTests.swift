import Foundation
import XCTest

final class KshiftPlatformIsolationTests: XCTestCase {
  func testSharedTargetsDoNotImportPlatformOrTransportFrameworks() throws {
    let root = repositoryRoot()
    let sharedDirectories = [
      root.appending(path: "Sources/KshiftCore"),
      root.appending(path: "Sources/KshiftPresentation"),
      root.appending(path: "Sources/KshiftFFI"),
      root.appending(path: "Sources/KshiftUI"),
    ]
    let forbiddenImports = [
      "AppKit",
      "UIKit",
      "Network",
      "FoundationNetworking",
      "GRPC",
      "NIO",
      "PostgresNIO",
      "SQLKit",
      "SwiftProtobuf",
    ]

    for directory in sharedDirectories {
      for file in try swiftFiles(in: directory) {
        let source = try String(contentsOf: file, encoding: .utf8)
        for framework in forbiddenImports {
          XCTAssertFalse(
            source.contains("import \(framework)"),
            "\(file.path) must not import \(framework)"
          )
        }
      }
    }
  }

  func testConditionalOSCompilationIsConfinedToAllowedBoundaries() throws {
    let root = repositoryRoot()
    let sourceDirectories = [
      root.appending(path: "Sources"),
      root.appending(path: "Apps"),
    ]
    let allowedPrefixes = [
      "Apps/",
      "Sources/KshiftAppKitAdapter/",
      "Sources/KshiftUIKitAdapter/",
    ]

    for directory in sourceDirectories {
      for file in try swiftFiles(in: directory) {
        let relativePath = file.path.replacingOccurrences(of: root.path + "/", with: "")
        let source = try String(contentsOf: file, encoding: .utf8)
        guard source.contains("#if os(") else {
          continue
        }
        XCTAssertTrue(
          allowedPrefixes.contains(where: { relativePath.hasPrefix($0) }),
          "#if os is not allowed in \(relativePath)"
        )
      }
    }
  }

  func testBothAppEntrypointsComposeTheSameSharedFeature() throws {
    let root = repositoryRoot()
    let macEntry = root.appending(path: "Apps/KshiftMacOS/KshiftMacOSApp.swift")
    let iosEntry = root.appending(path: "Apps/KshiftIOS/KshiftIOSApp.swift")
    let sharedFeature = root.appending(path: "Sources/KshiftUI/KshiftRootView.swift")

    let macSource = try String(contentsOf: macEntry, encoding: .utf8)
    let iosSource = try String(contentsOf: iosEntry, encoding: .utf8)

    XCTAssertTrue(macSource.contains("KshiftRootView(model: model)"))
    XCTAssertTrue(iosSource.contains("KshiftRootView(model: model)"))

    let featureFiles = try swiftFiles(in: root.appending(path: "Sources/KshiftUI"))
      .filter { $0.lastPathComponent == "KshiftRootView.swift" }
    XCTAssertEqual(featureFiles.map(\.standardizedFileURL), [sharedFeature.standardizedFileURL])
  }

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func swiftFiles(in directory: URL) throws -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      )
    else {
      return []
    }

    var files: [URL] = []
    for case let file as URL in enumerator where file.pathExtension == "swift" {
      files.append(file)
    }
    return files
  }
}
