import CKshiftFFI
import Foundation

public enum KshiftFFIStatus {
    public static let invalidArgument = KSHIFT_STATUS_INVALID_ARGUMENT.rawValue
    public static let invalidState = KSHIFT_STATUS_INVALID_STATE.rawValue
    public static let unauthenticated = KSHIFT_STATUS_UNAUTHENTICATED.rawValue
    public static let permissionDenied = KSHIFT_STATUS_PERMISSION_DENIED.rawValue
    public static let notFound = KSHIFT_STATUS_NOT_FOUND.rawValue
    public static let conflict = KSHIFT_STATUS_CONFLICT.rawValue
    public static let protocolError = KSHIFT_STATUS_PROTOCOL_ERROR.rawValue
}

public struct KshiftCFFIError: Error, LocalizedError, Sendable {
    public let status: UInt32
    public let code: String
    public let message: String
    public let retryable: Bool
    public let currentRevision: UInt64?
    public let entityID: String?
    public let entityVersion: UInt64?

    public var errorDescription: String? { message }
}

private struct ErrorEnvelope: Decodable {
    let code: String
    let message: String
    let retryable: Bool
    let current_revision: UInt64?
    let entity_id: String?
    let entity_version: UInt64?
}

private func lastError(status: KshiftStatus) -> KshiftCFFIError {
    var buffer = KshiftBuffer(data: nil, len: 0, capacity: 0)
    var envelope: ErrorEnvelope?
    if kshift_last_error_json(&buffer) == KSHIFT_STATUS_OK {
        if let data = copyBuffer(&buffer) {
            envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
        }
    }
    return KshiftCFFIError(
        status: status.rawValue,
        code: envelope?.code ?? "unknown",
        message: envelope?.message ?? "Kshift operation failed",
        retryable: envelope?.retryable ?? false,
        currentRevision: envelope?.current_revision,
        entityID: envelope?.entity_id,
        entityVersion: envelope?.entity_version
    )
}

private func copyBuffer(_ buffer: inout KshiftBuffer) -> Data? {
    guard let pointer = buffer.data else {
        _ = kshift_buffer_free(&buffer)
        return nil
    }
    let data = Data(bytes: pointer, count: buffer.len)
    _ = kshift_buffer_free(&buffer)
    return data
}

private func check(_ status: KshiftStatus) throws {
    if status != KSHIFT_STATUS_OK {
        throw lastError(status: status)
    }
}

private func withSlice<T>(_ data: Data, _ body: (KshiftSlice) throws -> T) rethrows -> T {
    try data.withUnsafeBytes { rawBuffer in
        let pointer = rawBuffer.bindMemory(to: UInt8.self).baseAddress
        return try body(KshiftSlice(data: pointer, len: rawBuffer.count))
    }
}

private func readBuffer(_ status: KshiftStatus, _ buffer: inout KshiftBuffer) throws -> Data {
    try check(status)
    guard let data = copyBuffer(&buffer) else {
        return Data()
    }
    return data
}

public final class KshiftCancelToken: @unchecked Sendable {
    private var handle: UnsafeMutableRawPointer?

    public init() throws {
        var handle: UnsafeMutableRawPointer?
        try check(kshift_cancel_token_create(&handle))
        self.handle = handle
    }

    public func cancel() {
        guard let handle else { return }
        _ = kshift_cancel_token_cancel(handle)
    }

    deinit {
        guard let handle else { return }
        _ = kshift_cancel_token_destroy(handle)
    }
}

public final class KshiftClient: @unchecked Sendable {
    private var handle: UnsafeMutableRawPointer?

    public init(
        endpoint: String,
        caPEM: Data,
        tlsDomain: String? = nil,
        defaultDeadlineMilliseconds: UInt64 = 10_000,
        maxResponseBytes: Int = 16 * 1024 * 1024
    ) throws {
        let endpointData = Data(endpoint.utf8)
        let domainData = Data((tlsDomain ?? "").utf8)
        var handle: UnsafeMutableRawPointer?
        let status = endpointData.withUnsafeBytes { endpointRaw in
            caPEM.withUnsafeBytes { caRaw in
                domainData.withUnsafeBytes { domainRaw in
                    var config = KshiftClientConfig(
                        endpoint_utf8: KshiftSlice(
                            data: endpointRaw.bindMemory(to: UInt8.self).baseAddress,
                            len: endpointRaw.count
                        ),
                        ca_pem: KshiftSlice(
                            data: caRaw.bindMemory(to: UInt8.self).baseAddress,
                            len: caRaw.count
                        ),
                        tls_domain_utf8: KshiftSlice(
                            data: domainRaw.bindMemory(to: UInt8.self).baseAddress,
                            len: domainRaw.count
                        ),
                        default_deadline_ms: defaultDeadlineMilliseconds,
                        max_response_bytes: maxResponseBytes
                    )
                    return withUnsafePointer(to: &config) { configPointer in
                        kshift_client_create(configPointer, &handle)
                    }
                }
            }
        }
        try check(status)
        self.handle = handle
    }

