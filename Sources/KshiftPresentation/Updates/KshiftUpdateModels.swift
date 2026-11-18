import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct KshiftVersion: Codable, Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let preview: Int?

    public init(_ value: String) throws {
        let parts = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        let core = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(core.count),
              let major = Int(core[0]),
              let minor = Int(core[1]),
              core.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              major >= 0, minor >= 0
        else {
            throw KshiftUpdateError.invalidManifest("invalid version: \(value)")
        }
        let patch = core.count == 3 ? Int(core[2]) : 0
        guard let patch, patch >= 0 else {
            throw KshiftUpdateError.invalidManifest("invalid version: \(value)")
        }
        var preview: Int?
        if parts.count == 2 {
            let suffix = parts[1]
            guard suffix.hasPrefix("preview."),
                  let number = Int(suffix.dropFirst("preview.".count)),
                  number >= 0
            else {
                throw KshiftUpdateError.invalidManifest("invalid version: \(value)")
            }
            preview = number
        }
        self.major = major
        self.minor = minor
        self.patch = patch
        self.preview = preview
    }

    public init(major: Int, minor: Int, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.preview = nil
    }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        return preview.map { "\(core)-preview.\($0)" } ?? core
    }

    public static func < (lhs: KshiftVersion, rhs: KshiftVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.preview, rhs.preview) {
        case let (left?, right?): return left < right
        case (nil, nil): return false
        case (nil, _?): return false
        case (_?, nil): return true
        }
    }
}

public enum KshiftUpdatePlatform: String, Codable, Sendable {
    case macOS = "macos"
    case iOS = "ios"
}

public struct KshiftInstalledAppInfo: Equatable, Sendable {
    public let version: KshiftVersion
    public let build: String

    public init(version: KshiftVersion, build: String) {
        self.version = version
        self.build = build
    }
}

public struct KshiftUpdateConfiguration: Sendable {
    public let manifestURL: URL
    public let releaseBaseURL: URL
    public let platform: KshiftUpdatePlatform
    public let architecture: String
    public let operatingSystemVersion: KshiftVersion
    public let installed: KshiftInstalledAppInfo

    public init(
        manifestURL: URL,
        releaseBaseURL: URL,
        platform: KshiftUpdatePlatform,
        architecture: String,
        operatingSystemVersion: KshiftVersion,
        installed: KshiftInstalledAppInfo
    ) {
        self.manifestURL = manifestURL
        self.releaseBaseURL = releaseBaseURL
        self.platform = platform
        self.architecture = architecture
        self.operatingSystemVersion = operatingSystemVersion
        self.installed = installed
    }

    public static func from(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> KshiftUpdateConfiguration {
        let platform: KshiftUpdatePlatform = {
            #if os(iOS)
            return .iOS
            #else
            return .macOS
            #endif
        }()
        let architecture: String = {
            #if arch(arm64)
            return "arm64"
            #elseif arch(x86_64)
            return "x86_64"
            #else
            return "unknown"
            #endif
        }()
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = KshiftVersion(major: os.majorVersion, minor: os.minorVersion, patch: os.patchVersion)
        let versionValue = environment["KSHIFT_APP_VERSION"]
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "0.0.0"
        let version = (try? KshiftVersion(versionValue)) ?? KshiftVersion(major: 0, minor: 0, patch: 0)
        let build = environment["KSHIFT_APP_BUILD"]
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? "0"
        let manifestURL = URL(string: environment["KSHIFT_UPDATE_MANIFEST_URL"]
            ?? "https://github.com/wyz541/Kshift/releases/latest/download/release-manifest.json")!
        let releaseBaseURL = URL(string: environment["KSHIFT_UPDATE_RELEASE_BASE_URL"]
            ?? "https://github.com/wyz541/Kshift/releases")!
        return KshiftUpdateConfiguration(
            manifestURL: manifestURL,
            releaseBaseURL: releaseBaseURL,
            platform: platform,
            architecture: architecture,
            operatingSystemVersion: osVersion,
            installed: KshiftInstalledAppInfo(version: version, build: build)
        )
    }
}

public struct KshiftReleaseAsset: Codable, Equatable, Sendable {
    public let name: String
    public let platform: KshiftUpdatePlatform
    public let architecture: String
    public let role: String
    public let sizeBytes: Int
    public let sha256: String
    public let signingStatus: String

