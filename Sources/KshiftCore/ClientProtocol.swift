import Foundation

public protocol KshiftClientProtocol: Sendable {
    var actorID: String { get }
    func projects() async throws -> [ProjectSummary]
    func snapshot(projectID: String) async throws -> ProjectSnapshot
    func execute(projectID: String, envelope: CommandEnvelope) async throws -> CommandResponse
}

public enum KshiftClientError: LocalizedError, Sendable {
    case ffiUnavailable(String)
    case invalidResponse(String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case let .ffiUnavailable(message):
            "Rust FFI 不可用：\(message)"
        case let .invalidResponse(message):
            "Rust 返回了无效响应：\(message)"
        case let .transport(message):
            "Rust client 调用失败：\(message)"
        }
    }
}