    public func updateToken(_ token: String) throws {
        guard let handle else { throw lastError(status: KSHIFT_STATUS_INVALID_HANDLE) }
        try withSlice(Data(token.utf8)) { slice in
            try check(kshift_client_update_token(handle, slice))
        }
    }

    public func clearToken() throws {
        guard let handle else { throw lastError(status: KSHIFT_STATUS_INVALID_HANDLE) }
        try check(kshift_client_clear_token(handle))
    }

    public func clearCaches() throws {
        guard let handle else { throw lastError(status: KSHIFT_STATUS_INVALID_HANDLE) }
        try check(kshift_client_clear_caches(handle))
    }

    public func cacheAttachment(sha256Hex: String, bytes: Data) throws {
        guard let handle else { throw lastError(status: KSHIFT_STATUS_INVALID_HANDLE) }
        let keyData = Data(sha256Hex.utf8)
        try keyData.withUnsafeBytes { keyRaw in
            try bytes.withUnsafeBytes { valueRaw in
                let keySlice = KshiftSlice(
                    data: keyRaw.bindMemory(to: UInt8.self).baseAddress,
                    len: keyRaw.count
                )
                let valueSlice = KshiftSlice(
                    data: valueRaw.bindMemory(to: UInt8.self).baseAddress,
                    len: valueRaw.count
                )
                try check(kshift_client_cache_attachment(handle, keySlice, valueSlice))
            }
        }
    }

    public func cachedAttachment(sha256Hex: String) throws -> Data {
        guard let handle else { throw lastError(status: KSHIFT_STATUS_INVALID_HANDLE) }
        var buffer = KshiftBuffer(data: nil, len: 0, capacity: 0)
        let status = withSlice(Data(sha256Hex.utf8)) { slice in
            kshift_client_get_cached_attachment(handle, slice, &buffer)
        }
        return try readBuffer(status, &buffer)
    }

    public func clearAttachmentCache() throws {
        guard let handle else { throw lastError(status: KSHIFT_STATUS_INVALID_HANDLE) }
        try check(kshift_client_clear_attachment_cache(handle))
    }

    public func clearProjectCache(projectID: String) throws {
        guard let handle else { throw lastError(status: KSHIFT_STATUS_INVALID_HANDLE) }
        try withSlice(Data(projectID.utf8)) { slice in
            try check(kshift_client_clear_project_cache(handle, slice))
        }
    }

    public func listProjects(
        deadlineMilliseconds: UInt64 = 10_000,
        cancel: KshiftCancelToken? = nil
    ) throws -> Data {
        guard let handle else { throw lastError(status: KSHIFT_STATUS_INVALID_HANDLE) }
        var buffer = KshiftBuffer(data: nil, len: 0, capacity: 0)
        let status = kshift_client_list_projects(handle, deadlineMilliseconds, cancel?.rawHandle, &buffer)
        return try readBuffer(status, &buffer)
    }

    public func snapshot(
        projectID: String,
        deadlineMilliseconds: UInt64 = 10_000,
        cancel: KshiftCancelToken? = nil
    ) throws -> Data {
        guard let handle else { throw lastError(status: KSHIFT_STATUS_INVALID_HANDLE) }
        var buffer = KshiftBuffer(data: nil, len: 0, capacity: 0)
        let status = withSlice(Data(projectID.utf8)) { slice in
            kshift_client_get_snapshot(handle, slice, deadlineMilliseconds, cancel?.rawHandle, &buffer)
        }
        return try readBuffer(status, &buffer)
    }

    public func planDepthSnapshot(
        projectID: String,
        deadlineMilliseconds: UInt64 = 10_000,
        cancel: KshiftCancelToken? = nil
    ) throws -> Data {
        guard let handle else { throw lastError(status: KSHIFT_STATUS_INVALID_HANDLE) }
        var buffer = KshiftBuffer(data: nil, len: 0, capacity: 0)
        let status = withSlice(Data(projectID.utf8)) { slice in
            kshift_client_get_plan_depth_snapshot(
                handle,
                slice,
                deadlineMilliseconds,
                cancel?.rawHandle,
                &buffer
            )
        }
        return try readBuffer(status, &buffer)
    }