    public init(
        name: String,
        platform: KshiftUpdatePlatform,
        architecture: String,
        role: String,
        sizeBytes: Int,
        sha256: String,
        signingStatus: String
    ) {
        self.name = name
        self.platform = platform
        self.architecture = architecture
        self.role = role
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.signingStatus = signingStatus
    }

    enum CodingKeys: String, CodingKey {
        case name
        case platform
        case architecture
        case role
        case sizeBytes = "size_bytes"
        case sha256
        case signingStatus = "signing_status"
    }
}

public struct KshiftReleaseManifest: Decodable, Equatable, Sendable {
    public let schemaVersion: String
    public let product: String
    public let version: KshiftVersion
    public let channel: String
    public let tag: String
    public let sourceCommit: String
    public let generatedAt: Date
    public let minimumOS: [KshiftUpdatePlatform: KshiftVersion]
    public let assets: [KshiftReleaseAsset]
    public let signingStatus: String
    public let releaseStatus: String
    public let releaseNotes: String?
    public let releaseURL: URL?

    public init(data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self = try decoder.decode(Self.self, from: data)
        try validate()
    }

    public init(
        schemaVersion: String = "1",
        product: String = "Kshift",
        version: KshiftVersion,
        channel: String,
        tag: String,
        sourceCommit: String,
        generatedAt: Date = .now,
        minimumOS: [KshiftUpdatePlatform: KshiftVersion],
        assets: [KshiftReleaseAsset],
        signingStatus: String,
        releaseStatus: String,
        releaseNotes: String? = nil,
        releaseURL: URL? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.product = product
        self.version = version
        self.channel = channel
        self.tag = tag
        self.sourceCommit = sourceCommit
        self.generatedAt = generatedAt
        self.minimumOS = minimumOS
        self.assets = assets
        self.signingStatus = signingStatus
        self.releaseStatus = releaseStatus
        self.releaseNotes = releaseNotes
        self.releaseURL = releaseURL
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case product
        case version
        case channel
        case tag
        case sourceCommit = "source_commit"
        case generatedAt = "generated_at"
        case minimumOS = "minimum_os"
        case assets
        case signing
        case database
        case sbom
        case provenance
        case gates
        case limitations
        case rollback
        case releaseStatus = "release_status"
        case promotion
        case releaseNotes = "release_notes"
        case releaseURL = "release_url"
    }

