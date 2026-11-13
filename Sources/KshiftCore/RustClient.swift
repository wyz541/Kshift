import Darwin
import Foundation

public final class RustClient: KshiftClientProtocol, @unchecked Sendable {
    public let actorID: String
    private let libraryResult: Result<RustFFILibrary, KshiftClientError>

    public init(actorID: String = "person-mia") {
        self.actorID = actorID
        do {
            self.libraryResult = .success(try RustFFILibrary())
        } catch let error as KshiftClientError {
            self.libraryResult = .failure(error)
        } catch {
            self.libraryResult = .failure(.ffiUnavailable(error.localizedDescription))
        }
    }

    public func projects() async throws -> [ProjectSummary] {
        try await Task.detached { [libraryResult] in
            let library = try libraryResult.get()
            let raw = try library.projectsJSON()
            let decoder = JSONDecoder()
            let response = try decoder.decode(ProjectsResponse.self, from: Data(raw.utf8))
            if let error = response.error {
                throw KshiftClientError.transport("\(error.code): \(error.message)")
            }
            guard response.ok, let projects = response.projects else {
                throw KshiftClientError.invalidResponse(raw)
            }
            return projects
        }.value
    }

    public func snapshot(projectID: String) async throws -> ProjectSnapshot {
        try await Task.detached { [libraryResult] in
            let library = try libraryResult.get()
            let raw = try library.snapshotJSON(projectID: projectID)
            let decoder = JSONDecoder()
            let response = try decoder.decode(SnapshotResponse.self, from: Data(raw.utf8))
            if let error = response.error {
                throw KshiftClientError.transport("\(error.code): \(error.message)")
            }
            guard response.ok, let snapshot = response.snapshot else {
                throw KshiftClientError.invalidResponse(raw)
            }
            return snapshot
        }.value
    }

    public func execute(
        projectID: String,
        envelope: CommandEnvelope
    ) async throws -> CommandResponse {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let requestData = try encoder.encode(envelope)
        guard let request = String(data: requestData, encoding: .utf8) else {
            throw KshiftClientError.invalidResponse("命令不是合法 UTF-8")
        }

        return try await Task.detached { [libraryResult] in
            let library = try libraryResult.get()
            let raw = try library.executeJSON(projectID: projectID, requestJSON: request)
            let decoder = JSONDecoder()
            do {
                return try decoder.decode(CommandResponse.self, from: Data(raw.utf8))
            } catch {
                throw KshiftClientError.invalidResponse("\(error.localizedDescription): \(raw)")
            }
        }.value
    }
}

private final class RustFFILibrary: @unchecked Sendable {
    typealias NewFn = @convention(c) () -> UnsafeMutableRawPointer?
    typealias ClientFreeFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias ProjectsJSONFn = @convention(c) (UnsafeRawPointer?) -> UnsafeMutablePointer<CChar>?
    typealias SnapshotJSONFn = @convention(c) (
        UnsafeRawPointer?,
        UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<CChar>?
    typealias ExecuteJSONFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<CChar>?
    typealias StringFreeFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    private let handle: UnsafeMutableRawPointer
    private let clientFree: ClientFreeFn
    private let projectsJSONFunction: ProjectsJSONFn
    private let snapshotJSONFunction: SnapshotJSONFn
    private let executeJSONFunction: ExecuteJSONFn
    private let stringFree: StringFreeFn

    init() throws {
        guard let libraryPath = Self.libraryPath() else {
            throw KshiftClientError.ffiUnavailable("找不到 libkshift_ffi.dylib")
        }
        guard let dynamicLibrary = dlopen(libraryPath, RTLD_NOW | RTLD_LOCAL) else {
            let message = dlerror().map { String(cString: $0) } ?? "dlopen 失败"
            throw KshiftClientError.ffiUnavailable(message)
        }

        self.clientFree = try Self.load("kshift_client_free", from: dynamicLibrary)
        let newClient: NewFn = try Self.load("kshift_client_new", from: dynamicLibrary)
        self.projectsJSONFunction = try Self.load("kshift_client_projects_json", from: dynamicLibrary)
        self.snapshotJSONFunction = try Self.load("kshift_client_snapshot_json", from: dynamicLibrary)
        self.executeJSONFunction = try Self.load("kshift_client_execute_json", from: dynamicLibrary)
        self.stringFree = try Self.load("kshift_string_free", from: dynamicLibrary)

        guard let handle = newClient() else {
            throw KshiftClientError.ffiUnavailable("kshift_client_new 返回空 handle")
        }
        self.handle = handle
    }

    deinit {
        clientFree(handle)
    }

    func projectsJSON() throws -> String {
        try consume(projectsJSONFunction(handle))
    }

    func snapshotJSON(projectID: String) throws -> String {
        try projectID.withCString { projectPointer in
            try consume(snapshotJSONFunction(handle, projectPointer))
        }
    }

    func executeJSON(projectID: String, requestJSON: String) throws -> String {
        try projectID.withCString { projectPointer in
            try requestJSON.withCString { requestPointer in
                try consume(executeJSONFunction(handle, projectPointer, requestPointer))
            }
        }
    }

    private func consume(_ pointer: UnsafeMutablePointer<CChar>?) throws -> String {
        guard let pointer else {
            throw KshiftClientError.ffiUnavailable("Rust FFI 返回空字符串")
        }
        defer { stringFree(pointer) }
        return String(cString: pointer)
    }

    private static func load<T>(_ symbol: String, from library: UnsafeMutableRawPointer) throws -> T {
        guard let pointer = dlsym(library, symbol) else {
            let message = dlerror().map { String(cString: $0) } ?? "缺少符号 \(symbol)"
            throw KshiftClientError.ffiUnavailable(message)
        }
        return unsafeBitCast(pointer, to: T.self)
    }

    private static func libraryPath() -> String? {
        var candidates: [String] = []
        if let explicit = ProcessInfo.processInfo.environment["KSHIFT_FFI_PATH"] {
            candidates.append(explicit)
        }
        if let frameworks = Bundle.main.privateFrameworksPath {
            candidates.append("\(frameworks)/libkshift_ffi.dylib")
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libkshift_ffi.dylib").path)
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("libkshift_ffi.dylib").path)
        }
        let current = FileManager.default.currentDirectoryPath
        candidates.append("\(current)/.build/ffi/macos/libkshift_ffi.dylib")
        candidates.append("\(current)/.build/ffi/ios-simulator/libkshift_ffi.dylib")
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
    }
}