    public func cachedSnapshot(projectID: String) throws -> Data {
        guard let handle else { throw lastError(status: KSHIFT_STATUS_INVALID_HANDLE) }
        var buffer = KshiftBuffer(data: nil, len: 0, capacity: 0)
        let status = withSlice(Data(projectID.utf8)) { slice in
            kshift_client_get_cached_snapshot(handle, slice, &buffer)
        }
        return try readBuffer(status, &buffer)
    }

    public func executeCommand(
        _ commandJSON: Data,
        deadlineMilliseconds: UInt64 = 10_000,
        cancel: KshiftCancelToken? = nil
    ) throws -> Data {
        guard let handle else { throw lastError(status: KSHIFT_STATUS_INVALID_HANDLE) }
        var buffer = KshiftBuffer(data: nil, len: 0, capacity: 0)
        let status = withSlice(commandJSON) { slice in
            kshift_client_execute_command(handle, slice, deadlineMilliseconds, cancel?.rawHandle, &buffer)
        }
        return try readBuffer(status, &buffer)
    }

    public func executePlanDepthCommand(
        _ commandJSON: Data,
        deadlineMilliseconds: UInt64 = 10_000,
        cancel: KshiftCancelToken? = nil
    ) throws -> Data {
        guard let handle else { throw lastError(status: KSHIFT_STATUS_INVALID_HANDLE) }
        var buffer = KshiftBuffer(data: nil, len: 0, capacity: 0)
        let status = withSlice(commandJSON) { slice in
            kshift_client_execute_plan_depth_command(
                handle,
                slice,
                deadlineMilliseconds,
                cancel?.rawHandle,
                &buffer
            )
        }
        return try readBuffer(status, &buffer)
    }

    public func planDepthReport(
        projectID: String,
        startsOn: String,
        endsOn: String,
        today: String,
        deadlineMilliseconds: UInt64 = 10_000,
        cancel: KshiftCancelToken? = nil
    ) throws -> Data {
        guard let handle else { throw lastError(status: KSHIFT_STATUS_INVALID_HANDLE) }
        var buffer = KshiftBuffer(data: nil, len: 0, capacity: 0)
        let status = withSlice(Data(projectID.utf8)) { projectSlice in
            withSlice(Data(startsOn.utf8)) { startsSlice in
                withSlice(Data(endsOn.utf8)) { endsSlice in
                    withSlice(Data(today.utf8)) { todaySlice in
                        kshift_client_get_plan_depth_report(
                            handle,
                            projectSlice,
                            startsSlice,
                            endsSlice,
                            todaySlice,
                            deadlineMilliseconds,
                            cancel?.rawHandle,
                            &buffer
                        )
                    }
                }
            }
        }
        return try readBuffer(status, &buffer)
    }

    public func watchProject(
        projectID: String,
        sinceRevision: UInt64 = 0,
        cancel: KshiftCancelToken? = nil
    ) throws -> KshiftSubscription {
        guard let handle else { throw lastError(status: KSHIFT_STATUS_INVALID_HANDLE) }
        var subscription: UnsafeMutableRawPointer?
        let status = withSlice(Data(projectID.utf8)) { slice in
            kshift_client_watch_project(handle, slice, sinceRevision, cancel?.rawHandle, &subscription)
        }
        try check(status)
        return KshiftSubscription(handle: subscription)
    }

    deinit {
        guard let handle else { return }
        _ = kshift_client_destroy(handle)
    }
}

public final class KshiftSubscription: @unchecked Sendable {
    private var handle: UnsafeMutableRawPointer?

    fileprivate init(handle: UnsafeMutableRawPointer?) {
        self.handle = handle
    }

    public func next(timeoutMilliseconds: UInt64 = 1_000) throws -> Data {
        guard let handle else { throw lastError(status: KSHIFT_STATUS_INVALID_HANDLE) }
        var buffer = KshiftBuffer(data: nil, len: 0, capacity: 0)
        let status = kshift_subscription_next(handle, timeoutMilliseconds, &buffer)
        return try readBuffer(status, &buffer)
    }

    deinit {
        guard let handle else { return }
        _ = kshift_subscription_destroy(handle)
    }
}

extension KshiftCancelToken {
    fileprivate var rawHandle: UnsafeMutableRawPointer? { handle }
}