    enum SigningKeys: String, CodingKey {
        case status
        case identity
        case notarization
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        product = try container.decode(String.self, forKey: .product)
        version = try KshiftVersion(container.decode(String.self, forKey: .version))
        channel = try container.decode(String.self, forKey: .channel)
        tag = try container.decode(String.self, forKey: .tag)
        sourceCommit = try container.decode(String.self, forKey: .sourceCommit)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        let database = try container.decode(ReleaseDatabase.self, forKey: .database)
        guard database.engine == "postgresql", database.major == 18,
              !database.exactVersion.isEmpty, !database.schemaVersion.isEmpty,
              database.migrationDigest.count == 64,
              database.migrationDigest.allSatisfy({ $0.isHexDigit })
        else { throw KshiftUpdateError.invalidManifest("database metadata is invalid") }
        let sbom = try container.decode(ReleaseSBOM.self, forKey: .sbom)
        guard ["spdx-json", "cyclonedx-json"].contains(sbom.format),
              !sbom.file.isEmpty, sbom.sha256.count == 64,
              sbom.sha256.allSatisfy({ $0.isHexDigit })
        else { throw KshiftUpdateError.invalidManifest("SBOM metadata is invalid") }
        let provenance = try container.decode(ReleaseProvenance.self, forKey: .provenance)
        guard !provenance.workflow.isEmpty, !provenance.runID.isEmpty,
              provenance.runAttempt > 0, !provenance.artifactID.isEmpty
        else { throw KshiftUpdateError.invalidManifest("provenance metadata is invalid") }
        let gates = try container.decode([ReleaseGate].self, forKey: .gates)
        guard !gates.isEmpty, gates.allSatisfy({ ["passed", "failed", "skipped"].contains($0.status) && !$0.name.isEmpty && !$0.evidence.isEmpty })
        else { throw KshiftUpdateError.invalidManifest("gates metadata is invalid") }
        _ = try container.decode([String].self, forKey: .limitations)
        let rollback = try container.decode(ReleaseRollback.self, forKey: .rollback)
        guard ["new-patch-release", "restore-backup", "manual"].contains(rollback.strategy), !rollback.notes.isEmpty
        else { throw KshiftUpdateError.invalidManifest("rollback metadata is invalid") }
        let promotion = try container.decodeIfPresent(ReleasePromotion.self, forKey: .promotion)
        let os = try container.decode([String: String].self, forKey: .minimumOS)
        minimumOS = Dictionary(uniqueKeysWithValues: os.compactMap { key, value in
            guard let platform = KshiftUpdatePlatform(rawValue: key), let version = try? KshiftVersion(value) else { return nil }
            return (platform, version)
        })
        assets = try container.decode([KshiftReleaseAsset].self, forKey: .assets)
        let signing = try container.nestedContainer(keyedBy: SigningKeys.self, forKey: .signing)
        signingStatus = try signing.decode(String.self, forKey: .status)
        _ = try signing.decodeIfPresent(String.self, forKey: .identity)
        _ = try signing.decode(String.self, forKey: .notarization)
        releaseStatus = try container.decode(String.self, forKey: .releaseStatus)
        guard releaseStatus != "promoted" || promotion != nil else {
            throw KshiftUpdateError.invalidManifest("promoted release has no promotion record")
        }
        releaseNotes = try container.decodeIfPresent(String.self, forKey: .releaseNotes)
        releaseURL = try container.decodeIfPresent(URL.self, forKey: .releaseURL)
    }

    public func validate() throws {
        guard schemaVersion == "1", product == "Kshift" else { throw KshiftUpdateError.invalidManifest("unsupported schema or product") }
        guard tag == "v\(version)", sourceCommit.count == 40, sourceCommit.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            throw KshiftUpdateError.invalidManifest("invalid release identity")
        }
        guard channel == "stable" || channel == "preview" || channel == "hotfix" else { throw KshiftUpdateError.invalidManifest("invalid release channel") }
        guard minimumOS[.macOS] != nil, minimumOS[.iOS] != nil else { throw KshiftUpdateError.invalidManifest("minimum_os is incomplete") }
        guard !assets.isEmpty else { throw KshiftUpdateError.invalidManifest("assets is empty") }
        var names = Set<String>()
        for asset in assets {
            guard names.insert(asset.name).inserted,
                  asset.name.first?.isLetter == true || asset.name.first?.isNumber == true,
                  asset.sizeBytes > 0,
                  asset.sha256.count == 64,
                  asset.sha256.allSatisfy({ $0.isHexDigit })
            else { throw KshiftUpdateError.invalidManifest("invalid or duplicate asset metadata") }
        }
        guard ["signed", "testflight", "ad-hoc", "unsigned"].contains(signingStatus) else {
            throw KshiftUpdateError.invalidManifest("invalid signing status")
        }
        guard ["draft", "promoted", "failed"].contains(releaseStatus) else { throw KshiftUpdateError.invalidManifest("invalid release status") }
    }
}

