import XCTest
@testable import KshiftPresentation

final class KshiftUpdateTests: XCTestCase {
    private let installed = KshiftInstalledAppInfo(
        version: try! KshiftVersion("1.0.0"),
        build: "100"
    )

    func testSemVerOrdersStableAfterPreview() throws {
        XCTAssertLessThan(try KshiftVersion("1.0.0-preview.2"), try KshiftVersion("1.0.0"))
        XCTAssertLessThan(try KshiftVersion("1.0.0"), try KshiftVersion("1.1.0"))
        XCTAssertGreaterThan(try KshiftVersion("2.0.0"), try KshiftVersion("1.99.99"))
    }

    func testCompatibleStableReleaseIsAvailable() async throws {
        let data = try manifestData(version: "1.1.0", channel: "stable", releaseStatus: "promoted")
        let service = KshiftUpdateService(
            configuration: configuration(platform: .macOS),
            fetch: { _ in (data, 200) }
        )

        let result = await service.checkForUpdates()
        guard case let .available(candidate) = result else {
            return XCTFail("Expected an available update, got \(result)")
        }
        XCTAssertEqual(candidate.version.description, "1.1.0")
        XCTAssertEqual(candidate.asset.platform, .macOS)
        XCTAssertEqual(candidate.releaseNotes, "Bug fixes")
        XCTAssertEqual(candidate.distributionURL.absoluteString, "https://example.test/releases/tag/v1.1.0")
        XCTAssertEqual(candidate.assetURL.absoluteString, "https://example.test/releases/download/v1.1.0/Kshift.dmg")
        XCTAssertEqual(candidate.releaseNotesURL?.absoluteString, "https://example.test/releases/download/v1.1.0/release-notes.md")
        XCTAssertEqual(candidate.manifest.assets.map(\.platform), [.macOS, .source, .server])
    }

    func testManifestAcceptsFractionalReleaseAndPromotionTimestamps() throws {
        let data = try manifestData(version: "1.1.0", channel: "stable", releaseStatus: "promoted", timestamp: "2026-11-18T00:00:00.123Z")
        let manifest = try KshiftReleaseManifest(data: data)
        XCTAssertEqual(manifest.generatedAt.timeIntervalSince1970, 1794960000.123, accuracy: 0.001)
    }

    func testUpdateConfigurationUsesInjectedHostPlatform() {
        XCTAssertEqual(KshiftUpdateConfiguration.from(platform: .iOS, environment: [:]).platform, .iOS)
        XCTAssertEqual(KshiftUpdateConfiguration.from(platform: .macOS, environment: [:]).platform, .macOS)
    }

    func testEqualOrOlderReleaseReturnsNoUpdate() async throws {
        for version in ["1.0.0", "0.9.0"] {
            let data = try manifestData(version: version, channel: "stable", releaseStatus: "promoted")
            let service = KshiftUpdateService(
                configuration: configuration(platform: .macOS),
                fetch: { _ in (data, 200) }
            )
            let result = await service.checkForUpdates()
            guard case .noUpdate = result else { return XCTFail("Expected no update for \(version), got \(result)") }
        }
    }

    func testPreviewAndDraftReleaseDoNotProduceInstallAction() async throws {
        for channel in ["preview", "stable"] {
            let status = channel == "preview" ? "promoted" : "draft"
            let data = try manifestData(version: "1.1.0", channel: channel, releaseStatus: status)
            let service = KshiftUpdateService(
                configuration: configuration(platform: .macOS),
                fetch: { _ in (data, 200) }
            )
            let result = await service.checkForUpdates()
            guard case .incompatible = result else { return XCTFail("Expected incompatible result, got \(result)") }
        }
    }

    func testUnsignedStableReleaseIsIncompatible() async throws {
        let data = try manifestData(version: "1.1.0", channel: "stable", releaseStatus: "promoted", assetSigningStatus: "unsigned", manifestSigningStatus: "unsigned")
        let service = KshiftUpdateService(
            configuration: configuration(platform: .macOS),
            fetch: { _ in (data, 200) }
        )
        let result = await service.checkForUpdates()
        guard case .incompatible = result else { return XCTFail("Expected unsigned release to be incompatible") }
    }

    func testOSAndArchitectureMismatchAreIncompatible() async throws {
        let data = try manifestData(version: "1.1.0", channel: "stable", releaseStatus: "promoted", architecture: "x86_64", minimumMacOS: "99.0")
        let service = KshiftUpdateService(
            configuration: configuration(platform: .macOS),
            fetch: { _ in (data, 200) }
        )
        let result = await service.checkForUpdates()
        guard case .incompatible = result else { return XCTFail("Expected incompatible result, got \(result)") }
    }