private struct ReleaseDatabase: Decodable {
    let engine: String
    let major: Int
    let exactVersion: String
    let schemaVersion: String
    let migrationDigest: String
    enum CodingKeys: String, CodingKey {
        case engine, major
        case exactVersion = "exact_version"
        case schemaVersion = "schema_version"
        case migrationDigest = "migration_digest"
    }
}

private struct ReleaseSBOM: Decodable {
    let format: String
    let file: String
    let sha256: String
}

private struct ReleaseProvenance: Decodable {
    let workflow: String
    let runID: String
    let runAttempt: Int
    let artifactID: String
    enum CodingKeys: String, CodingKey {
        case workflow
        case runID = "run_id"
        case runAttempt = "run_attempt"
        case artifactID = "artifact_id"
    }
}

private struct ReleaseGate: Decodable {
    let name: String
    let status: String
    let evidence: String
}

private struct ReleaseRollback: Decodable {
    let strategy: String
    let notes: String
}

private struct ReleasePromotion: Decodable {
    let approvedBy: String
    let approvedAt: Date
    let runID: String
    enum CodingKeys: String, CodingKey {
        case approvedBy = "approved_by"
        case approvedAt = "approved_at"
        case runID = "run_id"
    }
}

public struct KshiftUpdateCandidate: Equatable, Sendable {
    public let manifest: KshiftReleaseManifest
    public let asset: KshiftReleaseAsset
    public let assetURL: URL
    public let releaseNotesURL: URL?
    public let distributionURL: URL
    public let releaseNotes: String?

    public init(
        manifest: KshiftReleaseManifest,
        asset: KshiftReleaseAsset,
        assetURL: URL,
        releaseNotesURL: URL?,
        distributionURL: URL,
        releaseNotes: String?
    ) {
        self.manifest = manifest
        self.asset = asset
        self.assetURL = assetURL
        self.releaseNotesURL = releaseNotesURL
        self.distributionURL = distributionURL
        self.releaseNotes = releaseNotes
    }

    public var version: KshiftVersion { manifest.version }
}

public enum KshiftUpdateCheckResult: Equatable, Sendable {
    case available(KshiftUpdateCandidate)
    case noUpdate(installed: KshiftInstalledAppInfo)
    case incompatible(version: KshiftVersion, reason: String)
    case failed(String)
}

public enum KshiftUpdateState: Equatable, Sendable {
    case idle
    case checking
    case available(KshiftUpdateCandidate)
    case noUpdate
    case incompatible(version: KshiftVersion, reason: String)
    case failed(String)
    case installing
    case installed

    public var isRetryable: Bool {
        if case .failed = self { return true }
        return false
    }
}

public enum KshiftUpdateError: LocalizedError, Equatable, Sendable {
    case invalidManifest(String)
    case network(String)
    case httpStatus(Int)
    case checksumMismatch(expected: String, actual: String)
    case signatureInvalid(String)
    case installationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidManifest(message): return "Invalid release manifest: \(message)"
        case let .network(message): return "Update check failed: \(message)"
        case let .httpStatus(status): return "Update check failed with HTTP status \(status)."
        case let .checksumMismatch(expected, actual): return "Checksum mismatch. Expected \(expected), received \(actual)."
        case let .signatureInvalid(message): return "Signature verification failed: \(message)"
        case let .installationFailed(message): return "Installation failed: \(message)"
        }
    }
}

public struct KshiftUpdateService: Sendable {
    public typealias Fetch = @Sendable (URL) async throws -> (Data, Int)

    public let configuration: KshiftUpdateConfiguration
    private let fetch: Fetch

    public init(configuration: KshiftUpdateConfiguration, fetch: @escaping Fetch = KshiftUpdateService.defaultFetch) {
        self.configuration = configuration
        self.fetch = fetch
    }

    public func checkForUpdates() async -> KshiftUpdateCheckResult {
        do {
            let (data, status) = try await fetch(configuration.manifestURL)
            guard (200..<300).contains(status) else { throw KshiftUpdateError.httpStatus(status) }
            let manifest = try KshiftReleaseManifest(data: data)
            guard manifest.releaseStatus == "promoted", manifest.channel == "stable" else {
                return .incompatible(version: manifest.version, reason: "Release is not a published Stable release.")
            }
            guard manifest.version > configuration.installed.version else {
                return .noUpdate(installed: configuration.installed)
            }
            let platform = configuration.platform
            guard let minimum = manifest.minimumOS[platform], minimum <= configuration.operatingSystemVersion else {
                return .incompatible(version: manifest.version, reason: "The release requires a newer operating system.")
            }
            let compatible = manifest.assets.filter {
                $0.platform == platform && $0.role == "application" && isArchitectureCompatible($0.architecture)
            }
            guard let asset = compatible.first else {
                return .incompatible(version: manifest.version, reason: "No compatible application asset is published for this device.")
            }
            let signingAllowed: Bool
            switch platform {
            case .macOS:
                signingAllowed = ["signed", "notarized"].contains(asset.signingStatus) && manifest.signingStatus == "signed"
            case .iOS:
                signingAllowed = ["signed", "testflight"].contains(asset.signingStatus) && ["signed", "testflight"].contains(manifest.signingStatus)
            }
            guard signingAllowed else {
                return .incompatible(version: manifest.version, reason: "The release is not signed for this platform.")
            }
            let base = manifest.releaseURL ?? configuration.releaseBaseURL.appendingPathComponent("tag").appendingPathComponent(manifest.tag)
            let distributionURL = base
            let assetURL = base.appendingPathComponent("download").appendingPathComponent(asset.name)
            let notesAsset = manifest.assets.first { $0.role == "notes" }
            let notesURL = notesAsset.map { base.appendingPathComponent("download").appendingPathComponent($0.name) }
            return .available(KshiftUpdateCandidate(
                manifest: manifest,
                asset: asset,
                assetURL: assetURL,
                releaseNotesURL: notesURL,
                distributionURL: distributionURL,
                releaseNotes: manifest.releaseNotes
            ))
        } catch let error as KshiftUpdateError {
            return .failed(error.localizedDescription)
        } catch {
            return .failed(KshiftUpdateError.network(error.localizedDescription).localizedDescription)
        }
    }

    public func downloadAndVerify(_ candidate: KshiftUpdateCandidate) async throws -> Data {
        let (data, status) = try await fetch(candidate.assetURL)
        guard (200..<300).contains(status) else { throw KshiftUpdateError.httpStatus(status) }
        guard data.count == candidate.asset.sizeBytes else {
            throw KshiftUpdateError.checksumMismatch(expected: candidate.asset.sha256, actual: "size mismatch")
        }
        let digest = SHA256Digest.hex(data)
        guard digest == candidate.asset.sha256.lowercased() else {
            throw KshiftUpdateError.checksumMismatch(expected: candidate.asset.sha256, actual: digest)
        }
        return data
    }

    private func isArchitectureCompatible(_ assetArchitecture: String) -> Bool {
        assetArchitecture == configuration.architecture || assetArchitecture == "universal" || assetArchitecture == "all"
    }

    public static let defaultFetch: Fetch = { url in
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 200)
        } catch {
            throw KshiftUpdateError.network(error.localizedDescription)
        }
    }
}

private enum SHA256Digest {
    static func hex(_ data: Data) -> String {
        #if canImport(CryptoKit)
        importCryptoKit(data)
        #else
        data.map { String(format: "%02x", $0) }.joined()
        #endif
    }

    #if canImport(CryptoKit)
    private static func importCryptoKit(_ data: Data) -> String {
        CryptoKit.SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    #endif
}