    func testInvalidManifestAndOfflineCheckAreRetryableFailures() async throws {
        let invalid = Data(#"{"schema_version":"1","product":"Kshift"}"#.utf8)
        let invalidService = KshiftUpdateService(
            configuration: configuration(platform: .macOS),
            fetch: { _ in (invalid, 200) }
        )
        guard case .failed = await invalidService.checkForUpdates() else { return XCTFail("Expected invalid manifest failure") }

        let offlineService = KshiftUpdateService(
            configuration: configuration(platform: .macOS),
            fetch: { _ in throw KshiftUpdateError.network("offline") }
        )
        guard case .failed = await offlineService.checkForUpdates() else { return XCTFail("Expected offline failure") }
    }

    func testChecksumMismatchPreventsDownload() async throws {
        let data = try manifestData(version: "1.1.0", channel: "stable", releaseStatus: "promoted")
        let service = KshiftUpdateService(
            configuration: configuration(platform: .macOS),
            fetch: { url in
                if url.absoluteString.contains("release-manifest") { return (data, 200) }
                return (Data("bad".utf8), 200)
            }
        )
        guard case let .available(candidate) = await service.checkForUpdates() else { return XCTFail("Expected candidate") }
        do {
            _ = try await service.downloadAndVerify(candidate)
            XCTFail("Expected checksum mismatch")
        } catch let error as KshiftUpdateError {
            guard case let .checksumMismatch(_, actual) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(actual.count, 64)
        }
    }

    private func configuration(platform: KshiftUpdatePlatform) -> KshiftUpdateConfiguration {
        KshiftUpdateConfiguration(
            manifestURL: URL(string: "https://example.test/release-manifest.json")!,
            releaseBaseURL: URL(string: "https://example.test/releases")!,
            platform: platform,
            architecture: "arm64",
            operatingSystemVersion: try! KshiftVersion("26.0"),
            installed: installed
        )
    }

    private func manifestData(
        version: String,
        channel: String,
        releaseStatus: String,
        architecture: String = "arm64",
        minimumMacOS: String = "26.0",
        assetSigningStatus: String = "signed",
        manifestSigningStatus: String = "signed",
        timestamp: String = "2026-11-18T00:00:00Z"
    ) throws -> Data {
        let assetDigest = String(repeating: "a", count: 64)
        let manifest: [String: Any] = [
            "schema_version": "1",
            "product": "Kshift",
            "version": version,
            "channel": channel,
            "tag": "v\(version)",
            "source_commit": String(repeating: "b", count: 40),
            "generated_at": timestamp,
            "minimum_os": ["macos": minimumMacOS, "ios": "26.0"],
            "database": ["engine": "postgresql", "major": 18, "exact_version": "18.0", "schema_version": "0001", "migration_digest": String(repeating: "c", count: 64)],
            "assets": [
                ["name": "Kshift.dmg", "platform": "macos", "architecture": architecture, "role": "application", "size_bytes": 3, "sha256": assetDigest, "signing_status": assetSigningStatus],
                ["name": "release-notes.md", "platform": "source", "architecture": "all", "role": "notes", "size_bytes": 9, "sha256": String(repeating: "d", count: 64), "signing_status": "not-applicable"],
                ["name": "kshift-server.tar.gz", "platform": "server", "architecture": "arm64", "role": "server-bundle", "size_bytes": 32, "sha256": assetDigest, "signing_status": "unsigned"]
            ],
            "signing": ["status": manifestSigningStatus, "identity": "Developer ID Application", "notarization": "passed"],
            "sbom": ["format": "spdx-json", "file": "sbom.json", "sha256": String(repeating: "e", count: 64)],
            "provenance": ["workflow": "release.yml", "run_id": "100", "run_attempt": 1, "artifact_id": "artifact"],
            "gates": [["name": "macos:signature", "status": "passed", "evidence": "fixture"]],
            "limitations": [],
            "rollback": ["strategy": "new-patch-release", "notes": "publish a patch"],
            "release_status": releaseStatus,
            "promotion": releaseStatus == "promoted" ? ["approved_by": "fixture", "approved_at": timestamp, "run_id": "100"] : NSNull(),
            "release_notes": "Bug fixes"
        ]
        return try JSONSerialization.data(withJSONObject: manifest)
    }
}
